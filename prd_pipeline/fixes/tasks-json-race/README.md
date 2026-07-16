# Fix: lost-update race on `tasks.json`

## Symptom (observed in production)

A work item sat visibly at status **`Ready`** for ~10 minutes while it was in
fact being implemented, then jumped straight to `Complete`. Every other item was
already done, so it looked like the pipeline was hung on a single item with no
agent working.

## Root cause

`tsk` is an **unlocked read-modify-write**. In `task-processing/src/tsk.ts`:

- `TaskManager` constructor loads the whole file: `JSON.parse(fs.readFileSync(...))`
- `saveBacklog()` writes the whole file: `fs.writeFileSync(this.filePath, ...)`
- no `flock`, no lockfile, no atomic (temp+rename) write.

Two callers write the **same** `tasks.json` concurrently in this pipeline:

| caller | writes | where |
| --- | --- | --- |
| foreground executor | `Ready`/`Implementing`/`Complete` | `tsk_cmd update ...` (`run-prd.sh`) |
| background research supervisor subshell | `Researching`/`Ready` for items chained ahead by `RESEARCH_DEPTH` | `tsk -f "$TASKS_FILE" update ...` |

Their read-modify-write cycles can interleave. The losing interleaving for the
observed bug:

1. Supervisor finishes item N's PRP → `tsk update N Ready`
2. Foreground's `wait_for_background_research` sees the PRP → `tsk update N Implementing`
3. Supervisor finishes N+1 and calls `tsk update N+1 Ready`. Its `tsk` **read the
   file before step 2's write landed** (saw `N:Ready`), so when it writes back
   `{N:Ready, N+1:Ready}` it **clobbers N back to `Ready`**.

Nothing touches N's status again until implementation finishes, so N shows
`Ready` for the entire implementation, then jumps to `Complete` when
`restore_tasks_json "Complete"` runs. Exactly the observed behavior.

The race is probabilistic and only needs one unlucky interleave, so it doesn't
hit every item — but over a long run with depth-2 prefetch it is near-certain to
hit *some* item.

`restore_tasks_json` is also vulnerable: it re-applies preserved statuses via the
same unlocked `tsk update` calls, so a supervisor write landing *during* a restore
can clobber those too.

## Proof

`repro-lost-update.sh` reproduces tsk's exact pattern (read JSON → mutate one
node → write JSON back) with the read→write window widened so the interleave is
observable (tsk's own window is sub-ms, so it only fires under real
supervisor/foreground timing — which is what produced the stuck-`Ready` item).

```
=== BARE (no flock) ===     10/10 trials lost an update
=== LOCKED (flock wrapper) ===  10/10 trials clean
```

Run it yourself: `bash repro-lost-update.sh` (writes only under `/tmp/race-demo`).

## The fix

### Patch 1 — `run-prd.sh` (the real fix, no dependencies)

Serialize **every** read and write of `tasks.json` behind an exclusive `flock`
on a per-file lockfile. Adds one primitive, `tsk_locked()`, and routes all
access through it:

- `tsk_cmd()` now wraps `tsk_locked "$TASKS_FILE" "$@"` → covers all foreground
  reads/writes (executor: `Implementing`/`Complete`/`Failed`/`Researching`).
- The 6 direct-write sites (supervisor: `Researching`/`Ready`; `restore_tasks_json`:
  re-apply `Ready`/`Researching`/current; `cleanup_orphan_researching`) become
  `tsk_locked "$TASKS_FILE" ...` (or `tsk_locked "$tasks_file" ...` for cleanup).

The `( flock 9; ... ) 9>"${_f}.lock"` recipe scopes fd 9 to the subshell, so it
is safe under recursion and is inherited correctly by the backgrounded supervisor
subshell. Requires `flock` from `util-linux` (standard on Linux; present here).

`run_with_retry tsk_cmd update ...` sites need **no change** — they go through
`tsk_cmd`, which is now locked.

### Patch 2 — `task-processing/src/tsk.ts` (hardening)

Make `saveBacklog()` **atomic**: write to `.${basename}.${pid}.tmp` in the same
directory, then `fs.renameSync` onto the target. `rename` is atomic on the same
filesystem, so concurrent readers never see a half-written file and a crash
mid-write cannot corrupt `tasks.json`.

This does **not** by itself prevent lost updates (two unlocked writers can still
both read stale, then the second rename wins) — process-level mutual exclusion
is provided by Patch 1's flock at the shell layer. Patch 2 makes `tsk` itself
crash-safe and tear-free for any other concurrent callers.

### Optional further hardening (not in these patches)

If `tsk` is ever used by concurrent callers outside this pipeline, give
`TaskManager` real cross-process locking at the source (e.g. add the
`proper-lockfile` dependency and call `lockSync`/`unlockSync` around
load+mutate+save). Not needed as long as all writers go through `run-prd.sh`'s
flock wrapper.

## Apply (after all runs have finished)

Both projects share the git root `/home/dustin/projects/ai-scripts`. **Do not
apply while a `run-prd.sh` run is in progress** — a live run would pick up the
changed script mid-flight.

```sh
cd /home/dustin/projects/ai-scripts

# 1. Review
git apply --stat prd_pipeline/fixes/tasks-json-race/01-run-prd-flock-locking.patch
git apply --stat prd_pipeline/fixes/tasks-json-race/02-tsk-atomic-write.patch

# 2. Apply
git apply prd_pipeline/fixes/tasks-json-race/01-run-prd-flock-locking.patch
git apply prd_pipeline/fixes/tasks-json-race/02-tsk-atomic-write.patch

# 3. Rebuild tsk (src -> dist; the tsk wrapper runs dist/tsk)
( cd task-processing && npm run build )

# 4. Sanity
zsh -n prd_pipeline/run-prd.sh        # script parses
( cd task-processing && npx tsc --noEmit )   # types ok
```

Verified at prep time: both patches `git apply --check` clean, `run-prd.sh`
passes `zsh -n`, and `tsk.ts` passes `tsc --noEmit`.

## What this does / does not change

- **Status accuracy after the fix**: an item being implemented will reliably show
  `Implementing` (no more silent reversion to `Ready`).
- **Performance**: negligible. Writes take milliseconds; the flock is held only
  for the duration of one `tsk` call. The supervisor and foreground were already
  effectively serialized by the OS in the common case; this only adds correctness
  for the racy interleave.
- **No behavior change** to research depth, retry logic, restore, or commit flow.
- A `${TASKS_FILE}.lock` file will appear next to each `tasks.json` (advisory
  lockfile; safe to delete when no run is active; auto-recreated on next write).
