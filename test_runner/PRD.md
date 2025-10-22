# **Product Requirements Document: AI Test Runner System**

**Document Version:** 1.0
**Owner:** Engineering / AI Platform Team
**Date:** 2025-10-22

---

## **1. Overview**

### **1.1 Summary**

The AI Test Runner System automates the process of running, diagnosing, and completing a test suite for a given feature or codebase using Claude Code SDK–driven agents.
Its primary function is to ensure that all tests in a targeted portion of the codebase pass autonomously — or halt gracefully with actionable summaries if the implementation cannot complete successfully.

The system orchestrates multiple specialized agents in a closed feedback loop, coordinating test execution, code modification, and analysis until test completion or escalation criteria are reached.

---

## **2. Goals and Success Criteria**

### **2.1 Goals**

* Automate the completion of a code feature’s test suite using an AI-driven iterative process.
* Generate reproducible, environment-aware shell scripts for running tests.
* Automatically summarize test failures, retry implementation improvements, and compact context when necessary.
* Provide deterministic exit codes and structured JSON output for integration with CI/CD pipelines.
* Maintain resumable sessions across runs for long-lived feature completion tasks.

### **2.2 Success Criteria**

* ✅ All tests in the scoped feature pass automatically.
* ✅ All runs produce structured JSON results with test statistics.
* ✅ Failed implementations produce rich, actionable summaries.
* ✅ System halts gracefully after defined retry limits.
* ✅ Entire loop can be resumed with preserved state.

---

## **3. Key Use Case**

Given a codebase and a subset of feature tests:

1. The **Test Tasker** agent identifies the environment and composes a shell command to run those tests.
2. A **Prompt Writer** generates a Claude Code prompt to invoke an **Implementer** agent with the necessary tools and context.
3. The **Implementer** modifies the codebase to fix failing tests.
4. The system re-runs the test suite to validate progress.
5. If failures persist, the **Summarizer** agent analyzes results and informs another Implementer iteration.
6. The **Orchestrator** governs this loop until all tests pass or termination conditions are met.

---

## **4. Agent Architecture**

### **4.1 Agent Overview**

| Agent             | Role                                                                                            | Inputs                           | Outputs                                        |
| ----------------- | ----------------------------------------------------------------------------------------------- | -------------------------------- | ---------------------------------------------- |
| **Test Tasker**   | Identify environment, generate test command, produce run script and JSON metadata.              | Feature scope, codebase path     | `test_config.json` and executable shell script |
| **Prompt Writer** | Create Implementer prompt from feature docs, config, and test results.                          | `test_config.json`, feature docs | `implementer_prompt.json`                      |
| **Implementer**   | Execute code modifications via Claude Code SDK environment (with tools, MCP servers, etc.).     | Prompt + environment config      | Updated code + `implementer_status.json`       |
| **Summarizer**    | Parse test output, summarize failure reasons and examples.                                      | Test output logs                 | `summary.json`                                 |
| **Orchestrator**  | Manage the overall test/fix/retry loop, handle session persistence, compaction, and exit codes. | All agent outputs                | Final session report and exit code             |

---

## **5. System Components**

### **5.1 Orchestrator**

* Manages agent lifecycles and session state.
* Triggers agents in sequence: Tasker → Writer → Implementer → Summarizer → (loop).
* Maintains retry counters, progress metrics, and compacted context.
* Responsible for deterministic exit codes and JSON summary output.

### **5.2 Persistent Context Store**

* Stores all intermediate JSON outputs and logs.
* Allows resumption of partial sessions.
* Records:

  * `session_id`
  * Test stats (`total`, `failed`)
  * Implementer attempts and summaries
  * Compact context versions (when 60% threshold reached)

### **5.3 Execution Sandbox**

* Controlled runtime environment for test execution.
* Ensures:

  * Reproducible environment setup (venv, Docker, etc.)
  * Safe command execution (no arbitrary system access)
  * Capture of stdout, stderr, and exit codes.

### **5.4 Claude Code SDK Integration**

Agents are invoked and managed via the Claude Code SDK interface:

Conceptually:

* `create_agent_session()` – new Implementer or Summarizer session.
* `attach_tools()` – load MCP servers, skills, or commands.
* `run_prompt()` – execute a single agent action.
* `resume_session()` – restore compacted Implementer session.
* `stream_output()` – capture test runner output for analysis.

