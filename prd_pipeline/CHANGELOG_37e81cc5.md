# Changelog and Technical Specification

## Changes Since Commit 37e81cc5

**Base commit:** `37e81cc5` - "rewrite PRD spec with detailed technical implementation plan"
**Latest commit:** `ebc7157` - "fix(prd): harden nested execution guards and remove legacy bug hunt artifacts"
**Date range:** Commits b569e7f through ebc7157 (14 commits)
**Files changed:** `run-prd.sh` (+628 lines, -224 lines)

---

## Summary of Changes

This release introduces a major refactor of the bug hunt workflow with a new self-contained session architecture, enhanced task management via the `prd task` subcommand, improved session completion handling, and better artifact management. Additionally, strict operational boundaries have been added to all pipeline agents to prevent accidental pipeline corruption, and a nested execution guard prevents agents from recursively invoking the pipeline during implementation. Recent updates have further hardened these guards with session path validation, removed the separate BUG_FIX_MODE in favor of consistent SKIP_BUG_FINDING usage, and eliminated legacy `bug_hunt_tasks.json` support in favor of the new bugfix session architecture.

---

## Detailed Changelog

### 0. Background Research Timeout Fix (CURRENT)

**Problem Solved:** All pipeline instances were hanging indefinitely at "Waiting for background research to complete..." when the Claude Code CLI crashed or failed to respond. The `wait $RESEARCH_PID` call would block forever with no timeout.

**Solution:** Replaced blocking `wait` with a polling loop that:
1. Checks every 5 seconds if the process is still running
2. Checks if the PRP file was created (early success)
3. Times out after 5 minutes (configurable via `RESEARCH_TIMEOUT`)
4. Kills the stuck process and falls back to synchronous research

**Implementation:**
```bash
wait_for_background_research() {
    local id=$1
    local timeout_seconds=${RESEARCH_TIMEOUT:-300}  # 5 minute default
    local check_interval=5

    if [[ -n "$RESEARCH_PID" && "$RESEARCH_ITEM_ID" == "$id" ]]; then
        local elapsed=0
        while [[ $elapsed -lt $timeout_seconds ]]; do
            # Check if process finished
            if ! kill -0 $RESEARCH_PID 2>/dev/null; then
                wait $RESEARCH_PID 2>/dev/null
                # ... handle exit code
                return $exit_code
            fi

            # Check if PRP was created (success)
            if [[ -f "$RESEARCH_DIRNAME/PRP.md" ]]; then
                return 0
            fi

            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done

        # Timeout - kill process and fall back to sync
        kill $RESEARCH_PID 2>/dev/null
        wait $RESEARCH_PID 2>/dev/null
        return 1  # Triggers synchronous research
    fi
    return 0
}
```

**New Environment Variable:**
- `RESEARCH_TIMEOUT` - Timeout in seconds for background research (default: 300)

**Behavior:**
- Shows progress every 5 seconds: `Still waiting... (30s/300s)`
- If PRP file appears, returns success immediately
- If timeout reached, kills process and returns error
- Error triggers fallback to synchronous research in `execute_item()`

**Impact:**
- Prevents indefinite hangs when Claude Code crashes
- Provides visibility into wait progress
- Graceful degradation to synchronous mode on failure

---

### 1. Nested Execution Guard (104d93f)

**Problem Solved:** Agents could accidentally invoke `run-prd.sh` during implementation, causing recursive execution and corrupted pipeline state.

**Solution:** Added `PRP_PIPELINE_RUNNING` environment variable guard at script entry.

**Implementation:**
```bash
if [[ -n "$PRP_PIPELINE_RUNNING" && "$SKIP_BUG_FINDING" != "true" ]]; then
    echo "[ERROR] PRP Pipeline is already running. Nested execution blocked."
    echo "This script cannot be called from within an agent session."
    exit 1
fi
export PRP_PIPELINE_RUNNING=$$
```

**Behavior:**
- Sets `PRP_PIPELINE_RUNNING` to current PID on script start
- Blocks nested execution unless `SKIP_BUG_FINDING=true` (legitimate bug fix recursion)
- Provides clear error message if blocked

**Code Location:** Lines 4-17

---

### 1b. Enhanced Nested Execution Guards & Session Path Validation (a73950e)

**Problem Solved:** The original nested execution guard could be bypassed by setting `SKIP_BUG_FINDING=true` without a legitimate bugfix context. Additionally, sessions could accidentally be created in the main `plan/` directory during bug fix mode.

**Solutions:**

1. **Stricter Recursion Validation:** Now requires both `SKIP_BUG_FINDING=true` AND `PLAN_DIR` to contain "bugfix" for legitimate recursive calls.

2. **Session Creation Guards:** Added guards in `create_session()` to prevent incorrect session placement.

**Enhanced Guard Implementation:**
```bash
if [[ -n "$PRP_PIPELINE_RUNNING" ]]; then
    # Only allow through if this is a LEGITIMATE recursive call (has PLAN_DIR set to a bugfix path)
    if [[ "$SKIP_BUG_FINDING" != "true" || "$PLAN_DIR" != *"bugfix"* ]]; then
        echo "[ERROR] PRP Pipeline is already running (PID: $PRP_PIPELINE_RUNNING). Nested execution blocked."
        echo "This script cannot be called from within an agent session."
        echo "[DEBUG] SKIP_BUG_FINDING='$SKIP_BUG_FINDING' PLAN_DIR='$PLAN_DIR' PWD='$PWD'"
        exit 1
    fi
fi
```

**Session Path Validation in `create_session()`:**
```bash
# Guard: In bug fix mode, prevent creating sessions in main plan/ directory
local plan_basename=$(basename "$PLAN_DIR")
if [[ "$SKIP_BUG_FINDING" == "true" && "$plan_basename" == "plan" ]]; then
    print -P "%F{red}[ERROR]%f Attempted to create session in main plan/ during bug fix mode!"
    exit 1
fi

# Additional guard: session_dir must contain "bugfix" in bug fix mode
if [[ "$SKIP_BUG_FINDING" == "true" && "$session_dir" != *"bugfix"* ]]; then
    print -P "%F{red}[ERROR]%f Bug fix session path doesn't contain 'bugfix': $session_dir"
    exit 1
fi
```

**Debug Logging:**
- Added `[BUGFIX MODE]` and `[DEBUG]` output when entering bug fix mode
- Shows `PLAN_DIR`, `SESSION_DIR`, and `SKIP_BUG_FINDING` values for troubleshooting

---

### 1c. Removal of BUG_FIX_MODE Variable (a73950e)

**Problem Solved:** Having both `BUG_FIX_MODE` and `SKIP_BUG_FINDING` variables created confusion and potential state inconsistencies.

**Solution:** Removed `BUG_FIX_MODE` entirely in favor of using `SKIP_BUG_FINDING` consistently.

**Changes:**
- Removed `BUG_FIX_MODE=true` from recursive bug fix call
- Removed conditional task breakdown logic that used `BUG_FIX_MODE`
- All sessions now use full PRD task breakdown approach
- Cleanup phase now runs for all sessions (including bug fixes)

**Before:**
```bash
if [[ "$BUG_FIX_MODE" == "true" ]]; then
    # Simpler breakdown for bug fixes
else
    # Full PRD breakdown
fi
```

**After:**
```bash
# Full PRD breakdown for all sessions
print -P "%F{magenta}[PHASE 0]%f Generating breakdown..."
mkdir -p "$SESSION_DIR/architecture"
run_with_retry $BREAKDOWN_AGENT --system-prompt="$TASK_BREAKDOWN_SYSTEM_PROMPT" -p "$TASK_BREAKDOWN_PROMPT"
```

**Impact:**
- Simpler codebase with single source of truth for bug fix mode detection
- More consistent behavior between regular and bug fix sessions
- Bug fix sessions get proper architecture directory and cleanup

---

### 1d. Remove Legacy bug_hunt_tasks.json Support (ebc7157)

**Problem Solved:** The codebase maintained backwards compatibility with the old `bug_hunt_tasks.json` format, adding complexity and potential confusion with the new bugfix session architecture.

**Solution:** Completely removed all references to `bug_hunt_tasks.json` in favor of the new `bugfix/NNN_hash/tasks.json` structure.

**Removed Code:**
- Priority 2 check in `prd task` subcommand for `bug_hunt_tasks.json`
- `bug_hunt_tasks.json` check in `is_session_complete()` function
- `bug_hunt_tasks.json` check in bugfix session completion loops
- Auto-detection logic for legacy `bug_hunt_tasks.json` in auto-resume
- All agent prompt references to `bug_hunt_tasks.json` as forbidden file

**Updated Cleanup Rules:**
```bash
## CRITICAL - NEVER DELETE OR MOVE THESE FILES:
- **$SESSION_DIR/tasks.json** - Pipeline state tracking
- **$SESSION_DIR/prd_snapshot.md** - PRD snapshot for this session
- **$SESSION_DIR/delta_prd.md** - Delta PRD for incremental sessions
- **$SESSION_DIR/delta_from.txt** - Delta session linkage
- **PRD.md** - Product requirements document
- **$SESSION_DIR/TEST_RESULTS.md** - Bug report file
- Any file matching `*tasks*.json` pattern
- Any file directly in $SESSION_DIR/ root (NEVER MOVE to subdirectories)
```

**Impact:**
- Cleaner codebase with single bugfix session architecture
- Reduced cognitive load for understanding bug hunt workflows
- Session completion checks are simpler and more reliable

---

### 1e. Improved Delta PRD Generation (ebc7157)

**Problem Solved:** Delta sessions could get stuck if the delta PRD wasn't generated, with no way to recover. Additionally, the `get_next_item()` function assumed phase numbers matched array indices, which fails for delta sessions.

**Solutions:**

1. **Delta PRD Retry Logic:** Added retry mechanism when delta PRD isn't created on first attempt.

2. **Delta PRD Validation:** Session now fails fast if delta PRD cannot be generated.

3. **Missing Delta PRD Recovery:** Incomplete delta sessions now detect and regenerate missing delta PRDs.

4. **Fixed Phase Indexing:** `get_next_item()` now searches for phase IDs instead of using array indices.

**Delta PRD Retry Implementation:**
```bash
# Retry if delta PRD wasn't created
if [[ ! -f "$SESSION_DIR/delta_prd.md" ]]; then
    print -P "%F{yellow}[DELTA]%f delta_prd.md not found. Demanding agent write it..."
    run_with_retry $BREAKDOWN_AGENT --continue -p "You did NOT write the delta PRD file..."
fi

# Final validation - FAIL if delta PRD is still missing
if [[ ! -f "$SESSION_DIR/delta_prd.md" ]]; then
    print -P "%F{red}[ERROR]%f Delta PRD generation FAILED."
    exit 1
fi
```

**Resume Missing Delta PRD Detection:**
```bash
# Check if this is a delta session that never got its delta PRD generated
if [[ -f "$CURRENT_SESSION_DIR/delta_from.txt" && ! -f "$CURRENT_SESSION_DIR/delta_prd.md" ]]; then
    # ... find previous session and set CREATE_DELTA=true
    print -P "%F{yellow}[DELTA]%f Delta PRD missing, will regenerate from session $prev_session_num"
fi
```

**Fixed Phase Indexing in `get_next_item()`:**
```bash
# Find actual array indices by searching for matching IDs
# This handles delta sessions where P3 might be at backlog[0]
local phase_idx=-1
for (( i=0; i<total_phases; i++ )); do
    local pid=$(jq -r ".backlog[$i].id // empty" "$TASKS_FILE")
    if [[ "$pid" == "P$phase_num" ]]; then
        phase_idx=$i
        break
    fi
done
```

**Impact:**
- Delta sessions are more robust and recoverable
- Clear error messages when delta PRD generation fails
- Delta sessions with non-sequential phase IDs now work correctly

---

### 1f. New PRD Brainstormer System Prompt (ebc7157)

**Addition:** New system prompt file `prompts/system_prompts/prd-brainstormer.md` for an AI-powered PRD interrogation agent.

**Purpose:** Defines a "Requirements Interrogation and Convergence Engine" that produces comprehensive PRDs through aggressive questioning rather than invention.

**Key Features:**
- Four-phase model: Discovery → Interrogation → Convergence → Finalization
- Decision Ledger for tracking confirmed facts
- Linear questioning rule (no parallel questions that could invalidate each other)
- Testability requirements for all specs
- Impossibility detection for conflicting requirements

---

### 2. Clear Operational Boundaries for All Agents (410c9e3)

**Problem Solved:** Agents would sometimes modify pipeline state files, task files, or add plan directories to `.gitignore`, corrupting the orchestration state.

**Solution:** Added explicit "FORBIDDEN OPERATIONS" documentation to every agent prompt.

**Affected Agents:**

| Agent Type | Output Scope | Forbidden |
|------------|--------------|-----------|
| Task Breakdown | `tasks.json`, `architecture/` | PRD.md, source code, gitignore |
| Research (PRP) | `PRP.md`, `research/` | tasks.json, source code, prd_snapshot.md |
| Implementation | `src/`, `tests/`, `lib/` | plan/, PRD.md, tasks.json, pipeline scripts |
| Cleanup | `docs/` organization | plan/, PRD.md, tasks.json, session directories |
| Task Update | `tasks.json` modifications | PRD.md, source code, prd_snapshot.md |
| Validation | `validate.sh`, `validation_report.md` | plan/, source code, tasks.json |
| Bug Hunter | `TEST_RESULTS.md` (if bugs found) | plan/, source code, tasks.json |

**Standard Forbidden Operations (all agents):**
- Never modify `PRD.md` (human-owned)
- Never add `plan/`, `PRD.md`, or task files to `.gitignore`
- Never run `prd`, `run-prd.sh`, or `tsk` commands

**Implementation Notes:**
- Each agent prompt now includes a "FORBIDDEN OPERATIONS - CRITICAL" section
- Implementation agent additionally forbidden from running pipeline scripts
- Cleanup agent restricted from creating session-pattern directories (`[0-9]*_*`)

---

### 3. Simplified Bug Fix Task Breakdown (acd6d3c)

**Problem Solved:** Bug fixes were being broken down using the full PRD task hierarchy (Phases → Milestones → Tasks → Subtasks), resulting in overly complex task structures for simple bug fixes.

**Solution:** Added `BUG_FIX_MODE` flag and dedicated `BUG_FIX_BREAKDOWN_SYSTEM_PROMPT` with simpler structure.

**New Environment Variable:**
- `BUG_FIX_MODE` - When `true`, uses simplified task breakdown

**Simplified Structure:**
```json
{
  "backlog": [{
    "type": "Phase",
    "id": "P1",
    "title": "Bug Fixes",
    "milestones": [{
      "type": "Milestone",
      "id": "P1.M1",
      "title": "Critical and Major Bug Fixes",
      "tasks": [
        // ONE task per bug, 1-3 subtasks max
      ]
    }]
  }]
}
```

**Rules for Bug Fix Breakdown:**
1. ONE task per bug (no splitting)
2. 1-3 subtasks per task maximum
3. Small story points (0.5-2)
4. Direct context_scope (file + change)
5. No research or documentation tasks
6. Critical bugs ordered first

**Implementation:**
```bash
if [[ "$BUG_FIX_MODE" == "true" ]]; then
    print -P "%F{magenta}[BUG FIX]%f Generating simple bug fix task list..."
    run_with_retry $AGENT --system-prompt="$BUG_FIX_BREAKDOWN_SYSTEM_PROMPT" -p "$EXPANDED_BUG_FIX_PROMPT"
else
    # Full PRD breakdown
fi
```

**Additional Change:** Cleanup phase skipped for bug fix mode (no architecture research to organize).

---

### 4. New `prd task` Subcommand (d9bf0b3)

**Purpose:** Provides a convenient wrapper to interact with tasks in the current session without needing to know the exact tasks file path.

**Usage:**
```bash
prd task              # Show tasks for current session
prd task next         # Get next task
prd task status       # Show status
prd task -f <file>    # Override with specific file
```

