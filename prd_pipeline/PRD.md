# Hawk Agent PRD (Fully Expanded)

> This PRD integrates all original markdown files, follow-up prompts, and user instructions in their entirety. No information has been removed or condensed. "TBD" sections are clearly indicated.  

---

## 1. Overview
Hawk Agent is designed as a highly composable, recursive agent system capable of implementing any PRD in any codebase. Its design emphasizes:  

- **State persistence:** All ephemeral session data is stored locally per project session.  
- **Composability:** Workflows (equivalent to React components) can render other Workflows, perform synchronous actions, or trigger asynchronous processes.  
- **Human-in-the-loop:** Any agent in the hierarchy can request human intervention, which takes primary focus.  
- **Context propagation:** Parent agents can pass props, callbacks, and context to children, similar to React/Redux.  
- **Three pillars of codebase success:** Testing, Logging, Linting. Each pillar is validated and used to improve agent performance.  
- **Phantom Git system:** Every workspace action is tracked with phantom git commits for rollback and validation before committing to real git.  

---

## 2. Directory and Session Layout

- Session directory: `~/.local/state/hawk_agent/<absolute_path_to_session_cwd>/<session_uid>`  
- Ephemeral state, phantom git `.git`, project analysis, PRPs, and session-specific data are stored here.  
- `.hawk/` in project root stores persistent project settings and generated documents.  

---

## 3. Main Flow (Updated and Corrected)

### 3.1 PRD Creation

1. Prompt user until confidence threshold is achieved.  
2. Optionally perform light research to validate assumptions.  
3. Create the PRD document.  
4. Output PRD for review.  

**TBD:** Exact prompting logic and research integration details.  

### 3.2 PRD Breakdown

1. Check if `hawk init` has been run; if not, run it.  
2. Break PRD into sensible chunks.  
3. Recursively break chunks into tasks of story point size 1 or 2.  
4. Perform general research for all tasks and store in session.  

**TBD:** Recursive breakdown algorithm and task scoring metrics.  

### 3.3 Task Prioritization & Concurrency Analysis

1. Err on the side of consecutive execution.  
2. Build a **custom tool** to standardize task list access and interaction for all agents.  

---

## 4. Init Subflow

**Purpose:** Initialize session, detect project pillars, scaffold missing configs, and prepare .hawk/settings.  

```mermaid
flowchart TD
  Start[Start: user runs hawk init] --> CreateSession[Create session directory and phantom git]
  CreateSession --> ProjectScan[Project scan: detect tests, linter, logging]
  ProjectScan --> PillarsFound{Are all pillars found?}
  PillarsFound -- Yes --> Populate[Populate .hawk/settings and commit snapshot]
  PillarsFound -- Partial --> PromptUser[Prompt user: scaffold missing pillars?]
  PromptUser -- Yes --> Scaffold[Scaffold configs, validate scaffolds, commit snapshot]
  PromptUser -- No --> RecordPref[Record user preference in .hawk/settings]
  Populate --> Done[Done: session initialized]
  Scaffold --> Done
  RecordPref --> Done

````

**Notes:**

* Multiple pillar detection logic (TDD, Logging, Linting).
* Human prompt required if partial or missing pillars.
* Phantom git commit occurs after every stage for rollback.

---

## 5. Task Implementation Flow (PRP Research → TDD Loop)

1. Ensure phantom git workspace is fully committed.

2. Select next task.

3. PRP Research: deep dive all relevant topics, create master prompt packet for implementer and test creation agents.

4. **TDD Testing Agent Overseer:**

   * Gather exact commands for regression vs next test.
   * Validate commands work reliably.

5. Dynamically-created **Implementer Agent:**

   * Executes implementation using custom tools.
   * Uses feedback from logging, linter, and test results.
   * Configurable number of prompts until test passes or context/prompt limits reached.

6. Agent output must indicate: **success, fail, issue**.

   * **fail:** invoke external review for better agent configuration.
   * **issue:** request test/tooling modifications for next agent session.

7. Escalation paths:

   * Root Cause Analysis → Fagan Inspection → Independent Review → Human-in-the-loop (as last resort).

8. After test passes:

   * Cleanup temporary documents.
   * Stage work and run final verification.
   * Commit to **real git**.

**TBD:** Granular phantom git commit policy and exact cleanup procedures.

---

## 6. TDD Loop Subflow

```mermaid
flowchart TD
  TaskStart[Start Begin task] --> TestTasker[Test Tasker find next test and produce test config]
  TestTasker --> PromptWriter[Prompt Writer build implementer prompt]
  PromptWriter --> Implementer[Implementer single attempt]
  Implementer --> RunNext[Orchestrator runs run next test]
  RunNext --> Passed{Did next test pass}
  Passed -- Yes --> RunReg[Run regression tests using run regression tests]
  RunReg --> RegPass{Any regression failures}
  RegPass -- No --> Commit[Commit phantom git update state move to next task]
  RegPass -- Yes --> AnalyzeRegs[Analyze failures add findings to feedback]
  AnalyzeRegs --> PromptWriter
  Passed -- No --> RePrompt[Re prompt Implementer with failure context and attempt number]
  RePrompt --> Implementer
