# Detailed Technical Specification: Autonomous PRP Pipeline

## 1. Introduction

This document provides a comprehensive technical specification for reimplementing the Autonomous PRP Development Pipeline. It is derived from a rigorous analysis of the original `run-prd.sh` bash script and its dependencies. This specification captures every logical branch, state transition, and file operation required to replicate the system's behavior in a robust framework (e.g., Python, Rust, Go).

**Reference Materials:**
*   `PROMPTS.md`: Contains the exact text of all HEREDOC prompts referenced in this spec.
*   `run-prd.sh`: The reference implementation.

## 2. System Architecture & Components

The system is an orchestrated loop that manages project state through immutable "Session" directories.

### 2.1 Core Components
1.  **Session Manager:** Manages the `plan/{sequence}_{hash}/` directory structure, state persistence, and PRD diffing.
2.  **Task Orchestrator:** Manages the `tasks.json` backlog, state transitions, and dependency resolution.
3.  **Agent Runtime:** Interfaces with the LLM using specific personas (Architect, Researcher, Coder, QA).
4.  **Pipeline Controller:** The main execution loop handling arguments, signals, and parallel research.

## 3. Detailed Logic Specification

### 3.1 Argument Parsing & Configuration
**Source:** `run-prd.sh` (Lines 26-60)

The system must accept the following CLI arguments, with the following precedence and defaults:

| Flag | Variable | Default | Description |
| :--- | :--- | :--- | :--- |
| `-s`, `--scope` | `SCOPE` | `subtask` | Execution scope: `phase` \| `milestone` \| `task` \| `subtask` |
| `-p`, `--phase` | `START_PHASE` | `1` | Start execution at Phase # |
| `-m`, `--milestone` | `START_MS` | `1` | Start execution at Milestone # |
| `-t`, `--task` | `START_TASK` | `1` | Start execution at Task # |
| `-u`, `--subtask` | `START_SUBTASK` | `1` | Start execution at Subtask # |
| `-r`, `--parallel-research` | `PARALLEL_RESEARCH` | `false` | Enable background research for Task N+1 |
| `-v`, `--validate` | `ONLY_VALIDATE` | `false` | Run *only* the validation phase |
| `--bug-hunt` | `ONLY_BUG_HUNT` | `false` | Run *only* the creative bug hunt loop |
| `--skip-bug-finding` | `SKIP_BUG_FINDING` | `false` | Skip bug finding after implementation |
| `--single-session` | `SINGLE_SESSION` | `false` | Disable auto-flow to new Delta Sessions |
| `--session` | `TARGET_SESSION` | `null` | Manually target a specific session ID (integer) |

**Logic:**
*   If any start position flag (`-p`, `-m`, `-t`, `-u`) is provided, `MANUAL_START` must be set to `true`.
*   Validation: `SCOPE` must be one of `phase`, `milestone`, `task`, `subtask`. Error otherwise.

### 3.2 Session Management Logic
**Source:** `run-prd.sh` (Lines 75-321)

The system operates on **Sessions**. A Session is a directory containing the immutable state of a run.

**Directory Structure:**
```
project_root/
├── PRD.md                 # The master PRD (user editable)
└── plan/                  # The Session Container
    ├── 001_abc123.../     # Session 1 (Sequence + PRD Hash)
    │   ├── tasks.json     # The Backlog (Pipeline State)
    │   ├── prd_snapshot.md # Immutable copy of PRD for this session
    │   ├── architecture/  # Research findings
    │   ├── docs/          # Documentation produced by agents
    │   └── ... (Task dirs)
    ├── 002_def456.../     # Session 2 (Delta Session)
    │   └── delta_from.txt # Contains "1" (pointer to parent session)
    └── ...
```

**Session State Resolution Algorithm:**
1.  **Calculate Current Hash:** `SHA256(PRD.md)[0:12]`
2.  **Find Latest Session:** `ls plan/ | sort | tail -1`
3.  **Determine State:**
    *   **NO_SESSIONS:** If `plan/` is empty -> Create Session 001.
    *   **CURRENT_MATCH:** If `LatestHash == CurrentHash`:
        *   Resume execution in Latest Session.
    *   **PRD_CHANGED:** If `LatestHash != CurrentHash`:
        *   If Latest Session is **Complete** (all tasks done):
            *   Create **Delta Session** (Sequence + 1, New Hash).
            *   Write `delta_from.txt` pointing to previous sequence.
        *   If Latest Session is **Incomplete**:
            *   **Prompt User:** "Integrate changes into current session OR Queue delta?"
            *   **Integrate:** Update `prd_snapshot.md`, trigger `TASK_UPDATE_PROMPT`.
            *   **Queue:** Create `.pending_delta_hash` file, finish current session, then auto-create delta.

**Session Completion Logic (`is_session_complete`):**
Returns `true` ONLY if:
1.  `tasks.json` exists.
2.  ALL tasks in `tasks.json` have status "Complete" or "Completed".
3.  NO bug hunt artifacts exist (`TEST_RESULTS.md`, `bug_hunt_tasks.json`, `bug_fix_tasks.json`).

### 3.3 Task Breakdown Phase (Phase 0)
**Source:** `run-prd.sh` (Lines 2051-2075)

If `tasks.json` does not exist in the Session Directory:
1.  **Agent Persona:** `TASK_BREAKDOWN_SYSTEM_PROMPT`.
2.  **Input:** `PRD.md` content.
3.  **Action:**
    *   Spawn subagents to research codebase/docs.
    *   Store findings in `architecture/`.
    *   Generate JSON backlog.