*(Implementation details are left to engineering.)*

---

## **6. Data and Interface Contracts**

### **6.1 Test Runner Script Contract**

* Must `exit 0` if all tests pass.
* Must `exit 1` if any tests fail.
* Must produce a JSON output, e.g.:

```json
{
  "total": 127,
  "failed": 4,
  "details": ["test_login", "test_signup"],
  "summary_path": "output/summary.log"
}
```

### **6.2 Shared State Schema**

Common JSON schema passed between agents:

```json
{
  "session_id": "uuid",
  "feature": "feature_name",
  "state": {
    "total_tests": 127,
    "failing_tests": 4,
    "previous_attempts": 2,
    "context_utilization": 0.54,
    "summaries": [
      { "attempt": 1, "issues": ["missing validation", "wrong return type"] }
    ]
  },
  "next_action": "rerun_implementer"
}
```

### **6.3 Final Output Contract**

When the loop exits, output a final JSON report and exit code.

**Exit codes:**

| Code | Meaning                              |
| ---- | ------------------------------------ |
| `0`  | All tests passing                    |
| `1`  | Implementation incomplete            |
| `2`  | Agent stalled, human review required |
| `3`  | System or configuration error        |

**Final report:**

```json
{
  "session_id": "uuid",
  "result": "success",
  "total_tests": 127,
  "failing_tests": 0,
  "attempts": 4,
  "summaries": [...],
  "artifacts": ["path/to/output.json"]
}
```

---

## **7. Workflow**

### **7.1 Initialization**

* Orchestrator initializes session.
* Test Tasker inspects the project and outputs:

  * `test_config.json`
  * Test runner shell script.

### **7.2 Test Execution**

* Shell script is run; JSON results recorded.
* If all tests pass → success and exit.

### **7.3 Prompt Generation**

* Prompt Writer builds Implementer prompt with feature docs and config.

### **7.4 Implementation Cycle**

1. Implementer modifies codebase to fix failing tests.
2. Orchestrator reruns the test suite.
3. Summarizer analyzes remaining failures.
4. If failures persist, repeat.

### **7.5 Context Compaction**

* If context utilization > 60%, Summarizer produces a compressed historical summary and Orchestrator resumes session.

### **7.6 Retry and Termination Logic**

| Condition                                  | Action                                      |
| ------------------------------------------ | ------------------------------------------- |
| No reduction in failing tests for 3 cycles | Summarize and start new Implementer session |
| 3 sessions with no improvement             | Exit with code `2` (human review)           |
| Max attempts exceeded                      | Exit with failure                           |
| All tests pass                             | Exit with success                           |

---

## **8. Observability and Reporting**

* All agents must log JSONL lines with timestamp, agent name, and action.
* All artifacts (outputs, logs, summaries) stored under a session directory:

  * `/sessions/<session_id>/artifacts/`
* Metrics (attempts, pass/fail delta, test completion rate) tracked for future analytics.

---

## **9. Constraints and Assumptions**

* Claude Code SDK provides all session management and tool-loading APIs.
* Each agent is deterministic given the same input JSON.
* Execution environment supports shell scripts and JSON file I/O.
* Agents do not directly modify orchestration state except via defined output contracts.

---

## **10. Risks and Mitigations**

| Risk                         | Description                           | Mitigation                                   |
| ---------------------------- | ------------------------------------- | -------------------------------------------- |
| Infinite improvement loop    | Agent keeps retrying without progress | Termination threshold + session reset policy |
| Context overflow             | Model context grows too large         | Automatic compaction above 60% usage         |
| Unclear test failures        | Summarizer produces vague summaries   | Structured failure examples and test logs    |
| Partial environment mismatch | Local vs container differences        | Enforce standardized sandbox execution       |

---

## **11. Deliverables**

* **AI Test Runner Specification**

  * Orchestrator state schema
  * Agent prompt format specs
* **Shell Script Template**

  * Conforming to JSON+exit code contract
* **Session Schema**

  * Resumable session JSON
* **Sample Logs and Reports**

  * Example success/failure outputs

---

## **12. Future Enhancements**

* Multi-feature parallelization.
* Automatic documentation updates post-implementation.
* Integration with CI/CD to trigger on pull requests.
* Scoring mechanism for agent performance across features.