**Technical Implementation:**
- Intercepts `task` as first argument before main parameter parsing
- Implements priority-based task file discovery:
  1. **Priority 1:** Incomplete bugfix session tasks (`SESSION_DIR/bugfix/NNN_hash/tasks.json`)
  2. **Priority 2:** Legacy bug hunt tasks (`SESSION_DIR/bug_hunt_tasks.json`)
  3. **Priority 3:** Main session tasks (`SESSION_DIR/tasks.json`)
- Uses `is_tasks_incomplete()` helper function to check for incomplete items
- Passes through to `tsk` command with appropriate `-f` flag

**Code Location:** Lines 13-75

---

### 5. Self-Contained Bug Fix Workflow (9382a85)

**Problem Solved:** Previous implementation had complex dependencies between parent and child sessions, with task files being passed between recursive calls, leading to state corruption and resume failures.

**Solution:** Bug fix sessions are now fully self-contained within `SESSION_DIR/bugfix/NNN_hash/` directories.

**Key Changes:**
- Removed `BUGFIX_TASKS_FILE` global variable
- Bug fix recursion no longer passes `TASKS_FILE` - child session manages its own `tasks.json`
- Bug reports (`TEST_RESULTS.md`) are stored within the bugfix session directory
- Each bug hunt iteration creates a new numbered session: `bugfix/001_abc123/`, `bugfix/002_def456/`, etc.

**Session Structure:**
```
plan/
└── 001_abc123/           # Main session
    ├── tasks.json
    ├── prd_snapshot.md
    └── bugfix/           # Bug hunt sessions
        ├── 001_def456/   # First bug hunt
        │   ├── tasks.json
        │   └── TEST_RESULTS.md
        └── 002_ghi789/   # Second bug hunt
            ├── tasks.json
            └── TEST_RESULTS.md
```

---

### 6. Bug Fix Artifact Archiving (c1cf485, 7bc3c3b)

**Problem Solved:** Bug fix artifacts were being deleted after completion, losing valuable debugging history.

**Solution:** Artifacts are now preserved within the session directory structure instead of being deleted.

**Changes:**
- Removed `rm -f` and `rm -rf` commands that deleted bug artifacts
- Bug reports and task files remain in their session directories after completion
- "Discard" option renamed to "Archive and Start New" to indicate data preservation
- Simplified archiving: files stay in place (no timestamps or renaming)

**Benefits:**
- Full audit trail of bug hunting iterations
- Ability to review past bug reports
- Debugging history preserved for analysis

---

### 7. Interactive Prompts for Bug Hunt (0edbd0c)

**Problem Solved:** Bug hunt could automatically resume corrupted or unwanted state, leading to infinite loops.

**New Interactive Prompts:**

1. **Starting new bug hunt on completed session:**
   ```
   Session complete. Ready for validation/bug hunt.
   Start bug hunt / validation? [Y/n]
   ```

2. **Resuming incomplete bug fix cycle:**
   - User prompted before resuming
   - Option to archive existing session and start fresh
   - Prevents infinite resume loops with corrupted state

**Implementation:**
- Added `read -q "choice?..."` prompts at strategic decision points
- `SKIP_EXECUTION_LOOP` flag introduced to bypass task execution while still allowing validation/bug hunt

---

### 8. Session Completion Logic Enhancement (847ac48)

**Problem Solved:** When a session was complete, the script would exit before allowing bug hunt to run on completed work.

**Solution:** Introduced `SKIP_EXECUTION_LOOP` flag.

**Behavior:**
- When session is complete AND bug hunt is enabled:
  - Prompts user to confirm bug hunt
  - Sets `SKIP_EXECUTION_LOOP=true` to bypass task execution
  - Continues to validation and bug finding stages
- Main execution loops wrapped with `SKIP_EXECUTION_LOOP` check

---

### 9. Bug Fix Directory Structure Correction (b569e7f)

**Problem Solved:** Bug fix artifacts were being written to incorrect directories due to global vs session-specific path confusion.

**Fixes:**
- Bug fix recursion now correctly uses `${SESSION_DIR}/bugfix` instead of `${PLAN_DIR}/bugfix`
- Added guards against empty `SESSION_DIR` to prevent root directory writes
- Added checks for missing bug reports before resuming bug hunt cycles

**Safety Guards Added:**
```bash
if [[ -z "$SESSION_DIR" ]]; then
    # Prevent root directory writes
fi
```

---

### 10. Tasks File Path Preservation (0cd59a6)

**Problem Solved:** Resuming a bug fix cycle would erroneously trigger a new breakdown because `TASKS_FILE` was being overwritten.

**Fix:**
```bash
# Only update TASKS_FILE if it's the default "tasks.json"
if [[ "$TASKS_FILE" == "tasks.json" ]]; then
    TASKS_FILE="$SESSION_DIR/tasks.json"
fi
```

**Impact:**
- Sub-sessions correctly execute bug fix tasks from parent session
- Prevents accidental task file switching during recursive calls

---

### 11. MCP Server Configuration for PRP Creation

**New Feature:** Web search capability for research during PRP creation.

**Implementation:**
```bash
if [[ "$AGENT" == "glp" ]]; then
    PRP_AGENT_MCP_ARGS="--mcp-config=$(mcpp z-ai-web-search-prime)"
else
    PRP_AGENT_MCP_ARGS=""
fi
```

**Usage:** MCP args are passed during PRP creation calls:
```bash
$AGENT $PRP_AGENT_MCP_ARGS -p "$PRP_CREATE_PROMPT..."
```

---

### 12. Session Hash Calculation Change

**Previous:** Hash extracted from directory name (`001_abc123` → `abc123`)

**New:** Hash computed directly from `prd_snapshot.md` file content:
```bash
get_session_hash() {
    local session_dir=$1
    local snapshot="$session_dir/prd_snapshot.md"
    if [[ -f "$snapshot" ]]; then
        hash_prd_content "$snapshot"
    else
        echo ""
    fi
}
```

**Benefit:** More reliable hash comparison since it uses the actual content rather than stored metadata.

---

### 13. Auto-Resume Logic Enhancement

**New Variables:**
- `RESUME_BUGFIX_TASKS_FILE` - Path to bug fix tasks to resume
- `RESUME_BUGFIX_SESSION` - Path to the bugfix session directory
- `AUTO_RESUME_TASKS_FILE` - Determines which file to check for auto-resume

**Priority Order for Auto-Detection:**
1. Incomplete bugfix sessions (new format)
2. Legacy `bug_hunt_tasks.json` at session level
3. Main session tasks

---

### 14. Git Command Noise Reduction

**Change:** Git commands now redirect stderr to null and use `&>/dev/null` for silent failures:
```bash
# Before
git add "$TASKS_FILE"
git commit -m "..." 2>/dev/null || true

# After
git add "$TASKS_FILE" 2>/dev/null
git commit -m "..." &>/dev/null || true
```

---

### 15. `is_session_complete()` Function Enhancement

**Extended Checks:**
- Main `tasks.json` completion status
- `bug_hunt_tasks.json` at session level (legacy)
- All bugfix session `tasks.json` files
- All bugfix session `bug_hunt_tasks.json` files

**Removed Checks:**
- Simple file existence checks for `TEST_RESULTS.md`, `bug_hunt_tasks.json`, `bug_fix_tasks.json`
- Replaced with proper task completion status checks

---

## Technical Specifications

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PRP_PIPELINE_RUNNING` | (empty) | Guard to prevent nested execution (set to PID) |
| `BUG_FINDER_AGENT` | `glp` | Agent used for bug discovery |
| `BUG_RESULTS_FILE` | `TEST_RESULTS.md` | Bug report output file |
| `BUGFIX_SCOPE` | `subtask` | Granularity for bug fix tasks |
| `SKIP_BUG_FINDING` | `false` | Skip bug hunt stage; also used to identify bug fix mode |
| `SKIP_EXECUTION_LOOP` | `false` | Skip task execution (internal) |
| `RESUME_BUGFIX_TASKS_FILE` | (empty) | Auto-detected resume file |
| `RESUME_BUGFIX_SESSION` | (empty) | Auto-detected session path |

**Removed Variables:**
- `BUG_FIX_MODE` - Removed in favor of `SKIP_BUG_FINDING` (a73950e)

### Bug Hunt Session Lifecycle

```
1. Check for existing incomplete bugfix session
   ├── Found incomplete → Resume (with user confirmation)
   └── Not found → Create new session (NNN_hash)

2. Run bug discovery
   ├── Bugs found → Write TEST_RESULTS.md to session
   └── No bugs → Clean up empty session, exit

3. Run fix pipeline (recursive call)
   ├── SKIP_BUG_FINDING=true
   ├── PRD_FILE=TEST_RESULTS.md
   └── PLAN_DIR=bugfix session path

4. On completion
   ├── Session preserved for history
   └── User notified to run again for more bugs
```

### Recursive Call Parameters

When spawning bug fix subprocess:
```bash
SKIP_BUG_FINDING=true \
PRD_FILE="$BUG_RESULTS_FILE" \
SCOPE="$BUGFIX_SCOPE" \
AGENT="$AGENT" \
PLAN_DIR="$CURRENT_BUGFIX_SESSION" \
"$0"
```

Note: `TASKS_FILE` is intentionally NOT passed - child session creates its own.

---

## Migration Notes

### From Pre-37e81cc5 Sessions

**As of ebc7157:** Legacy `bug_hunt_tasks.json` support has been removed. Sessions must use the new bugfix session architecture.

Old sessions with these files at session root level are **no longer supported**:
- ~~`bug_hunt_tasks.json`~~ - Removed in ebc7157
- ~~`bug_fix_tasks.json`~~ - Removed in ebc7157

The current format stores everything within `bugfix/NNN_hash/` subdirectories:
- `bugfix/001_hash/tasks.json` - Bug fix tasks
- `bugfix/001_hash/TEST_RESULTS.md` - Bug reports

### Breaking Changes

**ebc7157:** Removed backwards compatibility for `bug_hunt_tasks.json` at session root level. If you have old sessions using this format, you will need to manually migrate them to the new `bugfix/NNN_hash/` structure or start fresh.

---

## Files Changed

| File | Lines Added | Lines Removed |
|------|-------------|---------------|
| `run-prd.sh` | 628 | 224 |
| `CHANGELOG_37e81cc5.md` | 229 | 17 |
| `prompts/system_prompts/prd-brainstormer.md` | 241 | 0 |
| `prompts/changelog_update.md` | 1 | 0 |

---

## Commit History

| Hash | Message |
|------|---------|
| `b569e7f` | fix(prd): correct bugfix directory structure and safeguard execution |
| `0cd59a6` | fix(prd): preserve tasks file path during recursive calls |
| `847ac48` | fix(prd): allow bug hunt to proceed when session is complete |
| `0edbd0c` | fix(prd): add interactive prompts for bug hunt resume and start |
| `c1cf485` | fix(prd): archive bug fix artifacts instead of deleting them |
| `7bc3c3b` | fix(prd): simplify artifact archiving |
| `9382a85` | fix(prd): refactor bug fix workflow to be self-contained |
| `d9bf0b3` | fix(prd): enhance task subcommand and bug hunt workflow |
| `410c9e3` | fix(prd): add clear operational boundaries for all pipeline agents |
| `acd6d3c` | fix(prd): add self-contained bug fix sessions and prd task subcommand |
| `104d93f` | fix(prd): add nested execution guard and cleanup safety measures |
| `a73950e` | fix(prd): enhance nested execution guards and bug fix mode safeguards |
| `5b01ab7` | fix(prd): add nested execution guard and agent operational boundaries |
| `ebc7157` | fix(prd): harden nested execution guards and remove legacy bug hunt artifacts |

---

## Changes Since Commit ebc7157 (pi.dev Migration + Pipeline Hardening)

**Base commit:** `ebc7157`
**Latest commit:** `2b812db` (plus uncommitted staged work on `run-prd.sh`)
**Theme:** Migration from claude-code to pi.dev as the agent runtime, plus several pipeline behavior improvements surfaced while bootstrapping this script into a larger framework.

### Migration Note: pi.dev Runtime

Switched the agent runtime from `claude-code` to `pi.dev`. Agent identifiers changed (`pglp`/`clp` → `piz`/`pizt`/`pizc`), `--continue` became `--session-id` for deterministic resume, and `git commit-claude` became `git commit-pi`. These are structural adapters to the new runtime and do not change pipeline semantics — they are NOT detailed below. The functional changes that *do* affect how the pipeline behaves are:

### A. Selective PRD Section Extraction (`prd_selectors` + mdsel) — `4285ba0`, `2b812db`

Subtasks now carry a `prd_selectors` field (e.g. `["h2.1", "h3.0"]`) computed from a generated PRD section index. Downstream PRP agents receive only the referenced sections instead of the full PRD document, keeping their context windows focused on relevant requirements. Selectors are resolved via `mdsel`. Falls back to the full PRD when selectors are absent or extraction fails.

### B. Tasks.json Protection & Smart Recovery — `bdaf91a`, `59f515c`

`restore_tasks_json()` re-applies legitimate status changes after every agent run (agents routinely corrupt `tasks.json` despite being forbidden). On corruption it walks commit history to find the last valid JSON version. Interrupted/implementing items get their status re-applied, and background-research statuses (`Researching`/`Ready`) are preserved across restores rather than being dropped. This is the mechanism that makes the pipeline survivable across crashes and misbehaving agents.

### C. Planner / Implementation Model Split — staged

Separate model roles so cost/speed can be tuned per phase of the pipeline:
- `AGENT` — planning, research, PRP creation (default glm-5.2)
- `IMPL_AGENT` — code-writing steps: PRP execution and post-validation fix (default glm-5-turbo, faster codegen)

Previously one model did everything; now heavy reasoning and fast codegen are independently configurable.

### D. Depth-2 Chained Background Research — staged

Replaced single-slot prefetch with a supervisor that researches a *chain* of up to `RESEARCH_DEPTH` (default 2) items ahead while the current item is implemented. Collapses both failure modes of the single-slot design: "fast impl → stall waiting for N+1" and "slow impl → wasted idle capacity." Tracked via `RESEARCH_DIRNAMES` associative array (item_id → dirname); `wait_for_background_research()` consumes items one at a time while the supervisor keeps prefetching the rest.

### E. Issue-Driven Re-planning Loop — staged

Agents can report `"result": "issue"` (in addition to `success`/`fail`) to signal a *recoverable* planning gap rather than a hard failure. The pipeline:
1. Saves the issue message to `issue_feedback.md`
2. Deletes the stale PRP
3. Resets the item to `Planned`
4. Re-runs research with `<issue_feedback>` injected into the PRP prompt

Retries up to `ISSUE_RETRY_MAX` (default 3) times before hard-failing. Turns planning gaps into self-correcting retries instead of dead items.

### F. Classifier Transient-Failure Handling — staged

The COSMETIC/SUBSTANTIVE and CLEAN/DIRTY binary classifiers now retry up to 4 times and **distinguish transient API failures** (empty output, connection errors, rate limits, overloaded) from invalid model responses. Previously a single empty reply silently fell through to "Could not classify" and the pipeline proceeded *unprotected* through a SUBSTANTIVE PRD change.

### G. Documentation Sync in Task Breakdown — staged

`TASK_BREAKDOWN_SYSTEM_PROMPT` now enforces a two-mode documentation rule, mirroring the existing "tests ride with the work" TDD rule:
- **Mode A (doc-with-work):** docs a subtask directly touches (config, API, CLI, env vars, exported types) are updated inside that subtask's `context_scope` — declared via a new `DOCS:` line. Never a standalone subtask.
- **Mode B (changeset-level):** cross-cutting docs that only make sense once the whole change lands (`README.md`, feature overviews, architecture summaries) become a **final "Sync changeset-level documentation" task** depending on all implementing subtasks.

Mirrored in `DELTA_PRD_GENERATION_PROMPT` (step 3, SCOPE DELTA) so delta PRDs declare doc impact at authoring time. Prevents coherent changesets from shipping with stale READMEs — the exact failure that motivated this rule.

---

## Changes Since Commit e546e77 (Runtime & Concurrency Hardening)

**Base commit:** `e546e77` — "feat(prd): migrate to pi.dev runtime and add depth-2 research chaining with issue retry loop"
**Commits:** `9f526eff` (prompt-via-stdin) and `185cb24` (research-status snapshot + zsh arg splitting)
**Files changed:** `run-prd.sh` (+113 lines, -27 lines)

These are follow-on stability fixes to the pi.dev migration: one removes a hard `execve()` size ceiling that broke large-prompt runs, the other closes a race that could silently drop parallel-research statuses, plus a correctness fix to selector extraction.

### H. Prompts Routed via stdin (argv-Size Limit Bypass) — `9f526eff`

**Problem Solved:** Large prompts passed as `pi -p "$prompt"` hit the Linux kernel's `MAX_ARG_STRLEN = 131072` bytes (128KB) cap on a *single* argv string — independent of `ARG_MAX`. A PRD embedded in `-p "$TASK_BREAKDOWN_PROMPT"` easily exceeds this (a 133KB PRD produced `argument list too long: pi` here), and the failure is a hard `E2BIG` from `execve()` that no amount of wrapper trimming can fix.

**Solution:** Two new helpers feed the prompt through a temp-file-backed **stdin** instead of an argv string. With no positional prompt, `pi` reads it from stdin. The prompt is written to the temp file **once** and re-fed on every retry (a pipe would be consumed by the first attempt, starving retries).

**Implementation:**
```bash
# Retry-loop version (PRP creation, task breakdown, fix prompt, bug finder)
run_with_retry_stdin() {
    local prompt_text="$1"; shift
    local tmp
    tmp=$(mktemp -t prd-prompt.XXXXXX) || { print -P "%F{red}[ERROR]%f mktemp failed"; return 1; }
    print -r -- "$prompt_text" > "$tmp"
    local n=1 delay=5
    while true; do
        if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then rm -f "$tmp"; return 130; fi
        eval "${(q)@}" < "$tmp"
        local exit_status=$?
        if [[ $exit_status -eq 0 ]]; then rm -f "$tmp"; return 0; fi
        print -P "%F{yellow}[RETRY]%f Command failed (exit $exit_status). Attempt $n. Retrying in ${delay}s..."
        sleep $delay
        ((n++))
    done
}