```

**Notes:**

* TDD agents validate commands with multiple agents for accuracy.
* All custom tools (`run_next_test`, `run_regression_tests`, `modify_test`) produce unambiguous results.
* Feedback loops escalate complexity and tooling usage progressively.

---

## 7. Three Pillars

### 7.1 Testing Pillar

* Commands for tests must be repeatable and accurate.
* Testing agent collaborates with multiple agents to validate command generation.
* PRP session may update testing tools or test structure.

**TBD:** Automated handling of test identification for all languages/frameworks.

### 7.2 Logging Pillar

* Analyze project logging system.
* Optionally add `HawkAgent` logging level.
* Logging configuration validated during init.
* Test runner uses correct logging levels.

### 7.3 Linting Pillar

* Init process sets up linting rules; updates may occur during feedback cycles.
* `update_linting_rules <prompt>` custom tool allows human or automated review to inject rules.
* Linting validated at script-level after each PRP/implementation cycle.

---

## 8. Phantom Git Integration

* Every file write triggers phantom git commit.
* Commit logic integrates with Claude hooks.
* Allows rollback for any agent failure.

**TBD:** Define rollback policy relative to TDD loops and implementation attempts.

---

## 9. Human-in-the-Loop Integration

* Any agent can request user attention.
* Takes primary focus and allows direct intervention.
* Human decisions may modify PRP, update tooling, or resolve ambiguities.

---

## 10. Context and Communication

* Workflows pass **props**, **callbacks**, and **context channels**.
* Recursive tree structure enables deep agent nesting.
* Communication is two-way and hierarchical.
* Inspired by React/Redux context system, but customized for agent lifecycles.
* **Ink integration TBD:** investigate uniform mechanism for linking UI element lifecycles with agent lifecycles.

---

## 11. Workflow Composition

* Each Workflow (script/module) can:

  * Render other Workflows.
  * Execute synchronous actions.
  * Trigger asynchronous processes that create more Workflows.
* Asynchronous actions may include spawning implementer agents, TDD agents, PRP research agents, etc.
* Consider **sagas** for orchestrating long-lived async workflows.

---

## 12. Logging & Tracing

* Centralized logging of all agent actions.
* Logs persist in session directory.
* Supports:

  * Debugging.
  * State recovery.
  * Audit trail for PRP execution and TDD loops.

---

## 13. Research & PRP Tools

* PRP agents gather and validate research relevant to tasks.
* Stores results in session for downstream agent use.
* Ensures all agents operate on consistent knowledge base.

**TBD:** Standardization of research storage and retrieval.

---

## 14. Escalation & Error Handling

1. Implementer fails → attempt re-run with updated tools or PRP.
2. Failures escalated to Root Cause Analysis agent.
3. Persistent failure → Fagan Inspection agent invoked.
4. Independent review if problem persists.
5. Human-in-the-loop is last resort.

---

## 15. Session State & Cleanup

* Cleanup after task success: remove temporary files and documents.
* Stage all modified files → final verification → commit to real git.
* Phantom git continues to track every intermediate step.

---

## 16. Notes & TBD

* Recursive task breakdown algorithm: TBD.
* Research integration in PRD creation: TBD.
* Phantom git rollback policy details: TBD.
* Ink framework integration: TBD.
* Test identification for all frameworks/languages: TBD.
* Cleanup procedures for temporary documents: TBD.
* Exact saga orchestration patterns for long-lived workflows: TBD.
* Feedback cycle configuration and escalation thresholds: TBD.

