# Changelog and Technical Specification

## Changes Since Commit 37e81cc5

**Base commit:** `37e81cc5` - "rewrite PRD spec with detailed technical implementation plan"
**Latest commit:** `d9bf0b3` - "fix(prd): enhance task subcommand and bug hunt workflow"
**Date range:** Commits b569e7f through d9bf0b3 (8 commits)
**Files changed:** `run-prd.sh` (+299 lines, -136 lines)

---

## Summary of Changes

This release introduces a major refactor of the bug hunt workflow with a new self-contained session architecture, enhanced task management via the `prd task` subcommand, improved session completion handling, and better artifact management.

---

## Detailed Changelog

### 1. New `prd task` Subcommand (d9bf0b3)

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

### 2. Self-Contained Bug Fix Workflow (9382a85)

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

### 3. Bug Fix Artifact Archiving (c1cf485, 7bc3c3b)

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

### 4. Interactive Prompts for Bug Hunt (0edbd0c)

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

### 5. Session Completion Logic Enhancement (847ac48)

**Problem Solved:** When a session was complete, the script would exit before allowing bug hunt to run on completed work.

**Solution:** Introduced `SKIP_EXECUTION_LOOP` flag.

**Behavior:**
- When session is complete AND bug hunt is enabled:
  - Prompts user to confirm bug hunt
  - Sets `SKIP_EXECUTION_LOOP=true` to bypass task execution
  - Continues to validation and bug finding stages
- Main execution loops wrapped with `SKIP_EXECUTION_LOOP` check

---

### 6. Bug Fix Directory Structure Correction (b569e7f)

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

### 7. Tasks File Path Preservation (0cd59a6)

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

### 8. MCP Server Configuration for PRP Creation

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

### 9. Session Hash Calculation Change

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

### 10. Auto-Resume Logic Enhancement

**New Variables:**
- `RESUME_BUGFIX_TASKS_FILE` - Path to bug fix tasks to resume
- `RESUME_BUGFIX_SESSION` - Path to the bugfix session directory
- `AUTO_RESUME_TASKS_FILE` - Determines which file to check for auto-resume

**Priority Order for Auto-Detection:**
1. Incomplete bugfix sessions (new format)
2. Legacy `bug_hunt_tasks.json` at session level
3. Main session tasks

---

### 11. Git Command Noise Reduction

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

### 12. `is_session_complete()` Function Enhancement

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
| `BUG_FINDER_AGENT` | `glp` | Agent used for bug discovery |
| `BUG_RESULTS_FILE` | `TEST_RESULTS.md` | Bug report output file |
| `BUGFIX_SCOPE` | `subtask` | Granularity for bug fix tasks |
| `SKIP_BUG_FINDING` | `false` | Skip bug hunt stage |
| `SKIP_EXECUTION_LOOP` | `false` | Skip task execution (internal) |
| `RESUME_BUGFIX_TASKS_FILE` | (empty) | Auto-detected resume file |
| `RESUME_BUGFIX_SESSION` | (empty) | Auto-detected session path |

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
| `run-prd.sh` | 299 | 136 |

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