# Single-shot version (background research supervisor manages its own recovery)
run_agent_stdin() { ... }  # same temp-file/stdin pattern, no retry loop
```

**Usage convention:** `<prompt_text> <agent> [agent-args...]` — callers must NOT pass `-p` or `< /dev/null`; the helper owns stdin.

**Migrated call sites:** PRP creation (both the background-research supervisor's single-shot path and `execute_item`'s retry path), task breakdown + the "demand write" retry, the post-validation `FIX_PROMPT`, and the bug-finder prompt.

**Stale-temp-file sweep:** Added at script entry to clean up temp files left behind by runs hard-killed (SIGTERM/SIGKILL/power loss) before the helpers' cleanup ran. Normal Ctrl+C already hits the graceful-shutdown path, which removes its own temp file:
```bash
rm -f -- /tmp/prd-prompt.*(N) 2>/dev/null
```

### I. Authoritative Research-Status Snapshot Pre-Revert — `185cb24`

**Problem Solved:** `restore_tasks_json()` reverts `tasks.json` to HEAD after every agent run to undo agent corruption. The background-research supervisor's legitimate `Researching`/`Ready` writes were being re-applied *after* the revert using the `RESEARCH_DIRNAMES` associative array and a `RESEARCH_PID` liveness check. That array could drift out of sync with the live supervisor — e.g. after `start_background_research` reset `RESEARCH_DIRNAMES`, or when the PID check raced the supervisor — silently dropping statuses and leaving items stuck.

**Solution:** Snapshot the supervisor's status writes from the **working tree before the revert** (authoritative — it captures exactly what the supervisor wrote), then re-apply them afterward using **filesystem evidence** as proof of legitimacy.

**Implementation:**
```bash
# Step 0: snapshot BEFORE the revert
local _snap_researching="" _snap_ready=""
if [[ "$PARALLEL_RESEARCH" == "true" && -f "$TASKS_FILE" ]] && jq empty "$TASKS_FILE" 2>/dev/null; then
    _snap_researching=$(jq -r '.. | objects | select(.status? == "Researching") | .id // empty' "$TASKS_FILE" 2>/dev/null)
    _snap_ready=$(jq -r '.. | objects | select(.status? == "Ready") | .id // empty' "$TASKS_FILE" 2>/dev/null)
fi

# ... git checkout HEAD -- "$TASKS_FILE" (the revert) ...

# Step 4: re-apply, gated on filesystem evidence
for _id in ${(f)_snap_ready}; do        # PRP.md exists  -> Ready
    _dir="$SESSION_DIR/${_id//./}"
    [[ -f "$_dir/PRP.md" ]] && tsk -f "$TASKS_FILE" update "$_id" Ready 2>/dev/null || true
done
for _id in ${(f)_snap_researching}; do   # research/ dir exists -> Researching
    _dir="$SESSION_DIR/${_id//./}"
    [[ -d "$_dir/research" ]] && tsk -f "$TASKS_FILE" update "$_id" Researching 2>/dev/null || true
done
```

**Impact:** Replaces the `RESEARCH_DIRNAMES`/`RESEARCH_PID` re-apply path. Status preservation no longer depends on the in-memory assoc array staying in sync with the live supervisor, so parallel-research statuses survive `restore_tasks_json()` reliably.

### J. zsh Array Arg-Splitting for mdsel + Max-Thinking Breakdowns — `185cb24`

Two smaller fixes bundled into the same commit:

1. **`extract_prd_sections()` selector splitting (relates to item A):** Selectors were built as a space-separated string and passed unquoted (`mdsel $selectors "$prd_file"`). zsh, unlike bash, does **not** word-split unquoted `$var`, so every selector arrived as a single argument and mdsel rejected it. Now parsed into a real zsh array and expanded with `${selectors[@]}`:
   ```bash
   local -a selectors=(${(f)"$(echo "$selectors_json" | jq -r '.[]' 2>/dev/null)"})
   mdsel "${selectors[@]}" "$prd_file" 2>/dev/null
   ```

2. **Max-thinking breakdowns:** Task breakdown (initial + the "demand write" retry) now runs with `--thinking xhigh`. Decomposition + research synthesis into Phase→Milestone→Task→Subtask needs the deepest reasoning, so the highest reasoning budget is pinned unconditionally.

### K. Parallel Research Flag (`-r`) Propagation to Bugfix Sub-Runs — fix

**Problem Solved:** `prd -r` silently did nothing whenever the run entered the bugfix phase. Users observed every bugfix item (e.g. `P1.M3.T2.S1`) researching synchronously inline — no `[PARALLEL]` prefetch lines, items arriving `Planned` instead of `Ready` — even though `-r` had been passed at the top level.

**Root Cause:** `PARALLEL_RESEARCH` is set by `-r`/`--parallel-research` as a **plain shell variable that is never `export`ed** (only assignments at the arg-parse block; no `export`). When bug-finding finds bugs, the pipeline recurses into a *child* process:
```bash
SKIP_BUG_FINDING=true \
PRD_FILE="$BUG_RESULTS_FILE" \
SCOPE="$BUGFIX_SCOPE" \
AGENT="$AGENT" \
PLAN_DIR="$CURRENT_BUGFIX_SESSION" \
"$0"
```
This forwards a curated env block but **omits `PARALLEL_RESEARCH` and `-r`**. Because the var was never exported, the child hits `PARALLEL_RESEARCH="${PARALLEL_RESEARCH:-false}"` and defaults to `false`. All actual item execution happens in that bugfix child (the top-level main loop sees the main PRD's items already Complete and hands off), so background prefetch was disabled for the entire phase where it mattered. The failure was invisible because the `[CONFIG] Parallel research:` line only printed when enabled (no `else`).

Contrast: the queued-delta re-exec uses `exec "$0" "$@"`, which *does* forward `-r` via `$@` — so only the bugfix recursion was broken.

**Solution:**
1. Forward the settings into the bugfix child explicitly (matches the existing env-var convention in that block), including the companion `RESEARCH_DEPTH` which had the identical non-exported flaw:
```bash
SKIP_BUG_FINDING=true \
PRD_FILE="$BUG_RESULTS_FILE" \
SCOPE="$BUGFIX_SCOPE" \
AGENT="$AGENT" \
PLAN_DIR="$CURRENT_BUGFIX_SESSION" \
PARALLEL_RESEARCH="$PARALLEL_RESEARCH" \
RESEARCH_DEPTH="$RESEARCH_DEPTH" \
"$0"
```
2. Make the disablement visible so this class of regression can't fail silently again — the `[CONFIG]` line now prints `disabled` in the `else` branch.

**Why not `export`:** The explicit per-call forwarding is preferred here because it mirrors how `SCOPE`/`AGENT`/`PLAN_DIR` are already threaded through this exact recursion boundary, keeping the contract ("the bugfix child inherits a deliberate, curated environment") locally readable rather than relying on process-wide export state.

---

## Changes Since Commit e286b56 (Resilience & Guard-Rails Pass)

**Base commit:** `e286b56` — "fix(prd): forward parallel research and depth settings into bugfix sub-runs" (end of the prior section, item K)
**Latest commit:** `8098249` — "fix(prd): prevent orphaned plan dirs from interrupted runs" (+ uncommitted `--no-session` changes on `run-prd.sh`)
**Date range:** 2026-07-03 through 2026-07-13 (12 commits)
**Files changed:**
- `prd_pipeline/run-prd.sh` (+330 lines, −51 lines vs `e286b56`, working tree — includes uncommitted)
- `fix_diagrams/` (rewrite: 32 files, +912/−731 in `30d224f`)

**Theme:** The pipeline is now survivable across the two failure classes that caused the most lost work this period — *interrupted runs* (Ctrl+C / SIGKILL mid-item, mid-breakdown, mid-validation) and *misbehaving agents* (deleting `PRD.md`/`PRP.md`, batching thin PRPs, or stalling forever). Nearly every change here closes a path where a force-interrupt or an over-eager agent could leave the repo in a state that a blind resume would then orphan or corrupt.

---

### L. Critical-File Deletion Protection — `81a59ab`

**Problem Solved:** The autonomous bug finder, the validation fixer, and especially the cleanup agent would sometimes delete `PRD.md` and `**/PRP.md`. Because `smart_commit` runs `git add -A`, any such deletion was staged and committed permanently — silently wiping the real PRD and every PRP on every bug-fix run.

**Solution:** Two layers — a *prompt* layer telling agents never to delete these files, and a *mechanical* layer (`restore_critical_files()`) that undoes the deletion if it happens anyway, mirroring `restore_tasks_json`.

**Mechanical guard:**
```bash
restore_critical_files() {
    [[ ! -d ".git" ]] && return 0
    local deleted
    deleted=$(git diff --cached --name-only --diff-filter=D 2>/dev/null \
        | grep -E '(^|/)PRD\.md$|(^|/)PRP\.md$')
    [[ -z "$deleted" ]] && return 0
    local f
    for f in "${(@f)deleted}"; do
        [[ -z "$f" ]] && continue
        if git cat-file -e "HEAD:$f" 2>/dev/null; then
            git checkout HEAD -- "$f" 2>/dev/null \
                && print -P "%F{red}[PROTECT]%f Restored deleted critical file from HEAD: $f"
        else
            git reset -q HEAD -- "$f" 2>/dev/null   # created+deleted same run: just unstage
            print -P "%F{yellow}[PROTECT]%f Cannot restore (not in HEAD); unstaged deletion of: $f"
        fi
    done
}
```
Called from `smart_commit` right after `git add -A` (and before the `tasks.json` restore). `PRD.md` / `PRP.md` are now guaranteed to survive every commit.

**Prompt layer:** Every deletion-capable agent prompt (cleanup, bug hunter, bug-fix breakdown, post-validation fix) gained an explicit **"NEVER run `rm`, `git rm`, `git clean`, or `mv` against `PRD.md`, any `PRP.md`, or anything under `plan/`"** clause, and the cleanup prompt's "Delete" step was reworded to forbid treating pipeline-state files as "temporary."

---

### M. `--accept-prd-changes` Flag + Validation/Retry Hardening — `81b5fa6`

The largest commit of the period; several distinct concerns:

**M1. `--accept-prd-changes` flag.** Accept PRD edits as the new baseline *without* generating a delta session. Use when `PRD.md` was edited (docs/refinements reflecting already-finished work) but the work is complete and validated, so the next run should stay idempotent instead of spawning a delta. Across all three `PRD_CHANGED_*` session states it cancels any queued `.pending_delta_hash`, refreshes `prd_snapshot.md` to the current PRD, and exits/resumes idempotently.

**M2. Dedicated `VALIDATION_AGENT` + `VALIDATION_TIMEOUT`.** Validation now runs on a new `VALIDATION_AGENT` (default `pizr`, matching breakdown/bug-finder reasoning) instead of the generic `$AGENT`, and gets its own watchdog budget `VALIDATION_TIMEOUT` (default `7200` s / 2 h — validation legitimately runs full test suites), overriding `PI_AGENT_TIMEOUT` for the validation call only. Validation failure now **aborts the run** before cleanup/commit/bug-hunt rather than proceeding on a half-validated build:
```bash
PI_AGENT_TIMEOUT=$VALIDATION_TIMEOUT run_with_retry_stdin "$VALIDATION_PROMPT" $VALIDATION_AGENT
validation_rc=$?
if [[ $validation_rc -ne 0 ]]; then
    print -P "%F{red}[ERROR]%f Validation did not finish (exit $validation_rc). Aborting before cleanup/commit/bug-hunt."
    exit $validation_rc
fi
```

**M3. Watchdog timeouts are no longer retried.** `run_with_retry` and `run_with_retry_stdin` now treat exit `124` (watchdog kill) as a hard failure — a hung process will just re-hang, so churning retries forever is wrong:
```bash
if [[ $exit_status -eq 124 ]]; then
    print -P "%F{red}[TIMEOUT]%f Command killed by watchdog (exit 124). Not retrying."
    return 124
