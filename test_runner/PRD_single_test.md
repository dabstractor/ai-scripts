Excellent — this version is much tighter and now aligns perfectly with your deterministic, controlled-agentic philosophy.
Below is your **updated PRD** reflecting all your clarifications, corrections, and the new `"dependency"` state, along with added determinism, JSON validation, git-based resets, and stricter state machine rules.

---

# **PRD: Deterministic TDD Agent Pipeline (v2)**

## **1. Overview**

This system defines a **controlled, deterministic TDD agent loop** that anchors all progress in **verifiable test outcomes**.
It ensures that an implementation agent **cannot lie** about its progress or success by grounding all evaluation in a reproducible regression baseline.

This loop governs the interaction between:

1. A **Baseline Agent** (test discovery and regression command generator)
2. An **Implementation Agent** (makes the next test pass)
3. An **Intelligent Review Agent** (enforces truth and recovery)

All agents communicate strictly via **validated JSON**, and all test verification happens through deterministic test execution in a **pristine local environment** on the developer’s machine.

---

## **2. Objectives**

1. ✅ **Deterministic test validation** — no progress is accepted without test-based proof.
2. ✅ **Regression protection** — no previously passing tests may fail.
3. ✅ **Agent honesty enforcement** — the controller cross-verifies all claimed results.
4. ✅ **Structured recovery** — “issue” or “dependency” states are handled predictably.
5. ✅ **Repeatable state** — every run begins from a clean baseline (`git reset --hard`).
6. ✅ **Strict schema discipline** — all agent I/O must pass JSON schema validation.

---

## **3. System Architecture**

### **3.1 Agent #1 — Baseline Agent**

**Purpose:**
Discover test commands, run the full test suite, and produce deterministic baselines for regression validation.

**Responsibilities:**

* Detect test runner command (e.g. `pytest`, `npm test`, etc.).
* Execute full suite and capture:

  * List of **passing tests** (fully qualified identifiers)
  * Count of **passing vs failing tests**
* Generate:

  * `baseline_regression_command`: Command that re-runs *only the initially passing tests* and fails if any of them fail.
  * `next_test_command`: Command for running the *next test to be implemented* (provided externally via CLI).
* Output structured JSON for the next agent with full project/test context.

**Command requirements:**

* Must include **environment reset** for every run (e.g., via `git reset --hard && clean_env.sh` or equivalent).
* Must exit deterministically (0 = success, non-zero = failure).

**Example Output:**

```json
{
  "baseline_summary": {
    "total_tests": 142,
    "passed": 137,
    "failed": 5
  },
  "passing_tests": [
    "tests/unit/foo_test.py::test_bar",
    "tests/api/test_login.py::test_valid_credentials"
  ],
  "baseline_regression_command": "git reset --hard && pytest -q --disable-warnings tests/unit/foo_test.py::test_bar tests/api/test_login.py::test_valid_credentials",
  "next_test_command": "pytest tests/new_feature/test_handles_edge_case.py::test_handles_edge_case",
  "context": {
    "project_summary": "Library for X performing Y.",
    "feature_scope": "Implement edge-case handling for new feature.",
    "test_suite_overview": "Pytest-based, grouped into unit/integration/regression."
  }
}
```

---

### **3.2 Agent #2 — Implementation Agent**

**Purpose:**
Make the designated next test pass while ensuring all baseline tests remain green.

**Inputs:**

* Baseline JSON output
* Copy of target test file (for hash integrity)
* CLI argument specifying the test to implement
* `baseline_regression_command` and `next_test_command`

**Process Flow:**

1. Receive inputs and verify environment reset (controller ensures `git reset --hard` before start).
2. Attempt to implement required feature or fix.
3. Declare one of the following **states**:

   * `"Success"` → Claims test passes and no regressions exist.
   * `"Failure"` → Could not make meaningful progress or execution failed catastrophically.
   * `"Issue"` → Stuck due to unclear requirements or ambiguity.
   * `"Dependency"` → Needs an external dependency, resource, or tool before proceeding.

**Controller Responsibilities:**

* Always re-run both `next_test_command` and `baseline_regression_command` after any `"Success"` claim.
* Compare test file hash to the stored hash:

  * If changed, trigger **Intelligent Review Agent** to determine if modification was justified.
* Reject `"Success"` if any baseline regressions or target test failures occur.

**Example Output:**

