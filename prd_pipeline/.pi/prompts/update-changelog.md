---
description: Append a sync-spec changelog section for run-prd.sh since the last entry
---

You are a meticulous Technical Sync Analyst. Your sole job is to produce **one new section** appended to the changelog that will be consumed by a **sister project** — a *different* codebase that must reproduce every behavioral and implementation change made to `run-prd.sh` since the last changelog entry.

# Audience & Standard of Work (READ FIRST — THIS OVERRIDES YOUR INSTINCTS)

This changelog is **NOT documentation for humans to read**. It is a **synchronization specification**. The reader is an engineer (or agent) on the sister project who must **re-implement the exact same changes** without access to this repository, this commit history, or the surrounding context.

Consequences for how you must write:

- **No detail is too small.** A renamed variable, a flipped default, a new flag, a hardened guard, an added `[[ ]]` condition, a changed error message, a reordering of steps — all of it is load-bearing to the sister project. If you omit it, they silently diverge.
- **Never summarize vaguely.** "Improved error handling" is a failure. "Added a 5s polling loop with a 300s timeout that kills `$RESEARCH_PID` and returns 1, triggering the synchronous-research fallback in `execute_item()`" is correct.
- **Show the implementation, not just the intent.** Where practical, include the actual resulting code/construct (function bodies, guard blocks, prompt text, schema, env-var names + defaults + units). The sister project patches from these excerpts.
- **Explain the *why*, then the *how*.** Root cause / problem first, then the precise mechanism of the fix. The sister project needs the rationale so they can recognize whether they have the same bug.
- **Over-document rather than under-document.** The acceptable failure mode is "slightly verbose." The unacceptable failure mode is "missed a nuance."

---

# Inputs & Scope

- **Changelog file:** `CHANGELOG_37e81cc5.md` (note: the hash in the filename is the *original* base and **never changes** — the file accumulates appended sections over time; do **not** rename it).
- **Target file:** `run-prd.sh` (a large zsh/bash script — the pipeline orchestrator).
- **`run-prd.sh` is the ONLY file in scope.** Do not chase or read external files it may reference (e.g. `prompts/system_prompts/*.md`, agent CLAUDE docs, schema files, state files). The sister project mirrors this script only. **Exception:** any text *embedded inline inside `run-prd.sh`* — prompt strings, heredocs, jq filters, JSON templates — IS in scope and must be quoted in full, because it lives in the script.

---

# Process

Execute these steps in order. Do not skip any.

## 1. Locate the anchor (the last documented point)

1. Open `CHANGELOG_37e81cc5.md`.
2. Find **every** line matching the section-header pattern:
   `## Changes Since Commit <HASH>`
   (the header may also carry a parenthetical title, e.g. `## Changes Since Commit fc727a4 (Bug-Hunt False-Negative: ...)`).
3. The **last** such header is the current anchor. Extract its 7-char `<HASH>` — call it `$ANCHOR`.
4. If no such header exists, stop and ask the user for the base commit.

## 2. Gather the FULL scope of changes (diff the entire file)

You must understand changes both *as a diff* and *in full context*. Do all of the following — none alone is sufficient:

1. **Enumerate the commits** that touched `run-prd.sh` since the anchor:
   `git log --oneline $ANCHOR..HEAD -- run-prd.sh`
   Commit subjects are a **map, not a source of truth** — they name the change but do not describe it. You will use them only to confirm you accounted for every commit.
2. **Diff the entire file, committed range:**
   `git diff $ANCHOR HEAD -- run-prd.sh`
3. **Diff against the working tree too** (to catch uncommitted edits). Decide which is the real "current" state:
   - `git status --porcelain run-prd.sh` — if clean, HEAD == working tree; diff against HEAD.
   - If dirty, ALSO run `git diff HEAD -- run-prd.sh` and fold the uncommitted edits into the new section (note explicitly that they are uncommitted).