fi
```

**M4. Resilient stdin temp file.** `run_with_retry_stdin` now re-writes the prompt to its temp file on *every* retry attempt (not once). If the agent or the system cleans `/tmp` mid-run, the old code failed forever with "no such file" on every later retry; rewriting is cheap and makes retries resilient regardless of why the file vanished.

**M5. Calmer parallel-research wait.** `wait_for_background_research` timeout raised `600 s → 1800 s` (30 min), and the heartbeat is now silent for the first 1000 s then surfaces every 100 s — normal research can take a while, but a genuinely stuck supervisor is still visible without spamming early on.

---

### N. Single-PRP Default with Strict Batching Gates — `de3cb15`

**Problem Solved:** PRP (research) agents would batch several PRPs into one session "to be helpful," producing thin, under-researched PRPs that failed at implementation — the exact opposite of the goal.

**Solution:** Made "write exactly ONE PRP — the one you were asked for" the explicit default in the PRP system prompt, the `PRP_CREATE_PROMPT`, and each per-item scope line, with a **MULTI-PRP BATCHING POLICY** that only permits batching as an optimization for tightly-coupled items at a *higher* bar (not a lower one). The hard gate before any second PRP requires: full task-tree + full-PRD awareness, per-item 3–5 subagent research calls (the budget is *per PRP*, so an N-PRP batch needs ~N× the research), a per-item "No Prior Knowledge" pass, and an explicit batch declaration. **"When in doubt, write one."**

**Also:** `prd status` is now aliased to `prd task` for git muscle memory (`git status` / `prd status`).

---

### O. Mid-Session Integration: Preserve the Original Snapshot — `241c310`

**Problem Solved:** When the user chose "Integrate changes into current session" (option 1), the code immediately overwrote `prd_snapshot.md` with the new PRD. That erased the very diff the integration agent needs to see (it diffs *original snapshot* vs *current PRD*) *and* silently swallowed the change if integration failed to apply anything. (PRD-change detection hashes `prd_snapshot.md` as its baseline.)

**Solution:** Stop refreshing the snapshot at integration time; refresh it only *after* integration succeeds:
```bash
# Now that the task hierarchy reflects the new PRD, refresh prd_snapshot.md ...
# This is done AFTER integration so the agent had the original snapshot to diff against.
cp "$PRD_FILE" "$SESSION_DIR/prd_snapshot.md"
```

**Bundled in the same commit:**
- **Prompt-escaping fix:** several heredocs (`DELTA_PRD_GENERATION_PROMPT`, `TASK_UPDATE_PROMPT`, `VALIDATION_PROMPT`, bug-hunter prompt) used `\$(cat ...)` — a literal backslash-dollar that, in an unquoted heredoc, emits the *string* `$(cat "PRD.md")` rather than the file contents. Corrected to `$(cat ...)` so the prompts actually contain the PRD/tasks text.
- **Migrated four more call sites to `run_with_retry_stdin`** (delta-PRD generation, task update, validation, validation fix) — consistent with the argv-size bypass from item H, feeding these large prompts through stdin instead of `-p`.

---

### P. No-Issues Marker for Clean Bug Hunts — `2dc6ec1` (+commit in `81b5fa6`)

**Problem Solved:** After a bug hunt found nothing, there was no record of it — so the user couldn't tell whether bug hunting had already run clean on a task set or just hadn't run yet.

**Solution:** When the bug finder reports no bugs, write `$BUGFIX_DIR/NO_ISSUES_FOUND.md` recording the timestamp, the session tested, a `tasks.json` hash (so a stale marker is easy to spot once the task set changes), and the bug-finder agent. The marker is cleared (`rm -f`) if a later hunt *does* find bugs, so the bugfix directory always reflects the latest result. `81b5fa6` adds the matching `git commit` so the clean result is persisted just like a real bug report is.

---

### Q. Auto-Resume Interrupted Bugfix Task Breakdowns — `481a418`

**Problem Solved:** If a recursive bug-fix run was killed *between* committing the bug report and finishing PHASE 0 (task breakdown), the bugfix session was left with a `TEST_RESULTS.md` but no `tasks.json`. Plain `prd` / `prd --bug-hunt` would then not resume it — the breakdown was stranded.

**Solution:** A new `bugfix_needs_breakdown()` predicate (report present, `tasks.json` missing/empty/corrupt) plus an auto-detect block that runs *before* the session-state prompts: if the latest `bugfix/NNN_hash/` session needs its breakdown, re-enter the pipeline on the exact same path the bug-hunt stage uses when it first finds bugs (`PLAN_DIR` = bugfix session, `PRD_FILE` = bug report, `SKIP_BUG_FINDING=true`), so the child's PHASE 0 regenerates the missing `tasks.json`. `SKIP_BUG_FINDING=true` in the child skips this check, so there's no re-entry loop. Skipped in `--validate` / `--skip-bug-finding`.

---

### R. Prevent Orphaned `plan/` Dirs from Interrupted Runs — `8098249`

**Problem Solved:** A force-interrupted prior run could leave an item "Complete" in the *working tree* but never committed — stranding its `plan/` work directory and the status change as untracked/unstaged. A blind skip in `execute_item` ("already Completed → return") would then orphan that work *forever*: the cleanup agent is forbidden from touching `plan/`, and no later `smart_commit` would reach this item.

**Solution:** Two-part.
1. **Skip-recovery:** a new `_item_status_in_head()` checks the item's status in *HEAD's* `tasks.json` (not the working tree). On the Completed-skip path, if HEAD doesn't also record the item as Complete, run `smart_commit` now to persist the stranded `plan/` dir + status:
```bash
if [[ "$current_status" == "Completed" || "$current_status" == "Complete" ]]; then
    if ! _item_status_in_head "$id" Complete Completed; then
        print -P "%F{yellow}[RECOVERY]%f $id is Complete on disk but not in HEAD (interrupted prior run). Persisting stranded plan/ work..."
        smart_commit
    fi
    ...
```
2. **Pre-cleanup commit:** `execute_item` now runs `smart_commit` *before* the cleanup agent. Cleanup is a long, interruptible LLM call; committing the item's substance (source changes + `plan/` dir + Complete status) first guarantees a force-interrupt here can no longer leave the item "Complete on disk but uncommitted" — the state that causes the orphan. The cleanup agent's doc reorg is still committed by the later `smart_commit`.

---

### S. Agent Default Tuning — `pizr` / `piznt` / dedicated `VALIDATION_AGENT` — `4b6acad`, `90267ab`, `81b5fa6`

Three default-agent changes so each pipeline phase runs on a model suited to its job:

| Role | Default before | Default now | Commit |
|------|----------------|-------------|--------|
| `IMPL_AGENT` (PRP-execute + post-validation fix) | `pizt` (glm-5-turbo) | `piznt` | `4b6acad` |
| `BREAKDOWN_AGENT` (task decomposition) | `piz` (glm-5.2) | `pizr` (pi + `--thinking xhigh`) | `90267ab` |
| `BUG_FINDER_AGENT` | `piz` | `pizr` | `90267ab` |
| `VALIDATION_AGENT` (new role) | *(used generic `$AGENT`)* | `pizr` | `81b5fa6` |

Planning, breakdown, bug-finding, and validation — the steps that need deep reasoning — now all default to `pizr`; code-writing defaults to the faster `piznt`. (See M2 for the validation split.)

---

### T. Stateless Agent Invocations via `--no-session` (uncommitted, working tree)

Every agent call that is *stateless by nature* — cleanup, mid-session task update, validation, the post-validation fix, bug-finder, validation-artifact deletion, and the per-item PRP-execute (`tee`'d to the output log) — now passes `--no-session`. These calls don't benefit from session resume (they're single-shot or operate on freshly-built prompts), and leaving sessions enabled was creating/resuming sessions that served no purpose. Classifier calls already used `--no-session`; this extends the same discipline to the rest of the stateless call sites.

---

### U. Small Fixes

- **`commit-pi` → `stagecoach` (`0054127`):** the smart-commit commit tool was renamed; `smart_commit` now calls `stagecoach`. (Comments updated to drop the old name.)
- **Menu input sanitization (`55303cc`):** the PRD-change menu `read -r "choice?..."` now trims stray whitespace/CR, so basic mistypes like `"2 "` or a trailing carriage-return from a paste are still accepted:
```bash
choice="${choice//$'\r'/}"
choice="${choice#"${choice%%[![:space:]]*}"}"
choice="${choice%"${choice##*[![:space:]]}"}"
```

---

## Component: `fix_diagrams/` — Fixer Rewrite

### V. Drift-Tolerant, Display-Width-Aware Diagram Fixer — `30d224f`

**Scope note:** This is a separate subproject (`fix_diagrams/`, a Claude Code `PostToolUse` hook), not part of `run-prd.sh`. Documented here because it landed in the same window.

**What changed:** A near-complete rewrite of the ASCII box-diagram alignment fixer (`fix_diagram.py`; +912/−731 across 32 files including regenerated golden tests), plus a new geometry linter `diagram_lint.py` and an expanded `run_tests.py`.

**New error model ("drift and width"):** the fixer now models how LLMs actually break diagrams — the *top border and left corner column are written first and are almost always correct*, while errors accumulate rightward (wrong padding before `│`) and downward (bottom borders with the wrong dash count, drifted corners, or missing entirely). The pipeline:
1. **Trace** — each top border is traced downward, matching left/right edge tokens per row within a *drift-tolerance window*, anchored on the left neighbour's *actual* token positions so cumulative drift doesn't break matching; already-matched tokens are "claimed" so neighbours can't steal them.
2. **Layout** — target inner width = max(top-border width, widest rstripped content line), measured in **display cells** (`dwidth`: ANSI escapes are zero-width, CJK is double-width), so colored/CJK/emoji content aligns correctly in a terminal.
3. **Render** — each box row is rebuilt at its target geometry; gaps between side-by-side boxes are *elastic* (dash runs like `────▶` stretch/shrink via `_fit_gap`); a missing bottom border is synthesised when a connector row (`│▼▲`) follows.

**Conservative bail-outs ("do no harm"):** junction chars (`┬┼├┤`) in borders, double-line/rounded borders, tab-containing rows, malformed bottom borders, height > 40 rows, and connector pipes mistaken for edges all leave the text untouched.

**Testing:** `run_tests.py` runs four independent oracles — golden (50 pairs), property (idempotence, expected-files-are-fixed-points, no visible character created or destroyed, output never has more geometry violations than input), seeded corruption-fuzzing (builds clean diagrams, applies LLM-style corruptions, requires byte-exact recovery; `--fuzz N`), and targeted unit tests. `diagram_lint.py` is both a test oracle and a standalone audit tool.

---

## Commit History (this section)

| Hash | Date | Message |
|------|------|---------|
| `30d224f` | 2026-07-03 | refactor(diagrams): rewrite fixer with drift and width |
| `4b6acad` | 2026-07-03 | fix(prd): update default implementation agent to piznt |
| `90267ab` | 2026-07-05 | fix(prd): switch default breakdown and bug hunt agent |
| `241c310` | 2026-07-05 | fix(prd): preserve original snapshot during mid-session integration |
| `81a59ab` | 2026-07-07 | fix(prd): prevent agents from deleting PRD and PRP files |
| `55303cc` | 2026-07-07 | fix(prd): sanitize menu input of stray whitespace |
| `de3cb15` | 2026-07-07 | fix(prd): enforce single-PRP default with strict batching gates |
| `2dc6ec1` | 2026-07-07 | fix(prd): persist no-issues marker after clean bug hunt |
| `0054127` | 2026-07-08 | fix(prd): replace commit-pi with stagecoach |
| `81b5fa6` | 2026-07-10 | fix(prd): add accept-prd-changes flag and harden retry loops |
| `481a418` | 2026-07-11 | fix(prd): auto-resume interrupted bugfix task breakdowns |
| `8098249` | 2026-07-13 | fix(prd): prevent orphaned plan dirs from interrupted runs |

Plus uncommitted working-tree changes on `prd_pipeline/run-prd.sh` (item T).

---

## Changes Since Commit 8098249 (Distributed PRDs, Dependency Discipline & Commit Resilience)

**Base commit:** `8098249` — "fix(prd): prevent orphaned plan dirs from interrupted runs" (end of the prior section, item R)
**Latest commit:** `6b52c0a` — "fix(prd): ignore pending deps in failure streak"
**Date range:** 2026-07-13 through 2026-07-20 (10 commits)
**Files changed:**
- `prd_pipeline/run-prd.sh` (+644 lines, −57 lines vs `8098249`)
- `prd_pipeline/fixes/tasks-json-race/` (new subproject: README + repro script + 2 patches, +312 lines)
- `prd_pipeline/CHANGELOG_37e81cc5.md` (this file; +210 lines in `ab098a9`, the "Resilience & Guard-Rails Pass" section itself)

**Theme:** Three threads converge here.

1. **Distributed PRDs** — a PRD may now be authored across many files via `@path` include directives (first sole-line, then generalized inline), resolved into one canonical merged document that every downstream agent, selector, and hash sees. This is what makes a split PRD behave exactly like a monolithic one.
2. **Dependency discipline & failure halts** — the execution loop no longer implements a *consumer* before its *producers*, and it HALTS the whole run when a streak of items can't make progress (a systematic blocker), while removing the blind end-of-run "mark Complete" that used to permanently orphan incomplete work.
3. **Resilience** — stagecoach commit-gen is retried with a `git commit` fallback, `--validate`/`--bug-hunt` re-runs reuse a session instead of forking an empty delta, and the previously-uncommitted `--no-session` stateless-invocation discipline (item T) landed as a real commit.

Plus a new **`--adopt-prd`** mode for integrating the pipeline into an already-implemented legacy codebase, and a fully root-caused **`tasks.json` lost-update race** fix shipped as reviewable patches.

---

### W. Stateless `--no-session` Invocations Land as a Commit — `7f862c0`

**Supersedes item T.** The "uncommitted working-tree" `--no-session` discipline described in item T was committed here. Every agent call that is *stateless by nature* — the per-item PRP execute (`tee`'d to the output log), both cleanup sites (post-execute and post-breakdown), the mid-session task update, final validation, the post-validation fix, validation-artifact deletion, and the bug finder — now passes `--no-session`. These calls don't benefit from session resume (they're single-shot or operate on freshly-built prompts), and leaving sessions enabled was creating/resuming sessions that served no purpose.

> **Note (later refined in item AA):** this commit made the *implementation* call `--no-session` too, but `ca97e80` deliberately restored a resumable session (`--session-id prd-impl-<dirname>`) for implementation specifically — it is the one call that must survive a hang/crash. The other stateless call sites remain `--no-session`.

---

### X. Distributed PRDs: Recursive + Inline `@path` Include Resolution — `033a8c9`, `73a15e5`

**Problem Solved:** A PRD of any real size wants to be split across multiple files (architecture, API, data model, companion docs). Before this, the pipeline hashed/snapshotted/showed agents only the single entry `PRD.md` file, so a split PRD was either partially invisible to agents or produced hash churn that broke delta detection.

**Solution:** An `@path/to/file.md` token is an *include directive* — it is replaced inline by the referenced file's contents. The resolver is **idempotent** (re-resolving already-resolved content yields identical bytes), which is the property that guarantees hash/snapshot consistency.

**Two-stage rollout:**

- **`033a8c9` — sole-line includes (recursive).** A line of the form `@path/to/file.md` (optional leading whitespace, nothing else on the line) is expanded. Includes are resolved **project-root-relative** (relative to the entry PRD's directory, regardless of which file contains the directive) and expanded **recursively with cycle detection** (`PRD_INCLUDE_MAX_DEPTH`, default 10). A token only expands if the path resolves to an existing file; otherwise it passes through verbatim, so prose `@mentions` stay literal.
- **`73a15e5` — inline includes.** Generalized so the `@path` token is honored **anywhere on a line**, not just alone — because companion docs are most naturally listed inside a markdown table cell (`| @ARCHITECTURE.md | Repository layout, module map |`) or in prose. A token expands when *both* hold: (1) **boundary** — the `@` is at the start of the line or preceded by a non-path character (protects `foo@bar.com` / mid-word `@`), and (2) **existence** — the path resolves to a file. Existence is the real discriminator; prose `@mentions` simply don't resolve.

**Plumbing:**
```bash
resolve_prd_content() { … }        # recursive, cycle-detected, project-root-relative
write_resolved_prd() { … }         # materialize fully-resolved PRD to <dest>
expand_inline_includes() { … }      # per-line inline token expansion
hash_prd_content() {
    resolve_prd_content "$1" | sha256sum | cut -c1-12   # hash the RESOLVED doc
}
```

Every `cp "$PRD_FILE" .../prd_snapshot.md` and `cat "$PRD_FILE"` site (snapshot writes, delta PRD inputs, integration/validation/bug-finder prompts, mdsel index generation) was routed through the resolver, so a split PRD is flattened into one canonical document everywhere downstream. mdsel now runs over a temp materialized copy so selectors reference the merged document. Agent prompts were updated to tell the model the text it receives is *already* the complete merged document (don't chase includes yourself).

**New env vars:** `PRD_INCLUDE_MAX_DEPTH` (default 10), `PRD_INCLUDE_MARKERS` (if non-empty, emit `<!-- @include: path -->` / `<!-- @end-include -->` markers).

**Impact:** A split PRD now behaves identically to a monolithic one for hashing, delta detection, mdsel selectors, and every agent prompt. Stale includes (a `.md` token that fails to resolve) earn a stderr warning; ordinary `@mentions` stay silent.

---

### Y. `--adopt-prd` Mode (Legacy Codebase Adoption) — `73a15e5`

**Problem Solved:** Integrating `run-prd.sh` into an existing, *already-implemented* project after writing the PRD used to waste a full breakdown + implementation pass planning and "building" code that already exists.

**Solution:** `--adopt-prd` (`ADOPT_PRD`) declares the PRD the source of truth for an already-shipped codebase. On a **fresh project** (no `plan/` sessions yet) it:
1. Creates a baseline session and stamps it with a `.adopted` marker.
2. Seeds a single completed `tasks.json` (one Phase → Milestone → Task → "Adopt existing codebase" Subtask, all `Complete`) — **no breakdown, no tokens** — so `is_session_complete` is true and this session becomes the idempotent baseline future deltas diff against.
3. Sets `SKIP_EXECUTION_LOOP=true`; implementation is skipped, but **validation + bug hunt still run** against the real codebase + PRD.

The next `PRD.md` edit produces a normal delta session, so deltas drive ongoing development from the adopted baseline.

**Guard rails:**
- `--adopt-prd` **requires** the PRD to exist (`PRD_FILE`); a missing PRD otherwise skips session resolution and would scribble near the filesystem root (`/architecture`, `/prd_snapshot.md`). It now exits loudly instead.
- It **only applies to fresh projects**; if sessions already exist the flag is a no-op misuse (warn + proceed with normal resolution).
- A new hard guard rejects an empty `SESSION_DIR` before breakdown/validation so collapsed root paths can never be written.
- `create_session()` now `mkdir -p "$PLAN_DIR"` first so the session path is always nested under it.

---

### Z. `--validate` / `--bug-hunt` Re-runs Reuse the Completed Session — `fddc68c`

**Problem Solved:** Re-running with `--validate` or `--bug-hunt` against an already-completed session whose PRD had a pending change would **fork an empty delta session** (because PRD-change detection fires before the flags are honored). That empty delta has no `tasks.json`, which made the validate-only / bug-hunt-only gates bail with *"Cannot validate without tasks"*.

**Solution:** When `ONLY_VALIDATE` or `ONLY_BUG_HUNT` is set, the PRD-change branch now **reuses the latest completed session** instead of creating a delta. The PRD change is intentionally left pending (not actioned) so the *next normal* run (no `--validate`) still processes it into a proper delta:
```bash
if [[ "$ONLY_VALIDATE" == "true" || "$ONLY_BUG_HUNT" == "true" ]]; then
    print -P "…reusing completed session $(basename "$CURRENT_SESSION_DIR")…"
    print -P "…PRD change noted but not actioned. Run without --validate to create the delta session…"
    SKIP_EXECUTION_LOOP=true
else
    # … create the delta session as before …
fi
```

---

### AA. Dependency-Order Enforcement, Failure-Halt Streak, & End-of-Run Completion Fix — `ca97e80`

The largest change in this window. Four related disciplines, one commit.

#### 1. Dependency gate (never build a consumer before its producers)

**Problem Solved:** Without ordering enforcement the loop would happily implement a *consumer* (docs, UI, a CLI flag) on top of *producers* that were skipped or not-yet-done — e.g. a tray calling `host_capable()` that was never defined, or documentation for CLI flags that don't exist yet.

**Solution:** `check_dependencies_satisfied <id>` returns false if any declared dependency is not yet `Complete`. `execute_item` calls it up front and signals "blocked" via **return code 3**, which the streak tracker consumes. Blocked items are left as `Planned` and retried once their producers land.

#### 2. Failure-halt streak (`ISSUE_STREAK`)

**Problem Solved:** Several items in a row that the loop *cannot* implement (failure / issue-retry / dep-blocked) almost always signals a **systematic blocker** — a broken build, a missing dependency, an unpushed git tag, contradictory requirements — that will fail every downstream item too. Silently walking past it (and building docs on top of the hole) was a critical failure.

**Solution:** `handle_item_result <rc> <id>` tracks the consecutive non-implementation streak (`ISSUE_STREAK_MAX`, default **3**); `run_item_and_check` wraps `execute_item` so all four scope loops share the logic:

| `execute_item` rc | meaning | streak effect |
|---|---|---|
| `0` | success / already-complete skip | **reset** |
| `1` | failure (marked `Failed`) | increment |
| `2` | issue-retry (reset to `Planned`) | increment |
| `3` | dependency-blocked | increment (refined in item AD) |
| `130` | interrupted | leave streak; shutdown owns exit |

At the max, the run **HALTs**: it stops background research, persists current state with `smart_commit`, and exits 1 so the root cause can be fixed. Blocked/issued items stay `Planned` and resume from where they stopped.

#### 3. Implementation runs under a (resumable) session; watchdog timeouts are not retried

**Refines item W.** The single implementation call — `IMPL_AGENT … Execute the PRP …` — switched from `--no-session` back to **`--session-id prd-impl-<dirname>`**. Rationale: implementation is the longest-running, most-subprocess-heavy call (test runners, headless editors) and the one most worth keeping resumable; `pi --resume prd-impl-<dirname>` picks up exactly where a hang/crash stopped. (All other stateless call sites from item W stay `--no-session`.)

A **watchdog timeout (exit 124)** is now treated distinctly from a normal agent failure: 124 means the agent hung — almost always on a spawned subprocess (headless editor / test runner) the watchdog can't reap, so that orphan likely still runs and must be killed by hand (`pkill -f nvim`, etc.). Retrying immediately would just re-hang on the same subprocess, so the item is marked `Failed` (not auto-retried) and returns `1` so the streak counter can halt the run if several items time out in a row. The session stays resumable for manual recovery.

#### 4. Removed blind end-of-run "mark final task Complete"

**Problem Solved:** The old tail block ran `tsk next` (which returns the *first* actionable item, not the last) and blindly marked it `Complete` — without verifying it was implemented. When the execution loop was interrupted, incomplete, or had skipped items, this marked **unimplemented work as done** and permanently orphaned it (future runs skip `Complete` items). The block is deleted; a comment now states completion is the *sole* responsibility of `execute_item`, which only marks `Complete` after verifying real source/PRP changes.

---

### AB. Stagecoach Commit-Gen Retry + `git commit` Fallback — `28c2d5d`

**Problem Solved:** `stagecoach` emits **exit 124 on its OWN generation timeout** (default 120s) — which is the *opposite* situation from the agent-subprocess hang in item AA. For a one-shot commit-message call, a 124 is **transient LLM-API slowness**, not a stuck subprocess, so it *should* be retried. But `smart_commit` routed stagecoach through `run_with_retry`, whose exit-124 special-case is correct for implementation/PRP agents (don't retry a hung subprocess) but **wrong** for stagecoach (do retry transient API slowness). The index is untouched on a stagecoach timeout and its lock is released on the rescue exit, so retrying is safe.

**Solution:** A deliberately separate primitive, `run_commit_with_retry`, with bounded retries and exponential backoff, and a last-resort fallback so a completed item's changes are never stranded uncommitted:
```bash
run_commit_with_retry() {
    local n=1 delay=${COMMIT_RETRY_DELAY:-10} rc
    while true; do
        [[ "$SHUTDOWN_REQUESTED" == "true" ]] && return 130
        stagecoach "$@"; rc=$?
        [[ $rc -eq 0 ]] && return 0
        (( n >= ${COMMIT_RETRY_MAX:-5} )) && break
        sleep "$delay"; delay=$(( delay * 2 )); (( delay > 120 )) && delay=120; ((n++))
    done
    # Fallback: preserve staged work with a clearly-labeled commit (reword later)
    git diff --staged --quiet && return $rc
    git commit -m "chore: stagecoach commit-gen failed (exit $rc); fallback commit" && return 0
    return $rc
}
```
`smart_commit` now calls `run_commit_with_retry` instead of `run_with_retry stagecoach`. **New env vars:** `COMMIT_RETRY_MAX` (default 5), `COMMIT_RETRY_DELAY` (first backoff, default 10s, doubling, capped at 120s).

---

### AC. Delta Breakdown Now Scoped to the Delta PRD — `c6c5f59`

**Problem Solved:** `TASK_BREAKDOWN_PROMPT` is an unquoted heredoc that embeds `$PRD_CONTENT` at **definition time**. For a delta session, `PRD_CONTENT` is reassigned to the *delta* PRD **after** the prompt was already defined — so the reassignment was dead code and the breakdown agent decomposed the **full** PRD, ignoring the delta entirely.

**Solution:** Wrap the heredoc read in a function and **rebuild** it once the delta content is known:
```bash
build_task_breakdown_prompt() {
    read -r -d '' TASK_BREAKDOWN_PROMPT <<EOF
    … $PRD_INDEX … $PRD_CONTENT …
EOF
}
# after PRD_CONTENT=$(cat "$SESSION_DIR/delta_prd.md"):
build_task_breakdown_prompt   # re-expand so the delta actually reaches the agent
```

---

### AD. Pending Dependencies Don't Count Toward the Halt Streak — `6b52c0a`

**Refines item AA.** The original dependency-block (rc 3) unconditionally incremented the streak. But a dependency block is only a **systematic** blocker if one of its unsatisfied dependencies is **Failed or missing**. If every unsatisfied dep is merely **pending** (Planned/Researching/Ready/Implementing), the producer just hasn't landed yet — that's normal ordering, not a failure, and must not count toward the halt. (Otherwise a single Mode-B docs task that legitimately depends on later-phase work would halt the whole run.)

**Solution:** `dependency_block_is_recoverable <id>` returns true if all unsatisfied deps are pending. In `handle_item_result`, an rc 3 now **defers without penalizing the streak** when recoverable, so the loop can advance to the producer; only a Failed/missing dependency increments the streak:
```bash
3)
    if dependency_block_is_recoverable "$id"; then
        print -P "[DEFER] $id deferred — producer(s) not yet Complete (streak held); runs once they land."
        return 0
    fi
    ISSUE_STREAK=$((ISSUE_STREAK + 1))
    ;;
