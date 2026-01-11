# System Context: Hawk Agent Architecture

## Executive Summary

**Hawk Agent** is a green-field implementation - a complete agent orchestration system that does not currently exist in the codebase. This document establishes the architectural context, existing capabilities, and implementation roadmap.

---

## 1. Current State Assessment

### 1.1 Existing Infrastructure (Foundation)

**Location:** `/home/dustin/projects/ai-scripts/prd_pipeline/`

**What We Have:**
- ✅ **PRP Pipeline:** Shell-based orchestration of 11+ agent types (`run-prd.sh`)
- ✅ **Task Management:** TypeScript CLI (`tsk`) with hierarchical task tracking
- ✅ **Task Hierarchy:** Phase → Milestone → Task → Subtask structure
- ✅ **Auto-Resume:** Graceful shutdown handling and task recovery
- ✅ **Git Integration:** Standard git commits with smart staging
- ✅ **Research Support:** Parallel research capability
- ✅ **Agent Prompts:** PRP creation/execution templates

**Languages & Frameworks:**
- Shell Script (Zsh): Orchestration logic
- TypeScript (5.9.3): Task utilities
- Node.js (CommonJS): Runtime environment

**Key Dependencies:**
- `zod@4.1.12` - Schema validation
- `commander@14.0.2` - CLI framework
- `chalk@5.6.2` - Terminal colors
- `cli-progress@3.12.0` - Progress bars

### 1.2 What Hawk Agent Will Build (Green Field)

**Missing Components:**
- ❌ Session management system
- ❌ Phantom git (sandbox repository)
- ❌ Three pillars detection (testing, logging, linting)
- ❌ Workflow composition engine (React-like)
- ❌ TDD orchestration
- ❌ Human-in-the-loop integration
- ❌ Centralized logging system
- ❌ Escalation paths
- ❌ Context propagation (props/callbacks)
- ❌ Saga-style async workflows

**Conclusion:** Hawk Agent is a **major new subsystem** that will extend the existing PRD pipeline, not a refactoring of current code.

---

## 2. Architecture Decisions

### 2.1 Framework Selection

**Decision: Custom Implementation with Pattern Adoption**

**Rationale:**
- Existing codebase is shell + TypeScript (maintain consistency)
- No Python in current project (avoid Python dependency)
- LangGraph/Temporal would introduce heavy runtime dependencies
- PRD explicitly mentions "React/Redux-like" patterns (use patterns, not frameworks)

**Chosen Stack:**
- **Core Engine:** TypeScript + Node.js
- **Workflow Composition:** Custom React-like component system
- **State Management:** Redux-pattern (explicit state, reducers, selectors)
- **Orchestration:** Saga-pattern for async workflows
- **Sandboxing:** Git worktree + sparse checkout
- **UI (Optional):** Ink for terminal dashboard

### 2.2 Project Structure

```
hawk-agent/
├── src/
│   ├── core/
│   │   ├── session.ts        # Session lifecycle & UID generation
│   │   ├── workflow.ts       # Workflow composition engine
│   │   ├── context.ts        # Props/callbacks propagation
│   │   └── agent.ts          # Base agent class
│   │
│   ├── git/
│   │   ├── phantom-git.ts    # Phantom git operations
│   │   ├── sandbox.ts        # Git worktree management
│   │   └── commit-hooks.ts   # Claude hook integration
│   │
│   ├── pillars/
│   │   ├── detector.ts       # Three pillars detection
│   │   ├── testing.ts        # Test framework detection
│   │   ├── logging.ts        # Logging system analysis
│   │   └── linting.ts        # Lint configuration detection
│   │
│   ├── tdd/
│   │   ├── overseer.ts       # TDD orchestration
│   │   ├── test-runner.ts    # Test command validation
│   │   └── regression.ts     # Regression test management
│   │
│   ├── escalation/
│   │   ├── root-cause.ts     # Root Cause Analysis agent
│   │   ├── fagan.ts          # Fagan Inspection agent
│   │   ├── review.ts         # Independent Review agent
│   │   └── human-loop.ts     # Human-in-the-loop protocol
│   │
│   ├── logging/
│   │   ├── logger.ts         # Centralized logging
│   │   ├── levels.ts         # HawkAgent log level
│   │   └── audit.ts          # Audit trail
│   │
│   ├── workflows/
│   │   ├── init.ts           # Init workflow (hawk init)
│   │   ├── prd-creation.ts   # PRD creation workflow
│   │   ├── prd-breakdown.ts  # PRD breakdown workflow
│   │   └── implementation.ts # Task implementation flow
│   │
│   └── utils/
│       ├── path.ts           # Path resolution
│       ├── fs.ts             # File system operations
│       └── cli.ts            # CLI interactions
│
├── templates/
│   ├── workflows/            # Workflow templates
│   └── prompts/              # Agent prompts (reuse existing)
│
├── bin/
│   └── hawk                  # Main CLI entry point
│
├── package.json
├── tsconfig.json
└── README.md
```

### 2.3 Integration with Existing PRD Pipeline

**Strategy:** Coexistence, Not Replacement