4.  **Output:** Write `tasks.json`.
5.  **Validation:** Verify file existence and valid JSON structure.
6.  **Commit:** `git add tasks.json && git commit -m "Add task breakdown..."`

### 3.4 The Execution Loop (The "Inner Loop")
**Source:** `run-prd.sh` (Lines 2104-2200)

Iterate through the backlog based on the configured `SCOPE`.
hierarchy: `Phase` -> `Milestone` -> `Task` -> `Subtask`.

**For each Item:**
1.  **Check Status:** If `Complete` -> Skip.
2.  **Parallel Research Check:**
    *   If `PARALLEL_RESEARCH=true`, identify `NextItem`.
    *   Spawn background process (thread/async task) to research `NextItem`.
    *   Pass `CurrentItem` context to `NextItem` researcher (Pre-computation).
3.  **Wait for Research:** If background research was running for `CurrentItem`, wait for it to finish.
4.  **PRP Generation (If not exists):**
    *   **Prompt:** `PRP_CREATE_PROMPT`.
    *   **Context:** Item Title, Description, Architecture notes.
    *   **Output:** Write `PRP.md` in item directory (e.g., `P1M1T1/PRP.md`).
    *   **Status Update:** Set status to `Researching`.
5.  **Implementation:**
    *   **Status Update:** Set status to `Implementing`.
    *   **Prompt:** `PRP_EXECUTE_PROMPT`.
    *   **Action:** Agent reads `PRP.md`, implements code, runs validation.
    *   **Loop:** Fix/Retry until validation passes.
6.  **Completion:**
    *   **Status Update:** Set status to `Complete`.
    *   **Cleanup:** Run `CLEANUP_PROMPT` (Move docs to `docs/`, remove temps).
    *   **Smart Commit:** `git add -A`, protect `tasks.json`, `git commit`.

### 3.5 Parallel Research Logic
**Source:** `run-prd.sh` (Lines 1630-1713)

*   **Trigger:** Before starting implementation of Item N.
*   **Target:** Item N+1.
*   **Context Passing:** The researcher for N+1 receives a warning: "Item N is currently being implemented. Treat its PRP as a CONTRACT."
*   **Locking:** Use PIDs or Lockfiles to ensure the main loop waits for research to finish before starting implementation of N+1.

### 3.6 Signal Handling (Graceful Shutdown)
**Source:** `run-prd.sh` (Lines 383-415)

*   **First SIGINT (Ctrl+C):**
    *   Set `SHUTDOWN_REQUESTED=true`.
    *   Log "Graceful shutdown requested. Will exit after current item completes."
    *   Do NOT kill current agent.
*   **Second SIGINT:**
    *   Force Kill immediately (`exit 130`).
*   **Check Loop:** After every item completion, check `SHUTDOWN_REQUESTED`. If true, exit 0.

### 3.7 The "Smart Commit" Protocol
**Source:** `run-prd.sh` (Lines 1935-1954)

When committing changes, the system must **Protect Critical State**:
1.  `git add -A` (Stage everything).
2.  **Safety Check:** If `tasks.json` was deleted/modified destructively, RESTORE it from HEAD before committing.
3.  **Unstage Future Work:** If Parallel Research created directories for NextItem (`plan/P1M1T2/`), unstage them (`git reset HEAD -- plan/P1M1T2`).
4.  Commit with AI-generated message (via `commit-claude` alias).

### 3.8 The Bug Hunt Loop
**Source:** `run-prd.sh` (Lines 2296-2354)

After all tasks are complete (or if `--bug-hunt` flag used):
1.  **Validation:** Run `VALIDATION_PROMPT` to generate `validate.sh` and `validation_report.md`.
2.  **Fix Check:** If report is "DIRTY", spawn Fixer Agent.
3.  **Creative Hunt Loop:**
    *   **Prompt:** `BUG_FINDING_PROMPT`.
    *   **Condition:** Agent writes `TEST_RESULTS.md` ONLY if bugs found.
    *   **If File Exists:**
        *   Enter **Bug Fix Mode**:
        *   Treat `TEST_RESULTS.md` as PRD.
        *   Create `bug_hunt_tasks.json`.
        *   Recursively run the pipeline on this new "mini-project".
        *   On success, delete artifacts and repeat Hunt Loop.
    *   **If File Missing:** Success. Exit.

## 4. Migration Logic
**Source:** `migrate-to-sessions.sh`

When starting, if legacy structure is detected (tasks.json in root), the system must:
1.  Create `plan/001_hash/`.
2.  Move `tasks.json`, `bug_hunt_tasks.json`, `TEST_RESULTS.md` to session dir.
3.  Move all folders in `plan/` (architecture, docs, P*) to session dir.
4.  Update global variables to point to new paths.

## 5. Implementation Roadmap

1.  **Data Models:** Define `Session`, `Task`, `Backlog` structs/classes.
2.  **State Manager:** Implement `load_session()`, `create_session()`, `save_session()`.
3.  **Prompt Engine:** Port `PROMPTS.md` to Jinja2 templates.
4.  **Agent Interface:** Create `Agent` class wrapping the LLM API (supports `run(prompt, context)`).
5.  **Orchestrator:** Implement the `execute_item()` loop with async research support.
6.  **CLI:** Implement `argparse`/`clap` logic matching the spec.