```

---

### AE. `tasks.json` Lost-Update Race — Root-Caused & Shipped as Patches — `2b98341`

**Not yet applied to `run-prd.sh` / `tsk.ts` — shipped as reviewable patches under `prd_pipeline/fixes/tasks-json-race/`.**

**Symptom (observed in production):** A work item sat visibly at `Ready` for ~10 minutes while it was in fact being implemented, then jumped straight to `Complete`. It looked like the pipeline was hung on a single item with no agent working.

**Root cause:** `tsk` is an **unlocked read-modify-write** (`JSON.parse(readFileSync)` → mutate → `writeFileSync`, no `flock`, no lockfile, no atomic temp+rename). Two callers write the **same** `tasks.json` concurrently in this pipeline: the **foreground executor** (`Implementing`/`Complete`) and the **background research supervisor** (`Researching`/`Ready` for depth-2-chained items). Their read-modify-write cycles can interleave; the losing interleave clobbers a status back (e.g. the supervisor reverts `N:Implementing` → `N:Ready` because it read the file before the executor's write landed). `restore_tasks_json` is vulnerable for the same reason.

**Proof:** `repro-lost-update.sh` widens tsk's sub-ms read→write window to make the interleave observable — **10/10 bare trials lost an update; 10/10 flock-wrapped trials were clean.**

**The fix (two patches, to be applied when no run is active):**
1. **`01-run-prd-flock-locking.patch`** (the real fix, no dependencies) — add `tsk_locked()` wrapping `( flock 9; tsk … ) 9>"${file}.lock"` and route **every** `tasks.json` read/write through it: `tsk_cmd()` and the 6 direct-write sites (supervisor, `restore_tasks_json`, `cleanup_orphan_researching`). fd 9 is scoped to the subshell so it's safe under recursion and the backgrounded supervisor. Requires `flock` (util-linux).
2. **`02-tsk-atomic-write.patch`** (hardening) — make `saveBacklog()` in `task-processing/src/tsk.ts` **atomic**: write `.${basename}.${pid}.tmp` then `fs.renameSync` onto the target. `rename` is atomic on the same filesystem, so concurrent readers never see a half-written file and a crash mid-write can't corrupt `tasks.json`. (Doesn't by itself prevent lost updates — process-level mutual exclusion is Patch 1's flock — but makes `tsk` crash-safe for any other callers.)

**Artifacts:** `prd_pipeline/fixes/tasks-json-race/{README.md,repro-lost-update.sh,01-run-prd-flock-locking.patch,02-tsk-atomic-write.patch}`. Apply per the README's instructions after all runs finish; rebuild `task-processing` (`npm run build`) for Patch 2.

---

### AF. Docs / Meta — `ab098a9`

`ab098a9` is the **docs commit that added this changelog's "Changes Since Commit e286b56 (Resilience & Guard-Rails Pass)" section itself** (items L–V, +210 lines). It changed no pipeline code. Documented here for completeness so the commit is accounted for; it is the prior section, not new behavior.

---

## Commit History (this section)

| Hash | Date | Message |
|------|------|--------|
| `7f862c0` | 2026-07-13 | fix(prd): disable session persistence across pipeline agent calls |
| `2b98341` | 2026-07-16 | fix(prd): serialize tasks.json writes to prevent race |
| `ab098a9` | 2026-07-16 | docs(prd): add resilience pass changelog |
| `033a8c9` | 2026-07-16 | feat(prd): add recursive @path include resolution |
| `fddc68c` | 2026-07-16 | fix(prd): preserve session on validate-only re-runs |
| `73a15e5` | 2026-07-18 | feat(prd): add adopt mode and inline imports |
| `ca97e80` | 2026-07-20 | fix(prd): enforce dependency order and failure halts |
| `28c2d5d` | 2026-07-20 | fix(prd): retry stagecoach generation and add fallback |
| `c6c5f59` | 2026-07-20 | fix(prd): scope delta breakdown to current prd |
| `6b52c0a` | 2026-07-20 | fix(prd): ignore pending deps in failure streak |

> **Note on item T:** the uncommitted working-tree `--no-session` changes described in the prior section's item T were committed here as `7f862c0` (this section, item W) and are therefore no longer pending.

---

## Changes Since Commit fc727a4 (Bug-Hunt False-Negative: Reports Lost to NO_ISSUES_FOUND)

**Base commit:** `fc727a4`
**Symptom (observed in production on two projects):** The bug finder produced a **full bug report in chat** but the pipeline emitted `NO_ISSUES_FOUND.md` anyway — so real bugs (3 High-severity in one project, 5 Minor in another) were silently dropped with zero durable record.

**Root cause:** The pipeline's *only* signal for "were bugs found?" is the **presence of the file** `$BUG_RESULTS_FILE` (`TEST_RESULTS.md`). The bug finder itself decides whether to create it, and the old output-gate instructions said:

> - If you find **Critical or Major** bugs: write the file.
> - If you find **NO Critical or Major** bugs: do **not** write the file.

That gate failed in two distinct ways, both made silent by a structural fragility: the agent's **self-classification is the sole determinant** of whether anything is persisted, and the pipeline **never captures or inspects the agent's actual output** — so any mis-gating is a total, invisible loss.

1. **Taxonomy mismatch (the High-severity case).** The agent categorized findings as **High / Medium / Low** instead of Critical / Major / Minor, then applied the gate literally. Since its own scale had no "Critical" or "Major" bucket, it concluded none qualified — **even though it had found High-severity bugs and written a complete markdown report in its chat output.** It never persisted the file → pipeline saw no file → emitted `NO_ISSUES_FOUND.md`.
2. **Minor-issue black hole (the Minor case).** The agent correctly found only **Minor** issues and correctly applied the gate ("no Critical/Major → don't write"). Working as literally designed — but the design silently discards everything below "Major," so 5 real issues vanished with no record.

**The fix (two layers):**

### AG. Bug-Finder Output Gate Rewritten (primary fix) — `run-prd.sh`

Replaced the severity-conditional gate in `BUG_FINDING_PROMPT` with one that is robust to both failure modes:

- **Write on ANY issue (Critical, Major, *or Minor*).** The file is the durable record; a later stage decides what to act on. Omit it *only* when genuinely nothing reportable was found. This closes the Minor black hole.
- **Pin the taxonomy.** Require exactly **Critical / Major / Minor**, with an explicit **High→Critical / Medium→Major / Low→Minor** mapping, and call out that a "## High severity" report has been dropped before. This closes the taxonomy mismatch.
- **Bias toward writing.** "When in doubt, WRITE IT" — a spurious report costs seconds of review; a dropped report ships regressions. Added a final self-check: "Did I describe any issue? Then the file MUST exist on disk."
- Added a prominent header noting the pipeline never reads chat output — only the file counts.

### AH. Transcript Capture + Inconsistency Detection (defense in depth) — `run-prd.sh`

Turns the silent failure into a loud, recoverable one so a future misbehaving agent can't repeat it:

- `run_with_retry_stdin` gained an opt-in `CAPTURE_STDOUT` (tee combined stdout+stderr to a file while still streaming live; agent exit status preserved via `pipestatus[1]`). Other call sites are unaffected.
- The bug hunt sets `CAPTURE_STDOUT=<bugfix-session>/bug-hunt-transcript.log`, so the agent's full report is always persisted during the run.
- After the run, the old "`! -f BUG_RESULTS_FILE` ⇒ clean" branch now **scans the transcript first** for structural bug-report signals (severity headings, `### Issue`, `**Severity**`, "Steps to Reproduce", "Suggested Fix", "Issues found", …), with the prompt template's own placeholder lines excluded. Threshold ≥2 so a clean run that merely says "no bugs found" (count 1) isn't a false positive.
  - **≥2 signals but no file** → **INCONSISTENT**: refuse to mark clean, print a red warning, write `INCONSISTENT_BUG_HUNT.md`, commit it with the transcript, and keep the session dir as evidence. The findings are NOT lost — recoverable from the transcript.
  - **<2 signals** → genuinely clean → existing `NO_ISSUES_FOUND.md` path (wording updated from "no Critical/Major" to "no issues (Critical, Major, or Minor)"); transcript removed and empty session reaped.
