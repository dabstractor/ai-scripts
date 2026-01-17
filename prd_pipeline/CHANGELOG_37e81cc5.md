# Changelog and Technical Specification

## Changes Since Commit 37e81cc5

**Base commit:** `37e81cc5` - "rewrite PRD spec with detailed technical implementation plan"
**Latest commit:** `5b01ab7` - "fix(prd): add nested execution guard and agent operational boundaries"
**Date range:** Commits b569e7f through 5b01ab7 (13 commits)
**Files changed:** `run-prd.sh` (+590 lines, -170 lines)

---

## Summary of Changes

This release introduces a major refactor of the bug hunt workflow with a new self-contained session architecture, enhanced task management via the `prd task` subcommand, improved session completion handling, and better artifact management. Additionally, strict operational boundaries have been added to all pipeline agents to prevent accidental pipeline corruption, and a nested execution guard prevents agents from recursively invoking the pipeline during implementation. Recent updates have further hardened these guards with session path validation and removed the separate BUG_FIX_MODE in favor of consistent SKIP_BUG_FINDING usage.

---

## Detailed Changelog

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

Old sessions with these files at session root level are still supported:
- `bug_hunt_tasks.json` - Legacy bug hunt tasks
- `bug_fix_tasks.json` - Legacy bug fix tasks (backwards compat check)
- `TEST_RESULTS.md` - Bug reports at session level

The new format stores everything within `bugfix/NNN_hash/` subdirectories.

### Breaking Changes

None. The changes are backwards compatible with existing sessions.

---

## Files Changed

| File | Lines Added | Lines Removed |
|------|-------------|---------------|
| `run-prd.sh` | 590 | 170 |
| `CHANGELOG_37e81cc5.md` | 127 | 17 |

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