```json
{
  "state": "Dependency",
  "message": "Requires 'requests' library to implement API client.",
  "new_failures": [],
  "next_actions": "Recreate agent with dependency installed."
}
```

---

### **3.3 Agent #3 — Intelligent Review Agent**

**Purpose:**
Monitor, correct, and guide the Implementation Agent toward legitimate success.

**Responsibilities:**

* Handle `"Issue"` and `"Dependency"` states with contextual guidance.
* If `"Success"` was claimed but validation failed:

  * Re-inform agent of the false claim:

    > “You declared success, but the target test still fails. Please fix the implementation accordingly.”
* Detect cheating (e.g., test file modification without justification).
* Limit retries per “issue” or “false success” scenario.
* Trigger halt signal after max retries exceeded.

**Default Configurations:**

* `max_issue_retries`: 2
* `max_false_success_retries`: 3
* On exceeding limits: produce structured halt output for external orchestration.

---

## **4. Controller Script**

**Purpose:**
Coordinate the full loop with deterministic governance.

**Workflow:**

1. **Baseline Phase**

   * Run Baseline Agent
   * Validate JSON output (retry until valid)
   * Save baseline metadata: passing tests, test file hashes, commands

2. **Implementation Phase**

   * `git reset --hard` to pristine state
   * Run Implementation Agent with baseline JSON
   * Validate JSON output
   * Parse `state` and respond:

     * `"Success"` → Run validation commands.

       * If both exit 0 and hashes match → true success.
       * Else → reprompt with Intelligent Review Agent.
     * `"Failure"` → Invoke Intelligent Review Agent for guidance or termination.
     * `"Issue"` → Reprompt up to configurable limit.
     * `"Dependency"` → Recreate agent with declared dependency, then retry.

3. **Supervision Phase**

   * Intelligent Review Agent evaluates conditions and instructs next steps.
   * Controller enforces retry and halt policies.

4. **Context Compaction**

   * When implementation thread reaches 60% context usage:

     * Compact only conversational data.
     * Preserve deterministic state (commands, test hashes, counters, etc.) outside the context.

5. **Validation**

   * Every agent output validated against strict JSON schema.
   * On malformed JSON:

     > “Invalid output format. Please respond strictly in valid JSON conforming to schema.”

6. **Completion**

   * If all tests pass, emit success report:

     ```json
     {
       "final_state": "Success",
       "new_test": "test_handles_edge_case",
       "regressions": [],
       "total_passed": 138,
       "summary": "All baseline and new tests passing."
     }
     ```
   * If retries exhausted or dependencies unresolved → emit halt report:

     ```json
     {
       "final_state": "Halt",
       "reason": "Too many failed attempts",
       "unresolved_state": "Issue",
       "next_agent_hint": "Clarify database schema version mismatch."
     }
     ```

---

## **5. Determinism Guarantees**

| Guarantee                        | Mechanism                                          |
| -------------------------------- | -------------------------------------------------- |
| **Ground truth test validation** | Always re-run tests using exact baseline command   |
| **Clean environment**            | `git reset --hard` before every run                |
| **Immutable baseline**           | Fixed test ID list                                 |
| **Integrity enforcement**        | Test file hash check                               |
| **Schema correctness**           | JSON schema validation for every agent output      |
| **Controlled recovery**          | Finite retries with clear escalation               |
| **Compact context safely**       | Preserve deterministic data outside context memory |

---

## **6. Configuration Parameters**

| Parameter                    | Description                            | Default            |
| ---------------------------- | -------------------------------------- | ------------------ |
| `max_issue_retries`          | Consecutive issue loops allowed        | 2                  |
| `max_false_success_retries`  | False success cycles before halt       | 3                  |
| `compact_at_context_percent` | Context threshold for compaction       | 0.6                |
| `schema_path`                | Path to output JSON schema definitions | `./schemas/`       |
| `env_reset_command`          | Command to restore pristine state      | `git reset --hard` |
| `validate_test_hash`         | Enable test file integrity check       | true               |

---

## **7. Out of Scope**

* External agent creation or dependency installation logic (handled by parent process)
* Test selection and prioritization (provided as CLI arg)
* Continuous integration, deployment, or multi-user orchestration
* Runtime telemetry dashboards or human-in-the-loop correction

---

## **8. Success Criteria**

✅ New test passes deterministically
✅ All baseline-passing tests remain green
✅ No unjustified test modifications
✅ JSON schema passes validation
✅ All results are reproducible by replaying emitted commands
✅ Controller never accepts unverifiable “success”