- A successful bug-report run clears both stale `NO_ISSUES_FOUND.md` and stale `INCONSISTENT_BUG_HUNT.md`.

**Validation:** signal-count tested against the two real reports — the dense High/Medium/Low report scores 9 (caught); a genuinely-clean transcript scores 0 (no false positive); missing/empty transcripts score 0 (graceful). `zsh -n` clean. The sparse Minor-only transcript scores 1 (below the backstop threshold) but is fully handled at the source by item AG (Minor now triggers file-writing), and would in any case be recoverable from the captured transcript.

**Why two layers:** item AG makes the agent write the file reliably (fixes both incidents at the source); item AH guarantees that if an agent *still* mis-gates, the report is neither lost nor silently marked clean.

---

## Changes Since Commit fc727a4 (Deterministic Verdicts, No-Gaps Execution & Deterministic Cleanup)

**Base commit:** `fc727a4` — "docs(prd): add distributed PRD and resilience log"
**New HEAD:** `6ee0256` — "fix(prd): pluralize cleanup log message correctly"
**Date range:** 2026-07-23 through 2026-08-08 (8 commits touching `run-prd.sh`)
**Files changed:** `prd_pipeline/run-prd.sh` (+953 lines, −240 lines vs `fc727a4`)

**Theme:** The end-of-run decision stages were rebuilt around **agent-authored structured JSON verdicts parsed deterministically by the orchestrator**, eliminating the lossy LLM "CLEAN/DIRTY" classifier and the file-presence / prose-regex heuristics that silently dropped real findings (the false-negatives documented in the prior `fc727a4` section, items AG/AH). The execution loop gained a **no-gaps invariant** — the cursor never advances past a non-terminal item, with a hard **HALT gate** if any item is `Failed` before validation runs — and per-item completion now requires the implementing agent's **explicit self-certification** ("files changed → Complete" is gone). Per-item cleanup became a **deterministic file reorg with no LLM call**. PRD `@path` include resolution became **markdown-aware** (fenced and inline code are never treated as directives) and gained **per-file hash manifests** so a "PRD changed" can name the exact component file. Two new flags — `--focus-only` and `--dry-reconcile` — expose the prefix-closure model. A rule enforced everywhere a verdict is read: **a missing/malformed/contradictory verdict is never treated as "clean"** — it is a failure that must be resolved, not a success.

---

### A. PRD `@path` Include Resolution Is Now Markdown-Aware (fenced + inline code) — `de264c1`

**Problem solved / Root cause:** An `@<path>` token shown *inside a fenced code block* (``` ``` ``` / `~~~`) or wrapped in *inline backticks* (`` `@ARCHITECTURE.md` ``) as **documentation** was being expanded as an include directive. If the literal text happened to resolve to a file, the documented example's content got spliced into the resolved PRD; if it did not, a spurious `[PRD INCLUDE] File not found:` warning fired. Both corrupt the resolved PRD and therefore the PRD hash/snapshot/delta machinery.

**Solution / Mechanism — two parts:*

1. **Fenced-block passthrough in `resolve_prd_content()`** (the per-file reader). A new `in_fence` toggle; the delimiter line and every line *inside* a fence are emitted verbatim and never passed to `expand_inline_includes`:

```bash
    local line in_fence=0 bt=$'\140'
    # Fenced code blocks (``` or ~~~, up to 3 leading spaces) pass through
    # verbatim, so @<path> tokens shown inside one as documentation are never
    # treated as include directives. The delimiter line toggles the state.
    local fence_re="^[[:space:]]{0,3}(${bt}${bt}${bt}+|~~~+)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $fence_re ]]; then
            print -r -- "$line"
            (( in_fence )) && in_fence=0 || in_fence=1
            continue
        fi
        if (( in_fence )); then
            print -r -- "$line"
            continue
        fi
        expand_inline_includes "$line" "$root" "$file_path" $(( depth + 1 ))
    done < "$file_path"
```
   (`bt=$'\140'` is a literal backtick; the regex matches ```` ```+ ```` or `~~~+` with up to 3 leading spaces — CommonMark fence rules.)

2. **Inline-code-span awareness in `expand_inline_includes()`** (the per-line tokenizer). An `@` sitting inside an inline code span is documentation, not a directive. It tracks a running backtick count across the already-consumed prefix and keeps the token literal when odd. **Also:** the match-offset locals were renamed `$mbegin`/`$mend` → `$cap_begin`/`$cap_end` and copied *immediately* after the `=~`, because zsh repopulates the reserved `$mbegin`/`$mend` arrays on **every** `=~` (including the downstream "looks like a doc" warning match), which clobbered the saved offsets before the line slice:

```bash
    local result="" tok include_path before_at pre pre_bt
    local cap_begin cap_end
    local bt=$'\140' bt_count=0
    while [[ "$line" =~ @([A-Za-z0-9._~/-]+) ]]; do
        tok="${match[1]}"
        cap_begin=$MBEGIN
        cap_end=$MEND
        pre="${line[1,cap_begin-1]}"
        result+="$pre"
        before_at=""
        (( cap_begin > 1 )) && before_at="${line[cap_begin-1,cap_begin-1]}"

        pre_bt="${pre//[^$bt]/}"
        bt_count=$(( bt_count + ${#pre_bt} ))
        if (( bt_count % 2 )); then
            # Inside an inline code span → keep literal, no warning.
            result+="@$tok"
        elif [[ -n "$before_at" ]] && [[ "$before_at" == [A-Za-z0-9._~/-] ]]; then
            result+="@$tok"   # mid-token '@' (email/user@host)
        else
            # ... existing project-root-relative file resolution ...
        fi
        line="${line[cap_end+1,-1]}"
    done
```
   The `bt_count` trick is correct because the shrinking `$line` buffer is always a suffix of the original line, so the per-iteration `pre` prefixes sum to the true running backtick count. Pure parameter expansion (no `=~`) is used inside the inline-code branch so `$match/$MBEGIN/$MEND` stay intact.

**Behavior:** fenced-code documentation lines pass through byte-for-byte; inline `` `@x` `` tokens pass through literally and silently; genuine bare `@path` tokens still expand.

**Impact:** the resolved PRD (and thus `prd_snapshot.md`, the PRD hash, and the delta/comparison machinery — items B, H) is stable against `@path` tokens that appear as documentation. The sister project must replicate both the fence toggle and the inline-backtick counter, plus the `cap_begin`/`cap_end` offset-rename.

---

### B. PRD Per-File Hash Manifests + Precise "What Changed" Reports — `572aa29`

**Problem solved / Root cause:** when a *distributed* PRD (`PRD.md` + `@include` companion docs) changed between sessions, the `[SESSION]` message only said "PRD has changed" — it could not name *which* companion doc actually changed, so the user had to diff the whole tree.

**Solution / Mechanism — a per-file sha256 manifest written next to every snapshot, plus a comparison helper.**

**New artifact:** file `prd_manifest.txt`, written into each session dir alongside `prd_snapshot.md`. Format — one line per component file (main PRD first, then every `@include` recursively resolved), order-preserving, deduped:
```
<sha256(12)> <path-relative-to-PWD>
```

**New/changed functions (full):**

`write_resolved_prd()` now also refreshes the manifest after writing the snapshot:
```bash
write_resolved_prd() {
    local dest=$1
    resolve_prd_content "$PRD_FILE" > "$dest"
    write_prd_manifest "${dest:h}"
}
```

`collect_prd_includes()` — fills the global `_PRD_INCLUDES_FOUND` array (absolute, order-preserving, deduped; main PRD first) by re-resolving with `PRD_INCLUDE_MARKERS=1` and scraping the `<!-- @include: PATH -->` markers:
```bash
collect_prd_includes() {
    typeset -ga _PRD_INCLUDES_FOUND
    _PRD_INCLUDES_FOUND=()
    [[ -f "$PRD_FILE" ]] || return 0
    local root="${PRD_FILE:A:h}"
    _PRD_INCLUDES_FOUND+=("${PRD_FILE:A}")
    local resolved tok inc_path
    resolved=$(PRD_INCLUDE_MARKERS=1 resolve_prd_content "$PRD_FILE" 2>/dev/null) || resolved=""
    while IFS= read -r tok; do
        [[ -z "$tok" ]] && continue
        inc_path="$tok"
        inc_path="${inc_path/#\~/$HOME}"
        [[ "$inc_path" != /* && "$inc_path" != \$* ]] && inc_path="$root/$inc_path"
        [[ -f "$inc_path" ]] && _PRD_INCLUDES_FOUND+=("${inc_path:A}")
    done < <(print -r -- "$resolved" | sed -nE 's/.*<!-- @include: ([^ ]+) -->.*/\1/p')
    local -A seen=(); local out=() p
    for p in "${_PRD_INCLUDES_FOUND[@]}"; do
        (( ${+seen[$p]} )) && continue
        seen[$p]=1; out+=("$p")
    done
    _PRD_INCLUDES_FOUND=("${out[@]}")
}
```

`write_prd_manifest <session_dir>` — writes the manifest (called automatically by `write_resolved_prd`):
```bash
write_prd_manifest() {
    local session_dir=$1
    [[ -n "$session_dir" && -d "$session_dir" ]] || return 0
    collect_prd_includes || return 0
    local manifest="$session_dir/prd_manifest.txt" p rel h
    : > "$manifest"
    for p in "${_PRD_INCLUDES_FOUND[@]}"; do
        [[ -f "$p" ]] || continue
        if [[ "$p" == "$PWD"/* ]]; then rel="${p#$PWD/}"; else rel="$p"; fi
        h=$(sha256sum "$p" 2>/dev/null | cut -c1-12)
        [[ -n "$h" ]] && print -r "$h $rel" >> "$manifest"
    done
}
```

`prd_change_report <session_dir>` — prints (to stdout, for inline inclusion) which components changed. **If a manifest exists:** load baseline hashes into an associative array `baseline[rel]=hash`, then for each current component print `%F{yellow}+%f new:`, `%F{red}~%f changed:`, and (for baseline entries no longer on disk) `%F{red}-%f removed:`; if nothing changed, print `%F{cyan}(no component file changed — diff is elsewhere in the resolved content)%f`. **Fallback (older sessions without a manifest):** list every component with `[main PRD]`/`[@include]` tags and flag those edited by mtime since the snapshot, noting "change may be a pull/checkout that reset mtimes" when none show.

**Wired into both PRD-changed branches** — immediately after each "PRD has changed" line (in both the `PRD_CHANGED_SESSION_INCOMPLETE` and `PRD_CHANGED_SESSION_COMPLETE` cases):
```bash
            print -P "%F{cyan}[SESSION]%f The resolved PRD = the main PRD + any @include companion docs. Changed component(s):"
            prd_change_report "$CURRENT_SESSION_DIR"
```

**Impact:** "PRD changed" now enumerates the exact component file(s) (`+ new` / `~ changed` / `- removed`). `prd_manifest.txt` is a new artifact written into every session dir at snapshot time. The sister project must add all three functions, the `write_prd_manifest` call in `write_resolved_prd`, the `prd_manifest.txt` format, and the two `prd_change_report` call sites.

---

### C. No-Gaps Invariant + `--focus-only` + `--dry-reconcile` — `c740592`

**Problem solved / Root cause:** previously the four scope loops **skipped** any phase/milestone/task/subtask whose number was below `START_*`:
```bash
    [[ $PHASE_NUM -lt $START_PHASE ]] && continue
```
So an interrupted/half-finished run restarted at a chosen start point and left every *earlier* non-terminal item behind — a permanent gap. (The start-skip was the old "jump ahead" behavior.)

**Solution:** the cursor now walks from the beginning and never advances past a non-terminal item; the old jump-ahead is opt-in.

**New environment variables / flags:**
- **`FOCUS_ONLY`** (env `FOCUS_ONLY`, default `false`); long-arg `--focus-only` → `FOCUS_ONLY=true`. Restores the legacy jump-ahead: skip prefix closure, jump straight to `START_*`, leave prior non-terminal items as-is.
- **`DRY_RECONCILE`** (env `DRY_RECONCILE`, default `false`); long-arg `--dry-reconcile` → `DRY_RECONCILE=true`. Audit-only: print every non-terminal item in document order (the exact set a normal run would close) and `exit 0` with no execution.

Both are added to the `getopts` long-arg `case` *and* to both `Usage:` strings (the per-arg one and the summary one).

**1. The four skip conditions are now gated on `FOCUS_ONLY`** (phase shown; milestone/task/subtask follow the identical `[[ "$FOCUS_ONLY" == "true" && … ]]` pattern):
```bash
    # --focus-only: skip phases before the start point (legacy jump-ahead). By
    # default the no-gaps invariant walks from the start so the prefix is closed.
    [[ "$FOCUS_ONLY" == "true" && $PHASE_NUM -lt $START_PHASE ]] && continue
```
So by default (no `--focus-only`) every phase/milestone/task/subtask is visited — the prefix gets closed first.

**2. In-place retry on `rc=2` (the no-gaps loop).** `run_item_and_check` changed from a single call into a bounded re-attempt loop. `execute_item` returns `rc=2` when an item reported an implementation *issue* and reset **that same item** to Planned (PRP deleted, feedback saved); the wrapper now re-attempts the **same** item in place rather than advancing, bounded by `execute_item`'s `ISSUE_RETRY_MAX` (which eventually yields `rc=0` Complete or `rc=1` Failed). `rc=3` (dependency-defer) still advances. Full new body:
```bash
run_item_and_check() {
    local rc
    while true; do
        execute_item "$@"
        rc=$?
        [[ "$SHUTDOWN_REQUESTED" == "true" ]] && break
        [[ $rc -eq 2 ]] || break
        print -P "%F{cyan}[RETRY]%f $1 hit an implementation issue — re-attempting in place (no advance) per the no-gaps invariant."
    done
    if ! handle_item_result "$rc" "$1"; then
        [[ -n "$RESEARCH_PID" ]] && kill -TERM "$RESEARCH_PID" 2>/dev/null
        print -P "%F{blue}[GIT]%f Persisting current state before halt..."
        smart_commit
        exit 1
    fi
    return 0
}
```

