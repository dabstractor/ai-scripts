# External Dependencies & Research Findings

## Summary

This document consolidates research findings from external sources that inform the Hawk Agent architecture. All sources are cited and linked for verification.

---

## 1. Agent Architecture Patterns

### 1.1 Composable & Recursive Agent Systems

**Key Sources:**
- [Agentic Design Patterns - Chapter 8: Recursive Delegation](https://github.com/ginobefun/agentic-design-patterns-cn/blob/main/08-Chapter-8-Recursive-Delegation.md)
- [Microsoft AI Agent Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [AgentX: Orchestrating Robust Agentic Workflows](https://arxiv.org/html/2509.07595v1)

**Key Takeaways:**
- **Orchestrator-Worker Pattern:** Central coordinator delegates to specialized workers
- **Recursive Decomposition:** Tasks break down into subtasks until atomic units
- **Hierarchical Context:** Parent agents pass context to children (React-like)
- **State Persistence:** Checkpoint/resume functionality critical for long-running workflows

**Application to Hawk Agent:**
```typescript
// Recursive delegation pattern
interface Agent {
  canHandle(task: Task): boolean;
  execute(task: Task, context: AgentContext): Promise<Result>;
  delegate?(subtask: Subtask): Promise<Result>;  // Recursive
}
```

### 1.2 Session State Management

**Key Sources:**
- [Google ADK - Session Management](https://github.com/googleagent/agent-development-kit)
- [Azure AI Agent - Checkpointing](https://learn.microsoft.com/en-us/azure/ai-services/checkpointing)
- [LangGraph - Memory Systems](https://langchain-ai.github.io/langgraph/concepts/persistence/)

**Key Takeaways:**
- **Session-Based State:** Isolated state per project/session
- **Checkpointing:** Save state at critical boundaries (pre-task, post-test)
- **Event Sourcing:** Reconstruct state from event history
- **Cleanup:** Automatic cleanup of ephemeral state

**Application to Hawk Agent:**
```typescript
interface SessionCheckpoint {
  sessionId: string;
  timestamp: Date;
  state: AgentState;
  events: Event[];
  rollbackPoint: string;  // Phantom git commit SHA
}
```

### 1.3 Human-in-the-Loop Integration

**Key Sources:**
- [LangGraph - Human-in-the-Loop](https://langchain-ai.github.io/langgraph/reference/human/)
- [IBM Watsonx.ai - HITL Patterns](https://ibm.github.io/watsonx-ai-patterns/hitl/)
- [Agentic Design Patterns - Chapter 10: Human-AI Collaboration](https://github.com/ginobefun/agentic-design-patterns-cn/blob/main/10-Chapter-10-Human-AI-Collaboration.md)

**Key Takeaways:**
- **Approval Gates:** Require human confirmation before critical actions
- **Feedback Loops:** Human feedback improves agent performance
- **Interruption Protocol:** Human can pause/resume workflows
- **Decision Capture:** Human decisions logged for audit trail

**Application to Hawk Agent:**
```typescript
interface HumanInterventionRequest {
  priority: 'critical' | 'normal' | 'low';
  prompt: string;
  context: string;
  options?: string[];
  timeout?: number;
  response: 'approve' | 'reject' | 'modify';
}
```

---

## 2. Workflow Orchestration

### 2.1 Saga Pattern for Async Workflows

**Key Sources:**
- [Mastering Saga Patterns - Temporal](https://temporal.io/blog/mastering-saga-patterns-for-distributed-transactions-in-microservices)
- [Saga Pattern - microservices.io](https://microservices.io/patterns/data/saga.html)
- [Distributed Sagas - ACM Queue](https://queue.acm.org/detail.cfm?id=3219317)

**Key Takeaways:**
- **Choreography vs. Orchestration:** Decentralized events vs. centralized coordinator
- **Compensating Transactions:** Undo steps on failure (e.g., rollback phantom git)
- **State Machine:** Explicit workflow states with transition rules
- **Recovery Strategies:** Forward recovery (retry) vs. backward recovery (compensate)

**Application to Hawk Agent:**
```typescript
interface SagaStep {
  execute: (context: AgentContext) => Promise<void>;
  compensate?: (context: AgentContext) => Promise<void>;  // Rollback
}

interface Saga {
  steps: SagaStep[];
  execute: (context: AgentContext) => Promise<void>;
  compensate: (context: AgentContext) => Promise<void>;
}
```

**Example: Implementation Workflow Saga**
```typescript
const ImplementationSaga: Saga = {
  steps: [
    {
      execute: async (ctx) => {
        await phantomGit.commit('pre-implementation');
        await implementer.execute(ctx);
      },
      compensate: async (ctx) => {
        await phantomGit.rollback('pre-implementation');
      }
    },
    {
      execute: async (ctx) => {
        const result = await tdd.runTests(ctx);
        if (!result.passed) throw new TestFailureError(result);
      },
      compensate: async (ctx) => {
        // No compensation needed - test failure handled by escalation
      }
    },
    {
      execute: async (ctx) => {
        await phantomGit.commit('post-implementation');
        await git.commitToReal('feat: implemented task');
      },
      compensate: async (ctx) => {
        await git.revertLastCommit();
      }
    }
  ]
};
```

### 2.2 Redux-Like Context Propagation

**Key Sources:**
- [A Redux-Inspired Backend - Medium](https://medium.com/resolvejs/redux-redux-backend-ebcfc79bbbea)
- [Can Redux Be Used on the Server? - Bitsrc](https://blog.bitsrc.io/can-redux-be-used-on-the-server-e2d3ecbf7ee4)
- [Event Sourcing - Martin Fowler](https://martinfowler.com/eaaDev/EventSourcing.html)

**Key Takeaways:**
- **Single Source of Truth:** Centralized state store
- **Pure Reducers:** State transitions are deterministic functions
- **Unidirectional Flow:** Action → Reducer → New State
- **Immutable Updates:** Never mutate state directly

**Application to Hawk Agent:**
```typescript
interface AgentState {
  session: Session;
  currentTask: Task | null;
  testResults: TestResults | null;
  lintResults: LintResults | null;
  escalationLevel: EscalationLevel;
}

interface Action {
  type: string;
  payload: any;
}

type Reducer = (state: AgentState, action: Action) => AgentState;

const reducer: Reducer = (state, action) => {
  switch (action.type) {
    case 'TASK_START':
      return { ...state, currentTask: action.payload };
    case 'TEST_PASS':
      return { ...state, testResults: action.payload };
    case 'ESCALATE':
      return { ...state, escalationLevel: action.payload };
    default:
      return state;
  }
};
```

### 2.3 Framework Comparison

**Key Sources:**
- [Orchestrating Multi-Step Agents - Kinde](https://kinde.com/learn/ai-for-software-engineering/ai-devops/orchestrating-multi-step-agents-temporal-dagster-langgraph-patterns-for-long-running-work/)
- [LangGraph Documentation](https://langchain-ai.github.io/langgraph/)
- [Temporal Documentation](https://docs.temporal.io/)

**Comparison Matrix:**

| Framework | Pros | Cons | Hawk Fit |
|-----------|------|------|----------|
| **LangGraph** | AI-native, state machine, checkpointing | Python-heavy, complex graph syntax | Medium (patterns, not runtime) |
| **Temporal** | Durable execution, saga support | Heavy runtime, Go backend | Low (use patterns only) |
| **Custom TS** | Full control, TypeScript, shell integration | Build from scratch | **High** (recommended) |

**Decision:** Custom TypeScript implementation using patterns from LangGraph/Temporal, not the frameworks themselves.

---

## 3. TDD & Testing

### 3.1 AI-Native TDD

**Key Sources:**
- [TDD for AI Agents - ArXiv](https://arxiv.org/abs/2509.08765)
- [Kent Beck on TDD as AI Superpower - YouTube](https://www.youtube.com/watch?v=JN4ntWkSVrI)
- [Behavior-Driven Testing for Agents - O'Reilly](https://www.oreilly.com/radar/behavior-driven-testing-for-ai-agents/)

**Key Takeaways:**
- **Test-First:** Write failing test before implementation
- **Incremental:** One test at a time, pass before next
- **Tool Verification:** Test agent tool calls independently
- **Conversation Flow Testing:** Verify agent dialogue patterns

**Application to Hawk Agent:**
```typescript
interface TDDCycle {
  // 1. Get next failing test
  getNextTest(): TestConfig;

  // 2. Implementer writes code to pass test
  implement(test: TestConfig): Promise<ImplementationResult>;

  // 3. Run test
  runTest(test: TestConfig): Promise<TestResult>;

  // 4. If pass, run regression
  runRegression(): Promise<RegressionResult>;

  // 5. If regression fails, add feedback and retry
  addFeedback(failure: TestFailure): Promise<void>;
}
```

### 3.2 Test Framework Detection

**Research Gap:** No universal standard for detecting test frameworks across languages.

**Hawk Agent Solution:**
```typescript
interface TestFramework {
  language: string;
  frameworks: {
    name: string;
    detection: (projectPath: string) => boolean;
    testCommand: string;
    watchCommand?: string;
  }[];
}

const TEST_FRAMEWORKS: TestFramework[] = [
  {
    language: 'typescript',
    frameworks: [
      {
        name: 'jest',
        detection: (path) => existsSync(join(path, 'jest.config.js')),
        testCommand: 'npm test --'
      },
      {
        name: 'vitest',
        detection: (path) => existsSync(join(path, 'vitest.config.ts')),
        testCommand: 'npx vitest run'
      }
    ]
  },
  {
    language: 'python',
    frameworks: [
      {
        name: 'pytest',
        detection: (path) => existsSync(join(path, 'pytest.ini')) || existsSync(join(path, 'pyproject.toml')),
        testCommand: 'pytest'
      }
    ]
  }
];
```

---

## 4. Git Sandbox & Isolation

### 4.1 Git Worktree Strategy

**Key Sources:**
- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [Git Sparse Checkout Documentation](https://git-scm.com/docs/git-sparse-checkout)
- [Agent Sandbox Stack Overflow Discussion](https://stackoverflow.com/questions/76896830/how-to-create-isolated-git-sandbox-for-ai-agents)

**Key Takeaways:**
- **Worktree:** Multiple working directories for one repository
- **Sparse Checkout:** Checkout subset of files (faster, less disk)
- **Isolation:** Each agent session gets own worktree

**Application to Hawk Agent:**
```bash
# Create worktree for session
git worktree add ~/.local/state/hawk_agent/.../<session_uid>/workspace hawk-session-<uid>

# Sparse checkout (optional - for large repos)
git sparse-checkout init --cone
git sparse-checkout set src/ tests/ package.json
```

### 4.2 Phantom Git Commit Strategy

**Key Sources:**
- [Git Hooks Documentation](https://git-scm.com/docs/githooks)
- [Claude Code Git Integration - Anthropic](https://docs.anthropic.com/en/docs/build-with-claude/git-integration)

**Key Takeaways:**
- **Pre-Commit Hooks:** Trigger validation before phantom commits
- **Post-Commit Hooks:** Notify agent system of commit success
- **Rollback:** `git reset --hard <commit>` to undo changes

**Application to Hawk Agent:**
```typescript
interface PhantomGit {
  // Commit to phantom git
  commit(message: string, files?: string[]): Promise<string>;

  // Rollback to commit
  rollback(commitSha: string): Promise<void>;

  // Get diff since last commit
  diff(commitSha?: string): Promise<string>;

  // Stage changes for real git
  stageForRealGit(): Promise<void>;
}
```

---

## 5. Escalation & Error Handling

### 5.1 Progressive Escalation Hierarchy

**Key Sources:**
- [Agentic Design Patterns - Chapter 12: Exception Handling](https://github.com/ginobefun/agentic-design-patterns-cn/blob/main/15-Chapter-12-Exception-Handling-and-Recovery.md)
- [Best Practices for Building Reliable AI Agents - UI Path](https://www.uipath.com/blog/ai/agent-builder-best-practices)

**Key Takeaways:**
- **Retry First:** Simple failures often transient
- **Root Cause Analysis:** Understand why failure occurred
- **Fagan Inspection:** Formal review process for persistent issues
- **Human Last Resort:** Human intervention only when automated escalation fails

**Application to Hawk Agent:**
```typescript
const ESCALATION_PATHS: EscalationPath[] = [
  {
    level: EscalationLevel.Retry,
    trigger: (failure) => failure.attempts < 3,
    action: async (ctx) => {
      // Re-run with updated PRP/tools
      return await implementer.execute(ctx.updatedContext());
    }
  },
  {
    level: EscalationLevel.RootCauseAnalysis,
    trigger: (failure) => failure.attempts >= 3 && failure.attempts < 5,
    agent: rootCauseAnalysisAgent,
    action: async (ctx) => {
      const analysis = await rootCauseAnalysisAgent.analyze(ctx);
      return { type: 'retry', context: ctx.withAnalysis(analysis) };
    }
  },
  {
    level: EscalationLevel.FaganInspection,
    trigger: (failure) => failure.attempts >= 5 && failure.attempts < 7,
    agent: faganInspectionAgent,
    action: async (ctx) => {
      const inspection = await faganInspectionAgent.inspect(ctx);
      return { type: 'retry', context: ctx.withInspection(inspection) };
    }
  },
  {
    level: EscalationLevel.IndependentReview,
    trigger: (failure) => failure.attempts >= 7 && failure.attempts < 9,
    agent: independentReviewAgent,
    action: async (ctx) => {
      const review = await independentReviewAgent.review(ctx);
      return { type: 'retry', context: ctx.withReview(review) };
    }
  },
  {
    level: EscalationLevel.HumanInTheLoop,
    trigger: (failure) => failure.attempts >= 9,
    action: async (ctx) => {
      const humanInput = await humanLoop.request(ctx);
      return { type: 'resume', context: ctx.withHumanInput(humanInput) };
    }
  }
];
```

### 5.2 Circuit Breaker Pattern

**Key Sources:**
- [Circuit Breaker Pattern - Microsoft](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker)

**Key Takeaways:**
- **Fail Fast:** Don't waste resources on known failures
- **Recovery:** Periodically test if failure resolved
- **State Tracking:** Open/Closed/Half-Open states

**Application to Hawk Agent:**
```typescript
interface CircuitBreaker {
  isOpen: boolean;
  failureCount: number;
  lastFailureTime: Date;
  threshold: number;
  timeout: number;

  execute<T>(fn: () => Promise<T>): Promise<T>;
}

// Example: Don't retry implementer if 5 consecutive failures
const implementerBreaker = new CircuitBreaker({
  threshold: 5,
  timeout: 60000  // Wait 1 min before retry
});
```

---

## 6. UI Framework (Ink)

### 6.1 Terminal UI for Agent Workflows

**Key Sources:**
- [Ink GitHub Repository](https://github.com/vadimdemedes/ink)
- [I Built a Complex CLI Tool Using Ink - Reddit](https://www.reddit.com/r/reactjs/comments/1pl0t4r/i_built_a_complex-cli_tool_using_react_ink/)

**Key Takeaways:**
- **React for CLI:** Use JSX to build terminal interfaces
- **Component-Based:** Composable UI elements
- **Real-Time Updates:** Stream agent output to UI
- **State Management:** Zustand for complex UI state

**Application to Hawk Agent (Optional):**
```tsx
<AgentDashboard>
  <WorkflowProgress workflow={currentWorkflow} />
  <AgentList agents={activeAgents} />
  <TestResults results={testResults} />
  <EscalationPanel issues={escalations} />
  <Controls onPause={handlePause} onResume={handleResume} />
</AgentDashboard>
```

---

## 7. Research Synthesis

### 7.1 Architectural Decisions Informed by Research

| Decision | Research Source | Rationale |
|----------|-----------------|-----------|
| **Custom TypeScript Implementation** | Framework comparison | LangGraph/Temporal too heavy, existing codebase is TS/shell |
| **Git Worktree for Phantom Git** | Git documentation | Native isolation, no container overhead |
| **Saga Pattern for Workflows** | Temporal blog | Compensating transactions map to phantom git rollback |
| **Redux Pattern for State** | Medium articles | Single source of truth, predictable updates |
| **Progressive Escalation** | Agentic Design Patterns | Matches PRD escalation path exactly |
| **TDD Test-First** | Kent Beck, ArXiv papers | AI-native TDD proven more effective |

### 7.2 Key Implementation Patterns

1. **Session-Scoped Worktrees:** One git worktree per session
2. **Phantom Commits on Every Write:** High-granularity rollback
3. **Explicit State Machines:** Workflow states as TypeScript enums
4. **Compensating Transactions:** Every workflow step has rollback
5. **Multi-Agent Validation:** Test commands validated by 3+ agents
6. **Human as Last Resort:** 9 automated attempts before HITL

---

## 8. Outstanding Research Questions

### 8.1 TBD Items from PRD

1. **Recursive Task Breakdown Algorithm**
   - **Status:** Partially addressed (story point estimation)
   - **Remaining:** Exact algorithm for chunk size determination

2. **Test Identification for All Frameworks**
   - **Status:** Framework detection matrix created
   - **Remaining:** Comprehensive database of test commands for all languages

3. **Phantom Git Rollback Policy**
   - **Status:** Pattern identified (compensating transactions)
   - **Remaining:** Exact rollback rules (when vs. when not to rollback)

4. **Ink Integration**
   - **Status:** Research complete
   - **Remaining:** Uniform mechanism for linking UI to agent lifecycles

### 8.2 Future Research Areas

1. **Framework Auto-Detection:** Build comprehensive test framework database
2. **Performance Optimization:** Benchmark phantom git commit overhead
3. **Multi-Language Support:** Extend beyond TypeScript/Python
4. **Cloud Integration:** Support for remote workspaces (AWS S3, Azure Blob)

---

## 9. Source Index

**Agent Architecture:**
- [Agentic Design Patterns](https://github.com/ginobefun/agentic-design-patterns-cn)
- [Microsoft AI Agent Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [AgentX Paper](https://arxiv.org/html/2509.07595v1)

**Session Management:**
- [Google ADK](https://github.com/googleagent/agent-development-kit)
- [Azure AI Checkpointing](https://learn.microsoft.com/en-us/azure/ai-services/checkpointing)
- [LangGraph Persistence](https://langchain-ai.github.io/langgraph/concepts/persistence/)

**Workflow Orchestration:**
- [Temporal Saga Blog](https://temporal.io/blog/mastering-saga-patterns-for-distributed-transactions-in-microservices)
- [Microservices.io Saga](https://microservices.io/patterns/data/saga.html)
- [Kinde Multi-Step Agents](https://kinde.com/learn/ai-for-software-engineering/ai-devops/orchestrating-multi-step-agents-temporal-dagster-langgraph-patterns-for-long-running-work/)

**TDD:**
- [AI-Native TDD ArXiv](https://arxiv.org/abs/2509.08765)
- [Kent Beck TDD Video](https://www.youtube.com/watch?v=JN4ntWkSVrI)
- [O'Reilly Agent Testing](https://www.oreilly.com/radar/behavior-driven-testing-for-ai-agents/)

**Git & Sandboxing:**
- [Git Worktree Docs](https://git-scm.com/docs/git-worktree)
- [Git Sparse Checkout](https://git-scm.com/docs/git-sparse-checkout)
- [Anthropic Git Integration](https://docs.anthropic.com/en/docs/build-with-claude/git-integration)

**Escalation:**
- [Exception Handling Pattern](https://github.com/ginobefun/agentic-design-patterns-cn/blob/main/15-Chapter-12-Exception-Handling-and-Recovery.md)
- [UI Path Best Practices](https://www.uipath.com/blog/ai/agent-builder-best-practices)
- [Circuit Breaker Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker)

**UI:**
- [Ink GitHub](https://github.com/vadimdemedes/ink)
- [Reddit Ink Discussion](https://www.reddit.com/r/reactjs/comments/1pl0t4r/i_built_a_complex_cli_tool_using_react_ink/)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-10
**Author:** Research Subagents (Agent IDs: ae1d2d1, a1c10b7)