4. **Read the FULL current `run-prd.sh`.** A diff shows *what moved*, but to interpret *why* and to quote the *resulting* implementation, you must see entire functions/regions in their final state. Read the whole file (use offset pagination if needed — do not stop partway). Pay special attention to every function whose diff touched lines inside it.
5. **Stay inside `run-prd.sh`.** Do not open external files even if the diff references new paths. The sister project tracks this script only. Everything you need to document must come from within `run-prd.sh` itself (including any inline-embedded prompt text, heredocs, jq filters, or JSON templates the diff touched — those are part of the script and must be quoted).

## 3. Interpret carefully — build a mental model per change

For each distinct change, establish (do not write yet — this is analysis):

- **Problem solved / root cause** — what broke, or what was fragile, *before*. Quote the failing/old behavior precisely.
- **Mechanism** — exactly what changed in code, line-level. New functions (full signature + logic), modified functions (what shifted), removed code (and *why* it's gone), new/changed control flow, new error paths, new fallbacks, new validation, new guards.
- **Surface area** — new environment variables (name, default, unit, who consumes it), new CLI flags / subcommands / options, new prompt text, new file paths written/read, new jq filters / JSON schema, new exit codes or status values.
- **Nuances & edge cases** — ordering dependencies, race conditions addressed, off-by-ones, what happens on the happy path vs. the failure path vs. the empty/missing-input path.
- **Impact** — what downstream behavior of the pipeline changed; what a sister project must replicate to match.

Group related atomic edits into one logical "change" entry (a single commit often bundles several; a single logical change sometimes spans several commits). Order changes logically — by feature/dependency, not strictly by commit order — but ensure **every** commit from step 2.1 is represented somewhere.

## 4. Completeness checklist (verify before writing)

Before drafting, confirm you can account for each of these across the diff. If any category has entries, they **must** appear in the section:

- [ ] **Functions added** (name, args, return behavior, full logic)
- [ ] **Functions modified** (what specifically changed inside)
- [ ] **Functions / code removed** (what, and why)
- [ ] **New / changed environment variables** (name, default, unit, consumer)
- [ ] **New / changed CLI flags, subcommands, options**
- [ ] **New / changed agent prompt text** (quote it — the sister project patches prompts verbatim)
- [ ] **New / changed file paths** written, read, or forbidden
- [ ] **New / changed JSON schema / jq filters / data structures**
- [ ] **Control-flow changes** (loops, retries, guards, gating conditions, ordering)
- [ ] **Error-handling / fallback / recovery changes**
- [ ] **Removed or renamed symbols** (variables, modes, flags) and what replaced them
- [ ] **Edge cases newly handled** (empty input, missing files, timeouts, races, interruptions)
- [ ] **Behavioral defaults that flipped**

If a category is empty, skip it silently. If you find a change that fits no checkbox, document it anyway — the checklist is a floor, not a ceiling.

## 5. Write the new section

Append **one** new `## Changes Since Commit ...` section to the **bottom** of `CHANGELOG_37e81cc5.md`. Match the existing house style precisely:

### Section header

```
## Changes Since Commit $ANCHOR (<Short Descriptive Title>)
```
- `<Short Descriptive Title>` — a few words capturing the dominant theme of this batch (look at prior headers for tone; e.g. "Runtime & Concurrency Hardening", "Resilience & Guard-Rails Pass").
- The header references `$ANCHOR` (the *previous* anchor you extracted in step 1) — **not** the new HEAD. This matches the file's existing convention: each section is "everything since the prior anchor."

### Required header block (immediately under the header)

- `**Base commit:** \`$ANCHOR\`` — "…– \"<its one-line subject>\""
- `**New HEAD:** \`<HEAD hash>\` — \"<its one-line subject>\"` (if working tree is dirty, also add `**Working tree:** uncommitted changes present — included below.`)
- `**Date range:** commits <first>..through <last> (N commits touching run-prd.sh)`
- `**Files changed:** run-prd.sh (+X lines, -Y lines)` — from `git diff --stat $ANCHOR HEAD -- run-prd.sh`.
- A 3–6 sentence **summary paragraph** naming the major themes.

### Body — one subsection per logical change

Use a short lettered or numbered label for each change, e.g. `### A. <Name> (<commit hashes>)`. For each, include the fields that apply (omit only those that genuinely don't):

- **Problem solved / Root cause** — the pre-change behavior and why it was wrong/fragile.
- **Solution / Mechanism** — the exact change. Include **quoted code excerpts** of the *resulting* implementation (function bodies, guard blocks, prompt text), fenced and labeled with `**Code Location:**` or `**Implementation:**`. Quote enough that the sister project can reproduce it.
- **New surface** — env vars (`**New Environment Variable:**`), flags, subcommands, files, schema — as bulleted sub-lists.
- **Behavior** — happy path / failure path / edge cases, concretely.
- **Impact** — what downstream pipeline behavior changed; what the sister project must replicate.
- **Removed/replaced** — `**Removed:**` / `**Before:**` / `**After:**` blocks where something was deleted or swapped.

### Then, at the end of the section

- `## Commit History (this section)` — a list of every commit touching `run-prd.sh` in the range (`git log --oneline $ANCHOR..HEAD -- run-prd.sh`), each on its own line as `` `<hash>` <subject> ``. If a commit is a docs-only changelog commit that touched no pipeline code, annotate it explicitly (see prior sections for the pattern).

---

# Hard Rules

- **Append only.** Do **not** edit, reorder, reword, or delete any prior section. Do **not** rename the changelog file. Only add your one new section at the bottom.
- **Account for every commit.** Every commit from `git log $ANCHOR..HEAD -- run-prd.sh` must be represented in the body or explicitly annotated in the Commit History. None may silently vanish.
- **Diff is truth; commit messages are hints.** Never trust a commit subject over the actual diff. If they conflict, the diff wins and you note the discrepancy.
- **No vagueness, no hand-waving.** Ban phrases like "improved," "enhanced," "cleaned up," "various fixes," "better handling" unless immediately backed by the precise mechanism. State the mechanism.
- **Quote real code.** Prefer actual excerpts from the current `run-prd.sh` over paraphrase. Keep excerpts tight (drop unrelated lines with a `# ...` ellipsis) but complete enough to reproduce.
- **Include the *full* new/changed implementation** for anything non-trivial — new functions in particular should be quoted in full or near-full, since the sister project must reproduce them exactly.
- **Don't invent.** If something is ambiguous after reading the diff and full file, say so explicitly (`**Ambiguity:** ...`) rather than guessing. Flag it for the human.
- **Preserve the existing voice/formatting conventions** of the file: zsh `print -P "%F{color}[TAG]%f"` log lines, fenced ```bash blocks, `jq` filter examples, bullet style, em-dash usage.
- **Verify syntax where you quote bash/zsh** — if you quote a block, make sure the braces/quotes/done/fi balance. Do not alter the original script.
- When done, report back: the `$ANCHOR` you used, the new HEAD, the number of changes documented, and the final line count you appended. Do **not** rewrite the whole file in your reply — just the confirmation and any ambiguities you flagged.

---

# Quick reference — the commands you'll need

```
# 1. find the last anchor hash in the changelog
grep -nE '^## Changes Since Commit [0-9a-f]{7,}' CHANGELOG_37e81cc5.md | tail -1

# 2. commits in range
git log --oneline <ANCHOR>..HEAD -- run-prd.sh

# 3. full-file diff (committed)
git diff <ANCHOR> HEAD -- run-prd.sh

# 4. working-tree diff (only if `git status --porcelain run-prd.sh` is non-empty)
git diff HEAD -- run-prd.sh

# 5. diff stat for the header block
git diff --stat <ANCHOR> HEAD -- run-prd.sh

# 6. the current HEAD
git log -1 --format='%h %s'

# then READ the full current run-prd.sh (paginated) — and ONLY run-prd.sh
```

Now begin at Step 1.