**3. Config logging** now reports prefix-closure state instead of just start positions:
```bash
if [[ "$FOCUS_ONLY" == "true" ]]; then
    print -P "%F{cyan}[CONFIG]%f Prefix closure: %F{yellow}SKIPPED (--focus-only)%f — jumping to start, prior non-terminal items left as-is"
    print -P "%F{cyan}[CONFIG]%f Starting positions: Phase=$START_PHASE"
    [[ $SCOPE != "phase" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Milestone=$START_MS"
    [[ $SCOPE == "task" || $SCOPE == "subtask" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Task=$START_TASK"
    [[ $SCOPE == "subtask" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Subtask=$START_SUBTASK"
else
    print -P "%F{cyan}[CONFIG]%f Prefix closure: %F{green}enabled%f (no-gaps invariant) — walking from P1 to close any non-terminal items before advancing"
fi
```

**4. Dry-reconcile block** — inserted after the "no phases" guard, before the outer loop. A recursive `jq` walk over `.backlog` prints `status<TAB>id<TAB>title` for every `Planned|Researching|Ready|Implementing` item (document order = closure order), formatted by awk, then `exit 0`:
```bash
if [[ "$DRY_RECONCILE" == "true" ]]; then
    print -P "%B%F{cyan}[RECONCILE]%f%b Non-terminal items (document order = closure order):"
    print -P ""
    jq -r '
      def walk:
        (.status // empty) as $st |
        (select($st == "Planned" or $st == "Researching" or $st == "Ready" or $st == "Implementing")
         | "\($st)\t\(.id // "")\t\(.title // "")"),
        ((.milestones // [])[] | walk),
        ((.tasks // [])[] | walk),
        ((.subtasks // [])[] | walk);
      (.backlog // [])[] | walk
    ' "$TASKS_FILE" 2>/dev/null | awk -F'\t' 'NF>=2 { printf "  %-13s %-20s %s\n", $1, $2, $3 }'
    print -P ""
    print -P "%F{cyan}[RECONCILE]%f (Implementing/Ready/Researching behind the cursor are the gaps; Planned is normal not-yet-started work.)"
    exit 0
fi
```

**Behavior:** a default run walks P1→… closing the prefix; `--focus-only` restores the old jump-ahead; `--dry-reconcile` lists the gaps and exits without executing.

**Impact:** a restarted run no longer strands earlier non-terminal items. The sister project must flip the four skip conditions to `FOCUS_ONLY`-gated, add the `run_item_and_check` retry loop, the two flags + usage strings, the config block, and the dry-reconcile `jq` block.

---

### D. Per-Item Completion Requires Agent Self-Certification; One-Shot Re-Prompt; Interrupt → Planned Rollback — `c740592`

**Problem solved / Root cause:** the old completion test in `execute_item`'s post-agent region was **"any git diff (modified OR new untracked, excluding `tasks.json`) ⇒ Complete"**. Code can be written without ever being tested, so this routinely marked untested / no-op work as Complete. (The `agent_reported_success` signal existed but was only consulted on the *no-changes* branch.)

**Before:**
```bash
    if [[ -z "$modified_files" && -z "$untracked_files" ]]; then
        if [[ "$agent_reported_success" == "true" ]]; then
            ... mark Complete ...
        else
            ... "No changes produced" → Failed ...
        fi
    else
        # Changes exist - mark as complete
        CURRENT_PROCESSING_STATUS="Complete"; restore_tasks_json "Complete"; ...
    fi
```

**After — explicit self-certification first; files-changed demoted to a sanity check with a one-shot re-prompt:**
```bash
    if [[ "$agent_reported_success" == "true" ]]; then
        print -P "%F{green}[OK]%f Agent confirmed success for $id"
        CURRENT_PROCESSING_STATUS="Complete"; restore_tasks_json "Complete"
        rm -f "$dirname/.issue_retry_count" "$dirname/issue_feedback.md"
    else
        local modified_files=$(git diff HEAD --name-only -- ':!**/tasks.json' 2>/dev/null)
        local untracked_files=$(git ls-files --others --exclude-standard -- ':!**/tasks.json' 2>/dev/null)
        if [[ -n "$modified_files" || -n "$untracked_files" ]]; then
            print -P "%F{yellow}[VERIFY]%f $id changed files but emitted no success signal — prompting agent to confirm (run tests, emit result)..."
            local verify_out=$(mktemp)
            setopt pipefail
            $IMPL_AGENT --session-id "prd-impl-$(basename "$dirname")" -p "For $(get_scope_name) $id you modified files but did not emit a final result. Run this item's tests now. If they pass, output exactly: {\"result\":\"success\"}. If something is genuinely wrong, output: {\"result\":\"issue\",\"message\":\"...\"} and explain." < /dev/null 2>&1 | tee "$verify_out" >/dev/null
            unsetopt pipefail
            if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
                rm -f "$verify_out"
                print -P "%F{yellow}[INTERRUPTED]%f Re-prompt interrupted for $id - rolling back to Planned"
                restore_tasks_json "Planned"; return 130
            fi
            if grep -q '"result"[[:space:]]*:[[:space:]]*"success"' "$verify_out" 2>/dev/null; then
                # confirmed → Complete
            else
                # "agent changed files but could not confirm success on re-prompt" → Failed (return 1)
            fi
        else
            print -P "%F{red}[FAILED]%f No changes and no success signal for $id - marking as Failed and continuing"
            CURRENT_PROCESSING_STATUS="Failed"; restore_tasks_json "Failed"; return 1
        fi
    fi
```

**Decision table (new):**

| agent emitted `{"result":"success"}` | → **Complete** |
| no success, files changed, re-prompt yields `success` | → **Complete** |
| no success, files changed, re-prompt yields no `success` | → **Failed** |
| no success, no files changed | → **Failed** ("no-op") |

The re-prompt uses `$IMPL_AGENT` (default `piznt`) with a resumable session id `prd-impl-<dirname>`, reading the success JSON out of `verify_out` via `grep`.

**Interrupt rollback (3 sites, all in this commit).** A Ctrl-C / `SHUTDOWN_REQUESTED` during an item used to `restore_tasks_json "Implementing"` (leave it mid-flight for resume). It now rolls **back to `Planned`** so the item is re-driven from a clean state on resume (PRP + tree work preserved, but not stranded half-implemented). Two sites inside the attempt loop + the re-prompt site — all changed `restore_tasks_json "Implementing"` → `restore_tasks_json "Planned"`:
```bash
            print -P "%F{yellow}[INTERRUPTED]%f Agent interrupted for $id - rolling back to Planned (PRP + tree work preserved for resume)"
            restore_tasks_json "Planned"
            rm -f "$agent_output_file"
            return 130
```
(the third site is the re-prompt path: `"Re-prompt interrupted for $id - rolling back to Planned"`).

**Impact:** an item can no longer reach Complete without a passing signal from the implementing agent; interruptions re-drive from `Planned`. The sister project must replace the gate logic, add the re-prompt, and flip all three interrupt sites to `Planned`.

---

### E. Deterministic Per-Item Cleanup Replaces the LLM Cleanup Agent (execute_item only) — `1a9fc08`, `6ee0256`

**Problem solved / Root cause:** after each item, the pipeline ran an **LLM cleanup agent** (`$AGENT --no-session -p "$CLEANUP_PROMPT"`) to reorganize stray docs — a long, interruptible, model-dependent call whose only job was pure file reorg, run *after* the substance commit (so it produced a second "cleanup" commit), and able to delete things (risk to the NEVER-DELETE guardrails).

**Solution / Mechanism — a deterministic, LLM-free function** that moves stray docs + ensures `.gitignore` entries, runs **before** `smart_commit` (one substance commit), and only when the item actually produced real changes:

```bash
cleanup_deterministic() {
    local id=$1 moved=0 added=0 f base e
    mkdir -p "$SESSION_DIR/docs"
    # Stray untracked .md in the project ROOT → docs/. Root-level only (no '/');
    # PRP.md lives under plan/, so the no-slash filter excludes it automatically.
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        [[ "$f" == */* ]] && continue
        base="${f:t}"
        case "$base" in
            README*|PRD.md|PRP.md|CONTRIBUTING.md|LICENSE*|CHANGELOG*) continue ;;
        esac
        mv -- "$f" "$SESSION_DIR/docs/" 2>/dev/null && { print -P "%F{cyan}[CLEANUP]%f moved stray doc $base → docs/"; ((moved++)) }
    done < <(git ls-files --others --exclude-standard '*.md' 2>/dev/null)
    # Standard build/deps/env + common-temp patterns, so scratch never reaches a
    # commit (smart_commit does `git add -A`). Append-if-missing; never deletes.
    touch .gitignore 2>/dev/null
    for e in dist/ build/ node_modules/ venv/ .env .DS_Store '*.log' '*.tmp' '*.bak' '*.swp'; do
        grep -qxF "$e" .gitignore 2>/dev/null || { echo "$e" >> .gitignore; ((added++)) }
    done
    local doc_word entry_word
    (( moved == 1 )) && doc_word="doc" || doc_word="docs"
    (( added == 1 )) && entry_word="entry" || entry_word="entries"
    print -P "%F{blue}[CLEANUP]%f $id: moved $moved $doc_word, added $added .gitignore $entry_word."
}
```

It **deletes nothing** — it only `mv`s root-level untracked `*.md` (excluding `README*|PRD.md|PRP.md|CONTRIBUTING.md|LICENSE*|CHANGELOG*`, and the no-`/` filter means `PRP.md` under `plan/` is never touched) into `$SESSION_DIR/docs/`, and append-if-missing the listed `.gitignore` entries.

**Call site (in `execute_item`)** — replaces the old substance-commit + LLM-cleanup + restore + second-commit sequence:
```bash
    local _real_changes=""
    _real_changes=$(git diff HEAD --name-only -- ':!**/tasks.json' 2>/dev/null)
    [[ -z "$_real_changes" ]] && _real_changes=$(git ls-files --others --exclude-standard -- ':!**/tasks.json' 2>/dev/null)
    [[ -n "$_real_changes" ]] && cleanup_deterministic "$id"

    smart_commit
```
So: (a) the per-item LLM `CLEANUP_PROMPT` call is gone from `execute_item`; (b) cleanup runs *before* `smart_commit` (one substance commit, not two); (c) cleanup is skipped entirely when there are no real changes (the `tasks.json` status flip alone never triggers it).

**`6ee0256`** pluralizes the summary line correctly (`doc`/`docs`, `entry`/`entries`) — the `doc_word`/`entry_word` lines above are the post-fix final state.

⚠️ **Scope note — do NOT over-apply:** the LLM `CLEANUP_PROMPT` call **still exists in the Phase-0 task-breakdown path** (~line 4729: `run_with_retry $AGENT --no-session -p "$CLEANUP_PROMPT"`). Only the *per-item* (`execute_item`) cleanup was replaced. The sister project must leave the breakdown cleanup as-is. `$SESSION_DIR/docs/` is a new per-item destination for stray docs.

---

### F. HALT Gate: Stop the Whole Run If Any Item Is `Failed` Before Validation — `de264c1`

**Problem solved / Root cause:** a single `Failed` item whose downstream dependents merely *deferred* (so the ISSUE_STREAK mid-loop halt — which needs a streak — never tripped) used to fall through to end-of-run validation, which re-reported the known failures, after which the old cleanup/commit path marched on as if nothing was wrong — implementation effectively stamped "complete" on top of known failures.

**Solution / Mechanism — a hard gate immediately after the execution loop** (inside the `SKIP_EXECUTION_LOOP != true` branch, before validation):
```bash
if [[ "$SKIP_EXECUTION_LOOP" != "true" ]]; then
    _failed_count=$(jq '[.. | objects | select(.status? == "Failed")] | length' "$TASKS_FILE" 2>/dev/null)
    if [[ "${_failed_count:-0}" -gt 0 ]]; then
        print -P ""
        print -P "%F{red}%B[HALT]%b%f %BImplementation incomplete: $_failed_count item(s) in Failed status.%b"
        print -P "%F{red}[HALT]%f Validation will not run on top of known failures."
        print -P "%F{red}[HALT]%f Failed items:"
        jq -r '[.. | objects | select(.status? == "Failed")] | .[] | "  - \(.id // "?")  \(.title // "")"' "$TASKS_FILE" 2>/dev/null | head -20
        print -P "%F{cyan}[HALT]%f Fix the root cause, then retry a failed item with:  tsk -f \"$TASKS_FILE\" next-failed --retry"
        [[ -n "$RESEARCH_PID" ]] && kill -TERM "$RESEARCH_PID" 2>/dev/null
        print -P "%F{blue}[GIT]%f Persisting current state before halt..."
        smart_commit
        exit 1
    fi
fi
```

**Behavior:** if ≥1 item is `Failed`, the run kills background research, persists state via `smart_commit`, prints the failed ids (capped at 20 via `head -20`), and `exit 1` — **validation never runs**. Skipped entirely in validation-only / bug-hunt-only modes (`SKIP_EXECUTION_LOOP == true`).

**Impact:** validation and the bug hunt never run on a known-incomplete implementation. The sister project must add this gate exactly where shown (after the four scope loops close, before the validation block) and only when the execution loop actually ran.

---

### G. Validation: Agent JSON Verdict Replaces the LLM CLEAN/DIRTY Classifier; Fixer Gets a Watchdog Budget + Incomplete-Fix Preservation — `414975f`, `de264c1`

**Problem solved / Root cause** (the validation analog of the bug-hunt false-negative): the post-validation decision of "does the fixer run?" was an LLM CLEAN/DIRTY classifier — a no-tools `$CLASSIFIER_AGENT` (default `pizc`) keyed off "passing status" in the report, inside a 4-try retry loop. A cheap model read a "PASS with minor notes" report as CLEAN and the fixer never ran, so the findings evaporated. Same lesson as the bug-hunt stage: the agent's structured verdict is the contract, and absence of a clean signal can never suppress a fix.

**Layer 1 — the validation agent now writes a structured verdict (`414975f`).** `VALIDATION_PROMPT` gained a **third required output file** and a verdict block. The output-files section changed:

*Before:*
```
**IMPORTANT: Use these EXACT file names:**
1. Write the validation script to `./validate.sh` ...
2. Write the bug tracker report to `./validation_report.md` ...
...
**CLEANUP NOTE:** These files (validate.sh and validation_report.md) are temporary ...
...
You write ONLY to `./validate.sh` and `./validation_report.md`.
```
*After:*
```
**IMPORTANT: Use these EXACT file names:**
1. Write the validation script to `./validate.sh` ...
2. Write the bug tracker report to `./validation_report.md` ...
3. Write your structured verdict to `./validation_result.json` (this exact path, current directory)
...
**Structured verdict (`validation_result.json`) - CRITICAL:**
The orchestrator decides whether to run the fixer from this file DETERMINISTICALLY
-- it does NOT re-read your prose report to guess. It MUST be valid JSON:
```json
{ "hasIssues": true, "issueCount": 3, "summary": "Brief one-line summary." }
```
- `hasIssues`: true if ANY issue (critical, major, OR minor) is listed in the
  report. false ONLY when the report lists zero issues.
- `issueCount`: the exact number of issues listed in validation_report.md.
  MUST be 0 when hasIssues is false.
A missing, malformed, or self-contradictory verdict is treated as "issues found"
and the fixer runs anyway -- so emit it correctly and keep it consistent with
your report. (A cheap LLM-classifier gate here once misread a "PASS with minor
notes" report as clean and silently dropped real findings.)
...
**CLEANUP NOTE:** These files (validate.sh, validation_report.md, validation_result.json) are temporary ...
...
You write ONLY to `./validate.sh`, `./validation_report.md`, and `./validation_result.json`.
```

