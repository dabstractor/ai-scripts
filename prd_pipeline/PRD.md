# Hawk Agent PRD (Unified and Updated)

This document merges the **original PRP workflow specification** with the **latest Hawk Agent architecture**, preserving **all original requirements unless superseded**. The major change applied here is:

* **Removal of the Graybeard Reviewer persona** (no adversarial skeptic).
* **Addition of a cooperative, hierarchical agent review and communication system**, where implementation and review agents can request revisions to the PRP, update tests, and **restart the TDD loop cleanly**.

This document is the **authoritative PRD**.

---

## 1. Purpose

Hawk Agent is a **recursive, hierarchical agent system** for reliably implementing PRDs in arbitrary codebases, using:

* Structured decomposition into **PRP tasks**
* **Research-backed implementation planning**
* **TDD-based incremental execution**
* **Hierarchical review loops** that propagate corrections

The system ensures that features are implemented **correctly, safely, incrementally, and verifiably**.

---

## 2. Core Principles

* **Stateful Execution:** Session state stored in `~/.local/state/hawk_agent/...`
* **Composable Workflows:** Each agent is a workflow capable of spawning other workflows
* **Human-in-the-loop at any stage**
* **Three Project Pillars:** Testing, Logging, Linting — validated and enforced
* **Phantom Git:** All writes are committed to a shadow git repo before real commit

---

## 3. Session & Project Initialization (`hawk init`)

1. Create session workspace and phantom git.
2. Detect presence of:

   * Test framework & commands
   * Logging system
   * Linting rules
3. If pillars are missing → offer scaffolding.
4. Store configuration in `.hawk/settings`.
5. Commit project snapshot to phantom git.

---

## 4. High-Level Workflow Overview

1. **PRD Creation or Input**
2. **Task Breakdown into PRPs (recursive)**
3. **Task Prioritization and Concurrency Grouping**
4. **PRP Research & Drafting**
5. **Cooperative PRP Review Cycle**
6. **Test Generation (if applicable)**
7. **Feature Validation Strategy Definition**
8. **Implementation (TDD Loop)**
9. **Final Validation**
10. **Real Git Commit and Move to Next Task**

---

## 5. Detailed Workflow

### 5.1 PRD Breakdown Agent (Agent #1)

* Determines whether the PRD must be decomposed.
* If so, recursively break the PRD down into **1–3 story point tasks**.
* Tasks retain source PRD context.
* Depth-first breakdown stops when no task exceeds complexity threshold.

### 5.2 PRP Planning Research Agent (Agent #2)

* Performs deep research:

  * Codebase structure
  * Relevant frameworks & patterns
  * API boundaries
  * Architectural constraints
* Produces **PRP plans** for tasks, including:

  * API contracts
  * Type definitions
  * Implementation sequencing steps
* Stores results in session knowledge base.

### 5.3 Task Prioritization & Multithreading Agent (Agent #3)

* Orders tasks cautiously to avoid conflict.
* Creates **groups** when tasks can safely run concurrently.
* Defaults to **serial execution unless safety is certain**.

---

## 6. PRP Creation and Review Loop

### 6.1 PRP Creation Agent (Agent #4)

* Converts prioritized tasks into full PRPs:

  * Step-by-step implementation plan
  * Expected file changes and invariants
  * Dependency notes
* Ensures incremental safety and continuous project operability.

### 6.2 **Cooperative PRP Review Agent (Replaces Graybeard)** (Agent #5)

* **No adversarial persona**.
* Validates the PRP’s correctness and feasibility.
* Generates **review findings** instead of criticism.
* If issues are found:

  * Requests **PRP addendum revision** from Agent #4.
  * **Triggers automatic updates to tests & validation plan.**
  * Restarts the PRP–Review loop until stable.

This creates a **hierarchical communication model**:

```
Review Agent → Update PRP → Update Tests → Restart Implementation Session
```

---

## 7. Testing Integration

### 7.1 Test Suite Detection Agent (Agent #6)

* Determines whether unit tests exist.
* Extracts test framework, runner, directory layout, conventions.

### 7.2 Core Unit Test Authoring Agent (Agent #7)

* Based on:

  * PRD
  * PRP
  * Project test standards
* Produces **critical correctness tests**:

  * API shape
  * Behavior contracts
  * Failure modes

### 7.3 Feature Validation Strategy Agent (Agent #8)

* Ensures **complete end-to-end validation**:

  * Either automated validation script (≤ 300 LOC)
  * Or structured manual validation procedure
* Selects compatible **MCP tools** for execution.

---

## 8. Implementation: TDD Loop (Agent #9)

1. Apply PRP step incrementally.
2. Run **next test only**.
3. If pass → run full regression suite.
4. If failure:

   * Capture findings
   * Return context to PRP review agent (Agent #5)
   * **May trigger PRP addendum and test updates**, then restart loop.

This loop is bounded:

* Max attempts per step: 4
* Max PRP revision passes: 4

---

## 9. Final Validation Agent (Agent #10)

* Executes:

  * Unit tests (Agent #7)
  * Validation script or manual checklist (Agent #8)

If validation **fails**:
→ Agent #11 performs **PRP addendum research update**, then return to **PRP Review (Agent #5)**.

If validation **passes**:
→ Commit to **real git** and move to the next task.

---

## 10. Phantom Git Rules

* Every write operation → phantom commit.
* Real commits occur **only** after passing full validation.
* Full rollback possible at every loop boundary.

---

## 11. Communication Model

Agents communicate through:

* Shared **session knowledge base**
* PRP revision packets
* Explicit **review → revise → test → re-implement** signaling

The system is intentionally **cooperative**, not adversarial.

---

## 12. Termination Conditions

* Each feature task completes only upon:

  * Code implemented
  * Tests passing
  * Validation passing
  * Final review confirming PRD requirement fulfillment

* Entire run ends when:

  * All PRD tasks are completed and validated.

---

## 13. Open TBD Areas

| Area                                   | Status |
| -------------------------------------- | ------ |
| Recursive breakdown scoring metrics    | TBD    |
| Research caching & re-use model        | TBD    |
| Phantom git revert heuristics          | TBD    |
| Cross-agent context propagation APIs   | TBD    |
| Optional Ink UI live session dashboard | TBD    |

---

**End of Document**