```
┌─────────────────────────────────────────────────────────────┐
│                    Existing PRD Pipeline                     │
│  (run-prd.sh, tsk CLI, PRP system, task hierarchy)          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Hawk Agent Layer                          │
│  (Sessions, Phantom Git, Workflows, TDD, HITL)               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Enhanced Pipeline                         │
│  (PRD → Hawk Session → PRP Breakdown → Hawk Implementation) │
└─────────────────────────────────────────────────────────────┘
```

**Integration Points:**
1. `hawk init` → Generates/enhances `tasks.json` (uses `tsk` format)
2. `hawk implement` → Wraps existing PRP execution with TDD
3. Phantom git commits → Feed into real git commits
4. Session logs → Complement existing console output

---

## 3. Key Architectural Patterns

### 3.1 Session Management Pattern

**Research Sources:**
- Google ADK session state patterns
- Azure AI Agent checkpointing
- LangGraph memory systems

**Implementation:**
```typescript
interface Session {
  uid: string;                    // UUID
  projectPath: string;            // Absolute path to project
  sessionDir: string;             // ~/.local/state/hawk_agent/.../<uid>/
  startTime: Date;
  status: 'active' | 'paused' | 'completed' | 'failed';
  ephemeralState: Record<string, any>;
  phantomGitDir: string;          // Path to phantom .git
}
```

**Session Directory Layout:**
```
~/.local/state/hawk_agent/<absolute_project_path>/<session_uid>/
├── .git/                    # Phantom git repository
├── session.json             # Session metadata
├── ephemeral-state.json     # Agent state (props, context)
├── research/                # PRP research artifacts
├── logs/                    # Session logs
└── temp/                    # Temporary files (cleanup on success)
```

### 3.2 Phantom Git Pattern

**Research Sources:**
- Git worktree documentation
- Agent sandboxing best practices
- Stack Overflow patterns for git isolation

**Implementation Strategy:**
```bash
# Create worktree for session
git worktree add ~/.local/state/hawk_agent/.../<session_uid>/workspace <branch>

# Phantom git operations (in session directory)
cd ~/.local/state/hawk_agent/.../<session_uid>/workspace
git add .
git commit -m "phantom: <operation>"
```

**Integration with Claude Hooks:**
- Phantom commits trigger Claude's pre-commit hooks
- Real git commits only after validation passes
- Rollback capability via `git reset --hard <phantom-commit>`

### 3.3 Workflow Composition Pattern (React-Like)

**Research Sources:**
- Agentic Design Patterns (Chapter 8: Recursive Delegation)
- LangGraph graph-based workflows
- React component composition principles

**Implementation:**
```typescript
interface Workflow {
  id: string;
  render: (props: WorkflowProps) => WorkflowResult;
}

type WorkflowResult =
  | { type: 'sync'; value: any }                    // Synchronous action
  | { type: 'async'; process: ChildProcess }        // Async workflow spawn
  | { type: 'agent'; agent: Agent }                 // Render child agent
  | { type: 'human'; prompt: string }               // Request human input
  | { type: 'done' };                               // Workflow complete
```

**Example: Init Workflow**
```typescript
const InitWorkflow: Workflow = {
  id: 'init',
  render: async (props) => {
    // Step 1: Create session directory
    await CreateSessionWorkflow.render({ ...props });

    // Step 2: Detect pillars
    const pillars = await DetectPillarsWorkflow.render({ ...props });

    // Step 3: Scaffold if needed
    if (pillars.missing.length > 0) {
      await PromptUserWorkflow.render({
        question: `Scaffold missing pillars: ${pillars.missing.join(', ')}?`
      });
    }

    return { type: 'done' };
  }
};
```

### 3.4 Context Propagation Pattern (Redux-Like)

**Research Sources:**
- Redux pattern fundamentals (Medium article)
- Event sourcing principles (Martin Fowler)
- React context API documentation

**Implementation:**
```typescript
interface AgentContext {
  session: Session;
  props: Record<string, any>;
  callbacks: {
    onProgress?: (update: ProgressUpdate) => void;
    onHumanInput?: (prompt: string) => Promise<string>;
    onEscalate?: (issue: EscalationIssue) => void;
  };
  state: {
    currentTask?: Task;
    testResults?: TestResults;
    lintResults?: LintResults;
  };
}

// Context propagation (parent → child)
const childContext: AgentContext = {
  ...parentContext,
  props: {
    ...parentContext.props,
    taskSpecificData: 'value'
  }
};
```

### 3.5 TDD Orchestration Pattern

**Research Sources:**
- AI-native TDD patterns (ArXiv paper)
- Kent Beck on TDD as AI "superpower"
- Behavior-driven testing for agents

**Implementation:**
```typescript
interface TDDOverseer {
  // Test command validation (multi-agent)
  validateTestCommands(): Promise<TestCommands>;

  // Run next test
  runNextTest(): Promise<TestResult>;

  // Run regression suite
  runRegressionTests(): Promise<RegressionResult>;

  // Modify test (on failure)
  modifyTest(testPath: string, feedback: string): Promise<void>;
}
```