**Layer 2 — the orchestrator decides deterministically (`414975f`).** The entire `CHECK_PROMPT` / classifier retry loop was **deleted** and replaced with `jq` over `validation_result.json`. **Safe default: a missing / unparseable / contradictory verdict RUNS the fixer** — the *only* path that skips it is an explicit `hasIssues==false && issueCount==0`:
```bash
    RUN_FIXER="true"
    VAL_HAS_ISSUES="missing"
    VAL_ISSUE_COUNT="-1"
    if [[ -f "validation_result.json" ]]; then
        VAL_HAS_ISSUES=$(jq -r '.hasIssues // "missing"' "validation_result.json" 2>/dev/null)
        VAL_ISSUE_COUNT=$(jq -r '.issueCount // -1' "validation_result.json" 2>/dev/null)
        if [[ "$VAL_HAS_ISSUES" == "false" && "$VAL_ISSUE_COUNT" == "0" ]]; then
            RUN_FIXER="false"
            print -P "%F{cyan}[STATUS]%f Validation verdict: CLEAN (hasIssues=false, issueCount=0). No fixer needed."
        else
            print -P "%F{cyan}[STATUS]%f Validation verdict: ISSUES (hasIssues=$VAL_HAS_ISSUES, issueCount=$VAL_ISSUE_COUNT). Fixer will run."
        fi
    else
        print -P "%F{yellow}[STATUS]%f No validation_result.json verdict found. Defaulting to RUN fixer (never silently skip)."
    fi
    if [[ "$RUN_FIXER" == "true" ]]; then
        ... run fixer ...
    fi
```
**Removed:** `$CHECK_PROMPT`, the `$CLASSIFIER_AGENT` system-prompt call here, the `classify_attempt`/`classify_max=4` retry loop, and the `if [[ "$CLEAN_RESULT" == "DIRTY" ]]` branch. (`CLASSIFIER_AGENT` is still defined and still used by the bug-hunt FORCE step — see item H.)

**Layer 3 — fixer watchdog budget + incomplete-fix preservation (`de264c1`).**
- **New env var `FIX_TIMEOUT`** (default `14400` = 4h), declared near `VALIDATION_TIMEOUT`:
  ```bash
  # The validation-driven fixer re-runs lint/typecheck/the full test suite and
  # rebuilds while iterating on EVERY reported issue — strictly more work than
  # inspecting, so it gets a bigger watchdog budget than validation itself. ...
  FIX_TIMEOUT="${FIX_TIMEOUT:-14400}"
  ```
- The fixer is invoked with `PI_AGENT_TIMEOUT=$FIX_TIMEOUT run_with_retry_stdin "$FIX_PROMPT" $IMPL_AGENT --no-session || fix_rc=$?` and its exit classified: `0` → "Fixes applied."; `124` (watchdog) → `FIX_INCOMPLETE=1`, "exceeded the watchdog budget"; anything else → `FIX_INCOMPLETE=1`, "fixer failed".
- **Artifact preservation** (root-caused from a real loss: the watchdog once killed the fixer mid-fix, then this step `rm`'d the only copy of `validation_report.md`). Before any deletion, `validation_report.md`, `validation_result.json`, and `validate.sh` are `cp -f`'d into `$SESSION_DIR/` (only when a session dir exists; `PRESERVED_REPORT` records the report path). Then:
  - if `FIX_INCOMPLETE==1`: keep the artifacts in cwd too (immediately visible) and **skip the final `smart_commit`** so partial work is not stamped as a clean "fixed" commit;
  - else: the agent is asked to delete the three files (with an `rm -f` backup) and the preserved path is logged.

The final-commit guard:
```bash
if [[ "${FIX_INCOMPLETE:-0}" == "1" ]]; then
    print -P "%F{yellow}[GIT]%f Skipping auto-commit (fixer did not complete). Partial changes remain in the working tree — review and commit manually."
else
    print -P "%F{blue}[GIT]%f Committing final changes with smart commit..."
    smart_commit
fi
```

**Impact:** the fixer can no longer be silently suppressed; it gets enough time; and an interrupted fix never destroys its own report. The sister project must add the `validation_result.json` verdict to the prompt, replace the classifier with the `jq` gate, add `FIX_TIMEOUT`, the `fix_rc`/`FIX_INCOMPLETE` handling, the artifact-preservation `cp`s, and the guarded final commit.

---

### H. Bug Hunt: Deterministic JSON Verdict, Transcript Capture, Forced Conversion, No "Clean by Default" — `5bd1af5`, `15dd00a`, `572aa29`, `de264c1`

This completes and **supersedes** the transcript *signal-count regex scanner* backstop from the prior `fc727a4` section (items AG/AH). The prose regex is gone; the agent's **emitted JSON** is the single source of truth, parsed by the orchestrator. The whole bug-hunt block was rewritten across four commits; the net final state is below.

**Commit roles in this feature:**
- `5bd1af5` — introduced transcript capture (`CAPTURE_STDOUT`), `BUG_HUNT_TRANSCRIPT`, the `INCONSISTENT_BUG_HUNT.md` marker, and the first prompt→JSON rewrite.
- `15dd00a` — **intermediate only, fully superseded in the final file.** It refined the (now-removed) regex scanner into a two-tier `BUG_CLAIM_PAT`/`BUG_STRUCT_PAT` system (explicit bug-claims ⇒ 1 ⇒ inconsistent; structural/emoji-severity markers ⇒ ≥2 ⇒ inconsistent; a `BUG_NEG` filter stripped template echoes + negative statements). **None of this code survives** — `de264c1` deleted the entire regex approach and replaced it with the deterministic JSON resolver. Documented here only so the commit is accounted for; the sister project implements the JSON system, not this scanner.
- `572aa29` — `render_bug_results_md()`, `BUG_RESULTS_JSON`, and the prompt's strict TestResults schema.
- `de264c1` — `resolve_bug_verdict()`, the FORCE step, and the final `case found|clean|invalid`.

**New env / paths:**
- `BUG_RESULTS_JSON="$CURRENT_BUGFIX_SESSION/bug_hunt_result.json"` — the agent's **only** required output (TestResults JSON).
- `BUG_HUNT_TRANSCRIPT="$CURRENT_BUGFIX_SESSION/bug-hunt-transcript.log"` — captured combined stdout+stderr.
- **`CAPTURE_STDOUT`** — an *opt-in* env var consumed by `run_with_retry_stdin`. When set, the agent runs `eval "${(q)@}" < "$tmp" 2>&1 | tee "$CAPTURE_STDOUT"` with `exit_status=$pipestatus[1]` (the agent's status; tee's is intentionally ignored). Other call sites are unaffected. It exists so a report the agent writes only to chat (and never to the file) is still recoverable:
  ```bash
        if [[ -n "$CAPTURE_STDOUT" ]]; then
            eval "${(q)@}" < "$tmp" 2>&1 | tee "$CAPTURE_STDOUT"
            exit_status=$pipestatus[1]
        else
            eval "${(q)@}" < "$tmp"
            exit_status=$?
        fi
  ```

**`BUG_FINDING_PROMPT` rewritten (`5bd1af5`, `572aa29`).** Phase 4 changed from "Documentation as Bug Report" (a markdown template the agent filled in *only* for Critical/Major) to "Report Findings as a Structured JSON VERDICT". The agent now writes ONE file — `$BUG_RESULTS_JSON` — **every run**, clean or not. The prompt is expanded with both variables:
```bash
EXPANDED_BUG_PROMPT=$(echo "$BUG_FINDING_PROMPT" | BUG_RESULTS_FILE="$BUG_RESULTS_FILE" BUG_RESULTS_JSON="$BUG_RESULTS_JSON" envsubst '$BUG_RESULTS_FILE:$BUG_RESULTS_JSON')
```
The required schema (a concrete valid example is given in-prompt, with `severity`/`reproduction`/`location` fields):
```json
{ "hasBugs": true,
  "bugs": [ { "id":"BUG-001", "severity":"critical", "title":"...",
              "description":"...", "reproduction":"...", "location":"src/path:123" } ],
  "summary":"...", "recommendations":["..."] }
```
and for a clean hunt: `{ "hasBugs": false, "bugs": [], "summary": "...", "recommendations": [] }`.
The prompt's new "Output Rules - CRITICAL" mandates: always write the file (clean or not); `hasBugs` MUST equal (bugs non-empty) — cross-checked; use **exactly** `critical`/`major`/`minor` with an explicit **High→Critical / Medium→Major / Low→Minor** map (the taxonomy-mismatch fix); record **every** issue including minor; write only valid JSON to that one path (the orchestrator renders the markdown); plus a 3-point final self-check. The FORBIDDEN list's `**/TEST_RESULTS.md` line now reads "(the orchestrator renders these from your JSON; do not write them yourself)", and the agent is explicitly told it must NOT write `TEST_RESULTS.md` or `NO_ISSUES_FOUND.md`.

**The run** launches the finder with `CAPTURE_STDOUT="$BUG_HUNT_TRANSCRIPT"`, and resume-detection now accepts **either** a rendered `TEST_RESULTS.md` **or** the raw JSON contract as an existing result.

**`render_bug_results_md()` (`572aa29`)** — the **orchestrator** (not the agent) now owns `TEST_RESULTS.md`. A `python3` heredoc renders the TestResults JSON into the markdown the downstream bug-fix breakdown consumes (it indexes sections by h2/h3). It tolerates a ```` ```json ```` fence and missing optional fields, groups bugs by `critical`/`major`/`minor`, and emits the `# Bug Fix Requirements` / Overview / per-severity / Testing Summary / Recommendations structure. Signature: `render_bug_results_md <json_path> <out_md_path>`; `sys.exit(1)` on invalid JSON.

**`resolve_bug_verdict()` (`de264c1`)** — the deterministic verdict resolver (`python3` heredoc). **Strict rule:** `clean` iff the agent *explicitly* declared `{hasBugs:false, bugs:[]}`; `found` iff `bugs` is non-empty; `invalid` otherwise (missing / malformed / `hasBugs:true` with empty bugs / empty bugs with no explicit `false`). **Source priority:** (1) the JSON file if it holds a valid TestResults object; (2) the LAST `{...}` / ```` ```json ```` block in the transcript that validates as `{bugs:[…]}` — preferring objects carrying an explicit `hasBugs` key, **last-in-document wins** (the agent's final output). A prefilter (`bugs`/`hasBugs`/`has_bugs` must appear within the next 400 chars of a `{`) keeps a prose transcript with stray braces fast. **Severities are canonicalized** via a dict (`high`/`p0`/`blocker`/`fatal`/`severe`→`critical`; `medium`/`p1`/`moderate`/`normal`→`major`; `low`/`p2`/`trivial`/`cosmetic`/`polish`/`nice`/`info`→`minor`, etc.); uncanonicalizable severities default to `minor`. On `found`/`clean` it **rewrites the canonicalized object** to the JSON file (durable record). It prints exactly one JSON line to stdout:
```json
{"verdict":"found|clean|invalid","bug_count":N,"source":"file|transcript|none","reason":"..."}
```
Signature: `resolve_bug_verdict <transcript_path> <json_file_path>`.

**The FORCE step (`de264c1`).** If the first resolve returns `invalid` and the transcript is non-empty, a single no-tools call (`$CLASSIFIER_AGENT --system-prompt "$FORCE_SYS"`) is fed the transcript via stdin and told to output **only** the TestResults JSON. The system prompt embeds the full schema + the severity map + "You MUST list EVERY issue the report describes; do not omit any.":
```
FORCE_SYS="You convert a bug-hunt report into a STRICT JSON object and output ONLY that JSON -- no prose, no code fences. Schema: {\"hasBugs\":boolean,\"bugs\":[{\"id\":string,\"severity\":\"critical\"|\"major\"|\"minor\",\"title\":string,\"description\":string,\"reproduction\":string,\"location\":string}],\"summary\":string,\"recommendations\":[string]}. Map the report's own severity scale onto critical/major/minor (High/P0/blocker->critical, Medium/P1/should-fix->major, Low/P2/minor/trivial/polish->minor). If the report describes NO real defects, output {\"hasBugs\":false,\"bugs\":[],\"summary\":\"...\",\"recommendations\":[]}. You MUST list EVERY issue the report describes; do not omit any."
```
The transcript is passed via a temp `FORCE_BODY_FILE` (it can exceed `MAX_ARG_STRLEN`); its `FORCE_OUT` is re-resolved with `resolve_bug_verdict`. If it still yields no verdict, the run falls through to the `invalid` branch.

**The `case "$BUG_VERDICT"` (final):**
- **`found`** — clear stale `NO_ISSUES_FOUND.md` and `INCONSISTENT_BUG_HUNT.md`; `render_bug_results_md "$BUG_RESULTS_JSON" "$BUG_RESULTS_FILE"`; `git add` **both** the md and the JSON; commit `"Add bug report: <session>"`; recurse the pipeline (`SKIP_BUG_FINDING=true PRD_FILE="$BUG_RESULTS_FILE" SCOPE=… PLAN_DIR="$CURRENT_BUGFIX_SESSION" PARALLEL_RESEARCH=… RESEARCH_DEPTH=… "$0"`).
- **`clean`** — the **only** path to "no issues": agent explicitly declared `hasBugs:false, bugs:[]`. Writes `NO_ISSUES_FOUND.md` (wording now "the agent EXPLICITLY declared no bugs … a missing/invalid verdict is treated as INCONSISTENT, never clean"), `git add` the marker + the JSON contract, commit `"No issues found (explicit clean verdict): <session>"`, then `rm` the transcript and `rmdir` the session.
- **`*` (invalid)** — **never clean.** Prints red "NO VALID VERDICT … Refusing to mark this run clean. There is no 'clean by default' …", writes `INCONSISTENT_BUG_HUNT.md` (full recovery instructions: transcript path + expected JSON path), `git add` the marker + the transcript, commit `"No valid bug-hunt verdict (missing/invalid JSON): <session>"`, and **keeps** the session dir + transcript as evidence.

**Removed (the prior-section backstop, now superseded):** the transcript signal-count regex scanner (and `15dd00a`'s two-tier refinement of it), the threshold-≥2 INCONSISTENT trigger, and the old `BUG_RESULTS_FILE` file-presence ⇒ clean branch.

**Impact:** the bug hunt can no longer silently lose findings or falsely mark itself clean. The durable artifacts are `bug_hunt_result.json` (always), `bug-hunt-transcript.log` (kept until the run resolves clean/invalid), `TEST_RESULTS.md` (rendered, found only), and the `NO_ISSUES_FOUND.md` / `INCONSISTENT_BUG_HUNT.md` markers. The sister project must reproduce: the two new paths + `CAPTURE_STDOUT` in `run_with_retry_stdin`, the prompt rewrite + `envsubst`, `render_bug_results_md`, `resolve_bug_verdict` (with the canonicalization dict and the clean-only-on-explicit-`false` rule), the FORCE step, and the three-way `case`.

---

## Commit History (this section)

Commits touching `run-prd.sh`, oldest → newest (all are pipeline code; none are docs-only):

- `5bd1af5` fix(prd): catch orphaned bug reports  *(bug-hunt JSON verdict, transcript capture, INCONSISTENT marker — item H)*
- `15dd00a` fix(prd): detect freeform bug findings in transcript  *(intermediate two-tier regex scanner — **fully superseded by `de264c1` in the final file**; documented in item H for completeness)*
- `572aa29` feat(prd): precise prd diffs and strict json schema  *(per-file manifests + change reports — item B; `render_bug_results_md` + `BUG_RESULTS_JSON` + prompt schema — item H)*
- `de264c1` fix(prd): enforce explicit verdicts and gate on failures  *(markdown-aware includes — item A; HALT gate — item F; `FIX_TIMEOUT` + incomplete-fix preservation — item G; `resolve_bug_verdict` + FORCE step + final bug-hunt `case` — item H)*
- `c740592` fix(prd): require self-certification over file diffs  *(no-gaps invariant + `--focus-only`/`--dry-reconcile` — item C; self-cert completion gate + re-prompt + interrupt→Planned rollback — item D)*
- `1a9fc08` fix(prd): replace agent cleanup with deterministic reorg  *(deterministic per-item cleanup — item E)*
- `414975f` fix(prd): replace validation classifier with agent verdict  *(validation JSON verdict gate + prompt — item G)*
- `6ee0256` fix(prd): pluralize cleanup log message correctly  *(pluralization in `cleanup_deterministic` — item E)*