**TDD Loop (from PRD):**
```
TestTasker → PromptWriter → Implementer → RunNext
     ↑                                      ↓
     └────── Passed? ──→ RunReg ──→ RegPass? ─┘
              ↓ No                      ↓ Yes
         RePrompt ←────────────────── Commit
```

### 3.6 Escalation Pattern

**Research Sources:**
- Agentic Design Patterns (Chapter 12: Exception Handling)
- 5-level escalation hierarchy (UI Path blog)
- Circuit breaker patterns

**Implementation:**
```typescript
enum EscalationLevel {
  Retry = 1,                    // Re-run with updated tools/PRP
  RootCauseAnalysis = 2,        // RCA agent
  FaganInspection = 3,          // Fagan inspector
  IndependentReview = 4,        # External reviewer
  HumanInTheLoop = 5            // Human intervention
}

interface EscalationPath {
  level: EscalationLevel;
  trigger: (failure: Failure) => boolean;
  agent?: Agent;
  action: (context: AgentContext) => Promise<EscalationResult>;
}
```

---

## 4. Technology Stack Details

### 4.1 Core Dependencies

**New Dependencies Required:**
```json
{
  "dependencies": {
    "uuid": "^11.0.3",              // Session UID generation
    "winston": "^3.17.0",           // Logging
    "rxjs": "^7.8.1",               // Observable streams (sagas)
    "immer": "^10.1.1",             // Immutable state updates
    "execa": "^9.5.2",              // Process execution
    "chalk": "^5.6.2",              // Colors (existing)
    "inquirer": "^12.0.1"           // CLI prompts (upgrade from @types)
  },
  "devDependencies": {
    "@types/uuid": "^11.0.0",
    "@types/inquirer": "^9.0.9"     // Existing
  }
}
```

**Ink (Optional - for UI):**
```json
{
  "dependencies": {
    "ink": "^4.4.1",
    "react": "^18.3.1",
    "zustand": "^5.0.2"             // State management for UI
  }
}
```

### 4.2 TypeScript Configuration

**Target:** ES2022 (for async/await, top-level await)

**Module:** CommonJS (maintain compatibility with existing codebase)

**Strict Mode:** Enabled (critical for agent reliability)

---

## 5. Implementation Phases

Based on the PRD structure and complexity analysis, the implementation will follow this phased approach:

### Phase 1: Foundation (Session & Phantom Git)
- Session management system
- Phantom git infrastructure
- Basic logging

### Phase 2: Three Pillars
- Detection logic for testing, logging, linting
- Scaffolding capabilities
- Pillar validation

### Phase 3: Workflow Engine
- Workflow composition system
- Context propagation
- Basic workflow templates

### Phase 4: TDD Integration
- TDD overseer
- Test command validation
- TDD loop implementation

### Phase 5: Escalation & HITL
- Escalation path agents
- Human-in-the-loop protocol
- Error handling

### Phase 6: Integration
- Integration with existing PRD pipeline
- End-to-end workflows
- Polish & optimization

---

## 6. Risks & Mitigations

### 6.1 Complexity Risk

**Risk:** Workflow composition system may become overly complex.

**Mitigation:**
- Start with synchronous workflows only
- Add async workflows incrementally
- Extensive testing of composition patterns
- Clear documentation of workflow contracts

### 6.2 Git Performance Risk

**Risk:** Phantom git commits on every file write may be slow.

**Mitigation:**
- Batch commits where possible
- Use git worktree for isolation
- Benchmark commit performance
- Consider lazy commit strategy (commit on task boundaries)

### 6.3 State Synchronization Risk

**Risk:** Session state may become inconsistent across agents.

**Mitigation:**
- Single source of truth (session.json)
- Immutable state updates (immer)
- State validation on every access
- Comprehensive audit logging

### 6.4 Testing Gap Risk

**Risk:** TDD system may not detect all framework/language patterns.

**Mitigation:**
- Extensive framework detection matrix
- User-configurable test commands
- Fallback to manual test execution
- Community-driven framework database

---

## 7. Success Criteria

**Minimal Viable Hawk Agent:**
- ✅ Session creation and lifecycle management
- ✅ Phantom git with rollback capability
- ✅ Three pillars detection (at least 2/3)
- ✅ Init workflow fully functional
- ✅ One complete implementation workflow (PRD → commit)

**Complete Hawk Agent:**
- ✅ All three pillars detected and scaffolded
- ✅ Full TDD orchestration
- ✅ Escalation paths functional
- ✅ Human-in-the-loop working
- ✅ Ink-based terminal UI
- ✅ Full PRD pipeline integration

---

## 8. Next Steps

1. **Create tasks.json** with detailed breakdown (Phase → Milestone → Task → Subtask)
2. **Implement Phase 1** (Foundation) first
3. **Incrementally integrate** with existing PRD pipeline
4. **Test extensively** at each phase boundary

---

**Document Version:** 1.0
**Last Updated:** 2025-01-10
**Author:** Architecture Research Subagent (Agent ID: abc1ff0, ae1d2d1, a1c10b7)
