# Workflow Orchestration and Agent Systems Research Report

**Research Date:** January 10, 2026
**For:** Hawk Agent PRD - Workflow Composition Requirements
**Focus:** Practical implementations and architectural patterns for composable agent workflows

---

## Table of Contents

1. [Workflow Orchestration Patterns for Long-Running Agent Processes](#1-workflow-orchestration-patterns)
2. [Saga Pattern Implementations for Async Workflows](#2-saga-pattern-implementations)
3. [React/Redux-like Context Propagation in Non-UI Systems](#3-context-propagation-patterns)
4. [Tools and Frameworks for Composable Workflow Systems](#4-tools-and-frameworks)
5. [Escalation Paths and Error Handling Best Practices](#5-escalation-and-error-handling)
6. [Ink Framework Integration for Agent Lifecycles](#6-ink-framework-integration)
7. [Recommendations for Hawk Agent Implementation](#7-recommendations)

---

## 1. Workflow Orchestration Patterns for Long-Running Agent Processes

### Core Patterns Identified

#### 1.1 Sequential Orchestration
**Description:** Linear task progression where each agent completes its work before handing off to the next.

**Key Characteristics:**
- Simple to understand and debug
- Clear dependency chain
- Easy to track progress
- Minimal concurrency issues

**Use Cases:**
- PRD → Task Breakdown → Research → Implementation → Validation
- Agent pipelines where output of stage N is input to stage N+1
- Quality gates where each stage must pass before proceeding

**Implementation Considerations:**
- State persistence between stages is critical
- Checkpoint/restart capability for long-running workflows
- Timeouts and deadlock detection

**Sources:**
- [AI Agent Orchestration Patterns - Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [Agent Workflow Patterns: Essential Guide to AI Orchestration in 2025](https://www.fixtergeek.com/blog/Agent-Workflow-Patterns:-The-Essential-Guide-to-AI-Orchestration-in-2025_5BQ)

#### 1.2 Concurrent Execution
**Description:** Multiple agents work in parallel on independent tasks.

**Key Characteristics:**
- Faster completion for independent work
- Requires careful dependency analysis
- Resource management challenges
- Complex error handling

**Use Cases:**
- Parallel research on different topics
- Independent feature implementation
- Concurrent test execution

**Implementation Considerations:**
- Dependency graph analysis before execution
- Resource pooling and limits
- Coordination primitives (barriers, futures)
- Deterministic scheduling for reproducibility

**Sources:**
- [AWS Workflow Orchestration Agents](https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-patterns/workflow-orchestration-agents.html)
- [AgentX: Orchestrating Robust Agentic Workflows](https://arxiv.org/html/2509.07595v1)

#### 1.3 Group Chat Patterns
**Description:** Multiple agents collaborate dynamically, with agents able to interject and coordinate.

**Key Characteristics:**
- Emergent behavior through collaboration
- No fixed orchestration sequence
- Requires coordination protocols
- Complex state management

**Use Cases:**
- Architecture review panels (Security, DevOps, Backend, Frontend, QA)
- Brainstorming and ideation
- Multi-perspective problem solving

**Implementation Considerations:**
- Turn-taking protocols
- Consensus building mechanisms
- Moderator agent patterns
- Conversation history management

**Sources:**
- [AI Agent Orchestration Patterns - Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)

#### 1.4 Handoff Patterns
**Description:** Dynamic delegation between agents based on capabilities and current state.

**Key Characteristics:**
- Flexible routing based on agent expertise
- Requires agent capability registry
- Context preservation during handoffs
- Graceful degradation

**Use Cases:**
- Escalation from generalist to specialist agents
- Error recovery through agent rerouting
- Human-in-the-loop integration
- Dynamic agent selection

**Implementation Considerations:**
- Agent capability matching
- Context serialization/deserialization
- Handoff protocols and contracts
- Rollback capabilities

**Sources:**
- [AI Agent Orchestration Patterns - Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)

### 1.5 Orchestrator Pattern
**Description:** Central coordinator agent that manages workflow execution and agent lifecycle.

**Key Characteristics:**
- Single point of control
- Clear visibility into workflow state
- Simplified error handling
- Potential bottleneck

**Use Cases:**
- Complex multi-stage workflows
- PRP pipeline coordination
- TDD loop management
- Long-running process supervision

**Implementation Considerations:**
- State machine for orchestrator itself
- Event-driven architecture for scalability
- Persistent state for recovery
- Observability and debugging tools

**Sources:**
- [AgentX: Orchestrating Robust Agentic Workflows](https://arxiv.org/html/2509.07595v1)
- [Orchestrating Long-Running Processes with LangGraph](https://www.auxiliobits.com/blog/orchestrating-long-running-processes-using-langgraph-agents/)

### State Management for Long-Running Processes

#### Durable Execution
**Concept:** Ability to pause, persist, and resume workflows without losing state or progress.

**Key Requirements:**
- State snapshotting at workflow boundaries
- Deterministic workflow execution
- Event sourcing for state reconstruction
- Time-travel debugging

**Implementation Approaches:**
1. **Checkpoint-based:** Save state at predetermined points
2. **Event-sourced:** Replay events to reconstruct state
3. **Hybrid:** Combine checkpoints with event logs

**Sources:**
- [Temporal Workflow Orchestration Patterns](https://mcpmarket.com/zh/tools/skills/temporal-workflow-orchestration-patterns)
- [Orchestrating Multi-Step Agents: Temporal/Dagster/LangGraph Patterns](https://kinde.com/learn/ai-for-software-engineering/ai-devops/orchestrating-multi-step-agents-temporal-dagster-langgraph-patterns-for-long-running-work/)

#### Workflow Persistence Strategies
1. **Phantom Git (Hawk Agent Approach):**
   - Every action tracked in isolated git repository
   - Rollback capability at any point
   - Validation before real git commit
   - Session-specific isolation

2. **Event Sourcing:**
   - All state transitions stored as events
   - Replay capability for debugging
   - Temporal queries (state at any point in time)
   - Natural audit trail

3. **Checkpoint/Restore:**
   - Periodic state snapshots
   - Faster recovery than full replay
   - Memory vs. persistence tradeoffs

---

## 2. Saga Pattern Implementations for Async Workflows

### Saga Pattern Fundamentals

**Definition:** A sequence of distributed transactions where each step updates the system, with compensating actions triggered on failure.

**Key Characteristics:**
- Long-running transactions across multiple services
- Compensating transactions for rollback
- No distributed locks or two-phase commit
- Event-driven coordination

**Sources:**
- [Mastering Saga Patterns for Distributed Transactions in Microservices](https://temporal.io/blog/mastering-saga-patterns-for-distributed-transactions-in-microservices)
- [Saga Pattern - microservices.io](https://microservices.io/patterns/data/saga.html)
- [Saga Design Pattern - Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/patterns/saga)

### Saga Implementation Patterns

#### 2.1 Choreography-Based Sagas
**Description:** Decentralized coordination through events. Each service emits events and listens to events from others.

**Architecture:**
```
Service A → Event A → Service B → Event B → Service C → Event C
                      ↓                    ↓
                  Compensate A'       Compensate B'
```

**Advantages:**
- No central orchestrator
- Loose coupling between services
- Scalable through event distribution

**Disadvantages:**
- Complex to understand flow
- Difficult to debug
- No central view of state

**Implementation Considerations:**
- Event schema versioning
- Correlation IDs for tracking
- Idempotent compensating actions
- Event ordering guarantees

**Sources:**
- [Implement Saga Patterns in Microservices with NestJS and Kafka](https://thenewstack.io/implement-saga-patterns-in-microservices-with-nestjs-and-kafka/)

#### 2.2 Orchestration-Based Sagas
**Description:** Central orchestrator coordinates transactions and compensating actions.

**Architecture:**
```
Orchestrator → Service A (execute)
             → Service B (execute)
             → Service C (execute)
             → Compensate C' (if C fails)
             → Compensate B' (if B fails)
             → Compensate A' (if A fails)
```

**Advantages:**
- Clear workflow definition
- Centralized error handling
- Easier to understand and debug
- Explicit state management

**Disadvantages:**
- Single point of coordination
- More tightly coupled
- Orchestrator scalability concerns

**Implementation Considerations:**
- Orchestrator state persistence
- Timeout handling for each step
- Compensating action definition
- Saga completion detection

**Sources:**
- [Mastering Distributed Transactions: Implementing the Saga Pattern in .NET](https://roshancloudarchitect.me/mastering-distributed-transactions-implementing-the-saga-pattern-in-net-with-azure-cloud-services-68f78f5b02c4)
- [Sagaway - GitHub](https://github.com/Zio-Net/Sagaway)

### Saga Patterns for Agent Workflows

#### Agent Lifecycle Sagas
**Use Case:** Managing complex agent workflows with multiple stages and potential failures.

**Example: PRP Implementation Saga**
```
1. Research Agent → Creates PRP
2. Review Agent → Validates PRP
   └─> If validation fails → Compensate: Update PRP
3. Test Agent → Creates tests
4. Implementer Agent → Implements feature
   └─> If tests fail → Compensate: Revise implementation
5. Validation Agent → Final validation
   └─> If validation fails → Compensate: Add PRP addendum, retry from step 2
```

**Implementation Pattern:**
```python
class PRPImplementationSaga:
    def __init__(self, session_state):
        self.state = session_state
        self.current_step = 0
        self.compensation_log = []

    async def execute_step(self, step_number):
        try:
            result = await self.steps[step_number].execute(self.state)
            self.compensation_log.append(result)
            return result
        except Exception as e:
            await self.compensate(step_number - 1)
            raise

    async def compensate(self, from_step):
        for i in range(from_step, -1, -1):
            if self.compensation_log[i]:
                await self.steps[i].compensate(self.compensation_log[i])
```

**Sources:**
- [Understanding the Saga Pattern: Managing Distributed Transactions](https://www.gocodeo.com/post/understanding-the-saga-pattern-managing-distributed-transactions)

### Saga State Management

#### State Representation
1. **Explicit State Machine:**
```yaml
states:
  - STARTED
  - RESEARCHING
  - REVIEW_PENDING
  - REVIEW_FAILED
  - TESTING
  - IMPLEMENTING
  - VALIDATING
  - COMPLETED
  - COMPENSATING
```

2. **Event Log:**
```json
[
  {"event": "saga_started", "timestamp": "...", "data": {...}},
  {"event": "research_completed", "timestamp": "...", "data": {...}},
  {"event": "review_failed", "timestamp": "...", "error": "..."},
  {"event": "compensating_research", "timestamp": "...", "data": {...}}
]
```

#### Recovery Strategies
1. **Forward Recovery:** Retry failed step with updated context
2. **Backward Recovery:** Execute compensating transactions
3. **Hybrid:** Combine retry with selective compensation

**Sources:**
- [Enhancing Saga Pattern for Distributed Transactions](https://www.mdpi.com/2076-3417/12/12/6242)

---

## 3. React/Redux-like Context Propagation in Non-UI Systems

### Redux Pattern Fundamentals for Backend Systems

**Core Concepts:**
- **Single Source of Truth:** All state in one centralized store
- **State is Read-Only:** State changes through pure functions (reducers)
- **Changes are Pure Functions:** Reducers take previous state and action, return new state
- **Unidirectional Data Flow:** Actions → Dispatch → Reducers → State Update

**Sources:**
- [A Redux-Inspired Backend](https://medium.com/resolvejs/redux-redux-backend-ebcfc79bbbea)
- [Can Redux be Used on the Server?](https://blog.bitsrc.io/can-redux-be-used-on-the-server-e2d3ecbf7ee4)
- [Redux and it's relation to CQRS](https://github.com/reduxjs/redux/issues/351)

### Relationship to CQRS and Event Sourcing

**Key Insight:** Redux is influenced by CQRS and Event Sourcing concepts.

**Shared Principles:**
1. **One-way data flow:** Actions → State changes → View updates
2. **Functional stateless architecture:** Pure functions for state transitions
3. **Event-driven:** Actions are events that drive state changes
4. **Immutability:** State objects are never mutated, always replaced

**Implementation Pattern:**
```typescript
// Redux-like store for agent workflow state
interface AgentWorkflowState {
  currentPhase: 'planning' | 'research' | 'implementation' | 'validation';
  activeAgents: string[];
  completedTasks: Task[];
  pendingActions: Action[];
  context: Record<string, any>;
}

type Action =
  | { type: 'START_AGENT'; agentId: string; context: any }
  | { type: 'COMPLETE_TASK'; taskId: string; result: any }
  | { type: 'UPDATE_CONTEXT'; key: string; value: any }
  | { type: 'AGENT_ERROR'; agentId: string; error: Error };

function workflowReducer(
  state: AgentWorkflowState,
  action: Action
): AgentWorkflowState {
  switch (action.type) {
    case 'START_AGENT':
      return {
        ...state,
        activeAgents: [...state.activeAgents, action.agentId],
        context: { ...state.context, ...action.context }
      };
    case 'COMPLETE_TASK':
      return {
        ...state,
        completedTasks: [...state.completedTasks, action.taskId],
        activeAgents: state.activeAgents.filter(id => id !== action.agentId)
      };
    // ... other cases
  }
}
```

**Sources:**
- [Server-side Redux. Part I. The Redux.](http://valerii-udodov.com/posts/server-side-redux/server-side-redux-1-the-redux/)
- [Design Philosophy Behind Flux and Redux: CQRS, Event Sourcing, DDD](https://www.v2think.com/design-philosophy-behind-flux-and-redux-CQRS-ES-DDD)

### Context Propagation Patterns for Agent Systems

#### 3.1 Hierarchical Context (React-like)
**Pattern:** Parent agents pass context to child agents through props/context.

**Implementation:**
```typescript
interface AgentContext {
  sessionId: string;
  prdContent: string;
  taskBreakdown: Task[];
  phantomGitRepo: string;
  callbacks: {
    onRequestHuman: (reason: string) => Promise<void>;
    onUpdateStatus: (status: string) => void;
  };
}

class Agent {
  constructor(
    private context: AgentContext,
    private props: Record<string, any>
  ) {}

  async execute(): Promise<Result> {
    // Child agents receive subset of context
    const childContext = this.deriveChildContext();
    const childAgent = new ChildAgent(childContext, childProps);
    return await childAgent.execute();
  }

  private deriveChildContext(): Partial<AgentContext> {
    return {
      sessionId: this.context.sessionId,
      phantomGitRepo: this.context.phantomGitRepo,
      callbacks: this.context.callbacks
    };
  }
}
```

**Advantages:**
- Clear data flow
- Type-safe context passing
- Explicit dependencies
- Easy to trace context lineage

**Sources:**
- [Redux Fundamentals, Part 2: Concepts and Data Flow](https://redux.js.org/tutorials/fundamentals/part-2-concepts-data-flow)
- [React Context: Dependency injection, not state management](https://testdouble.com/insights/react-context-for-dependency-injection-not-state-management)

#### 3.2 Global Store with Selectors (Redux-like)
**Pattern:** Centralized store with selectors for context access.

**Implementation:**
```typescript
class AgentWorkflowStore {
  private store: ReduxStore<WorkflowState>;

  getState(): WorkflowState {
    return this.store.getState();
  }

  // Selectors for specific context
  selectCurrentTask(): Task | null {
    return this.store.getState().currentTask;
  }

  selectAgentContext(agentId: string): AgentContext | null {
    return this.store.getState().agentContexts[agentId] || null;
  }

  selectProjectPillars(): Pillars {
    return {
      testing: this.store.getState().testingConfig,
      logging: this.store.getState().loggingConfig,
      linting: this.store.getState().lintingConfig
    };
  }

  // Actions for state updates
  dispatch(action: Action) {
    this.store.dispatch(action);
  }
}

// Agents access context through store
class ImplementerAgent {
  constructor(private store: AgentWorkflowStore) {}

  async execute(): Promise<Result> {
    const task = this.store.selectCurrentTask();
    const pillars = this.store.selectProjectPillars();

    // ... implementation using context

    this.store.dispatch({
      type: 'TASK_COMPLETED',
      taskId: task.id,
      result
    });
  }
}
```

**Advantages:**
- Centralized state management
- Time-travel debugging
- Predictable state updates
- Easy state inspection and logging

**Sources:**
- [Redux Fundamentals, Part 7: Standard Redux Patterns](https://redux.js.org/tutorials/fundamentals/part-7-standard-patterns)

#### 3.3 Event-Sourced Context
**Pattern:** Context reconstructed from event history.

**Implementation:**
```typescript
interface ContextEvent {
  eventType: string;
  timestamp: number;
  agentId: string;
  data: any;
}

class EventSourcedContext {
  private eventLog: ContextEvent[] = [];

  recordEvent(event: ContextEvent) {
    this.eventLog.push(event);
  }

  reconstructContext(atTimestamp?: number): AgentContext {
    const events = atTimestamp
      ? this.eventLog.filter(e => e.timestamp <= atTimestamp)
      : this.eventLog;

    return events.reduce((context, event) => {
      return this.applyEvent(context, event);
    }, this.getInitialState());
  }

  private applyEvent(context: AgentContext, event: ContextEvent): AgentContext {
    switch (event.eventType) {
      case 'PRD_CREATED':
        return { ...context, prdContent: event.data.prd };
      case 'TASK_BREAKDOWN_COMPLETED':
        return { ...context, tasks: event.data.tasks };
      case 'PHANTOM_GIT_COMMIT':
        return { ...context, lastCommit: event.data.commitHash };
      // ... other event types
    }
  }
}
```

**Advantages:**
- Complete audit trail
- Time-travel debugging
- State reconstruction at any point
- Natural fit for saga patterns

**Sources:**
- [Event Sourcing - Martin Fowler](https://martinfowler.com/eaaDev/EventSourcing.html)
- [How We Used Redux on Backend and Got Offline-First](https://hackernoon.com/how-we-used-redux-on-backend-and-got-offline-first-mobile-app-as-a-result-b8ab5e7f7a4)

### Context Propagation Best Practices

#### 1. Immutable Context Updates
```typescript
// ❌ Bad: Mutation
context.activeAgents.push(newAgent);

// ✅ Good: Immutable update
context = {
  ...context,
  activeAgents: [...context.activeAgents, newAgent]
};
```

#### 2. Context Versioning
```typescript
interface ContextV1 {
  prd: string;
  tasks: Task[];
}

interface ContextV2 extends ContextV1 {
  researchCache: Map<string, ResearchResult>;
  parallelTasks: TaskGroup[];
}

function migrateContext(v1: ContextV1): ContextV2 {
  return {
    ...v1,
    researchCache: new Map(),
    parallelTasks: []
  };
}
```

#### 3. Context Validation
```typescript
function validateContext(context: AgentContext): ValidationResult {
  const errors: string[] = [];

  if (!context.sessionId) {
    errors.push('Missing sessionId');
  }

  if (!context.phantomGitRepo) {
    errors.push('Missing phantomGitRepo');
  }

  if (!context.callbacks.onRequestHuman) {
    errors.push('Missing human intervention callback');
  }

  return {
    valid: errors.length === 0,
    errors
  };
}
```

---

## 4. Tools and Frameworks for Composable Workflow Systems

### Framework Comparison Matrix

| Framework | Primary Focus | Durable Execution | Agent Support | Language | Best For |
|-----------|--------------|-------------------|---------------|----------|----------|
| **Temporal** | Workflow orchestration | ✅ Excellent | ⚠️ Indirect | Go, Java, Python, TypeScript | Mission-critical workflows, long-running processes |
| **LangGraph** | AI agent workflows | ⚠️ Limited | ✅ Excellent | Python | LLM agent orchestration, stateful agents |
| **Dagster** | Data pipelines | ✅ Good | ⚠️ Indirect | Python | Data orchestration, ML pipelines |
| **Prefect** | Workflow automation | ✅ Good | ✅ Growing | Python | Modern data workflows, agent integration |
| **Prefect AI Teams** | Agent workflows | ✅ Good | ✅ Excellent | Python | Production agent workflows with Pydantic AI, LangGraph |

### Deep Dive: Temporal

**Overview:** Durable execution system designed for mission-critical applications.

**Key Features:**
- **Durable Execution:** Workflows survive process failures
- **State Persistence:** Automatic state checkpointing
- **Time Travel:** Replay workflow execution for debugging
- **Deterministic:** Workflow logic is deterministic by design
- **Scalable:** Handles millions of concurrent workflows

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                      Temporal Cluster                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  History    │  │   Matching  │  │   Worker    │         │
│  │   Service   │  │   Service   │  │   Service   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
         ▲                    ▲                    ▲
         │                    │                    │
         │                    │                    │
    ┌────┴────┐         ┌────┴────┐         ┌────┴────┐
    │ Client  │         │ Client  │         │ Worker  │
    │ Code    │         │ Code    │         │ Process │
    └─────────┘         └─────────┘         └─────────┘
```

**Workflow vs. Activity Separation:**
- **Workflow:** Orchestrates logic, durable, deterministic
- **Activity:** Executes non-deterministic logic (API calls, file I/O)

**Example: PRP Implementation Workflow**
```go
// Workflow definition (durable, deterministic)
func PRPImplementationWorkflow(ctx workflow.Context, prp PRP) error {
    // Step 1: Research
    var researchResult ResearchResult
    err := workflow.ExecuteActivity(ctx, ResearchActivity, prp).Get(ctx, &researchResult)
    if err != nil {
        return err
    }

    // Step 2: Review
    var reviewResult ReviewResult
    err = workflow.ExecuteActivity(ctx, ReviewActivity, researchResult).Get(ctx, &reviewResult)
    if err != nil {
        // Compensating action
        workflow.ExecuteActivity(ctx, UpdatePRPActivity, reviewResult.feedback).Get(ctx, nil)
        return err
    }

    // Step 3: Implementation
    var implResult ImplementationResult
    err = workflow.ExecuteActivity(ctx, ImplementActivity, reviewResult.approvedPRP).Get(ctx, &implResult)
    if err != nil {
        // Retry with compensation
        return workflow.ExecuteActivity(ctx, AddPRPAddendumActivity, implResult.errors).Get(ctx, nil)
    }

    return nil
}

// Activity implementations (non-deterministic, can fail)
func ResearchActivity(ctx context.Context, prp PRP) (ResearchResult, error) {
    // Perform research (HTTP requests, file I/O, etc.)
    return result, nil
}
```

**Sources:**
- [Orchestrating Multi-Step Agents: Temporal Patterns](https://kinde.com/learn/ai-for-software-engineering/ai-devops/orchestrating-multi-step-agents-temporal-dagster-langgraph-patterns-for-long-running-work/)
- [Temporal Workflow Orchestration Patterns](https://mcpmarket.com/zh/tools/skills/temporal-workflow-orchestration-patterns)
- [Orchestration Showdown: Airflow vs Dagster vs Temporal](https://medium.com/datumlabs/orchestration-showdown-airflow-vs-dagster-vs-temporal-in-the-age-of-llms-758a76876df0)

### Deep Dive: LangGraph

**Overview:** Workflow orchestration framework specifically for LLM applications with state machine principles.

**Key Features:**
- **Stateful Agents:** Agents maintain state across interactions
- **Graph-based Workflows:** Define workflows as graphs of nodes and edges
- **Conditional Routing:** Dynamic agent selection based on state
- **Built-in Memory:** Persistent memory for long-running conversations
- **Integration:** Works with LangChain, LangSmith, and other LLM tools

**Architecture:**
```python
from langgraph.graph import StateGraph, END
from typing import TypedDict

class WorkflowState(TypedDict):
    prd: str
    task_breakdown: List[Task]
    current_task: Task
    research_results: Dict[str, Any]
    implementation_status: str
    validation_results: Dict[str, Any]

def create_prp_workflow():
    workflow = StateGraph(WorkflowState)

    # Add nodes (agents)
    workflow.add_node("breakdown", task_breakdown_agent)
    workflow.add_node("research", research_agent)
    workflow.add_node("create_prp", prp_creation_agent)
    workflow.add_node("review_prp", prp_review_agent)
    workflow.add_node("implement", implementation_agent)
    workflow.add_node("validate", validation_agent)

    # Add edges (workflow routing)
    workflow.set_entry_point("breakdown")
    workflow.add_edge("breakdown", "research")
    workflow.add_edge("research", "create_prp")
    workflow.add_conditional_edges(
        "review_prp",
        should_revise_prp,
        {
            "revise": "create_prp",  # Loop back
            "approve": "implement"   # Continue
        }
    )
    workflow.add_conditional_edges(
        "validate",
        should_retry_implementation,
        {
            "retry": "implement",     # Loop back
            "complete": END,
            "addendum": "create_prp"  # Major revision needed
        }
    )

    return workflow.compile()
```

**State Management:**
```python
class AgentState(TypedDict):
    messages: List[BaseMessage]
    current_agent: str
    context: Dict[str, Any]
    next_action: Optional[str]

def agent_node(state: AgentState) -> AgentState:
    """Agent node that processes state and returns updates"""
    agent = get_agent(state["current_agent"])
    result = agent.process(state["context"])

    return {
        **state,
        "messages": state["messages"] + [result.message],
        "context": {**state["context"], **result.updates},
        "next_action": result.next_action
    }
```

**Sources:**
- [LangGraph State Machines: Managing Complex Agent Task Flows](https://dev.to/jamesli/langgraph-state-machines-managing-complex-agent-task-flows-in-production-36f4)
- [Orchestrating Multi-Step Agents: LangGraph Patterns](https://kinde.com/learn/ai-for-software-engineering/ai-devops/orchestrating-multi-step-agents-temporal-dagster-langgraph-patterns-for-long-running-work/)

### Deep Dive: Prefect

**Overview:** Modern workflow orchestration with native Python integration and growing agent support.

**Key Features:**
- **Pythonic:** Natural Python syntax for workflow definition
- **Durable Execution:** Automatic state persistence and retry
- **Agent Integration:** Prefect AI Teams for agent workflows
- **Flexible Deployment:** Local, cloud, or hybrid
- **Observability:** Built-in monitoring and debugging

**Example: Agent Workflow with Prefect**
```python
from prefect import flow, task, get_run_logger
from prefect_ai_teams import AgentTeam

@task
def research_phase(task: Task) -> ResearchResult:
    logger = get_run_logger()
    logger.info(f"Researching task: {task.id}")
    # Research implementation
    return result

@task
def create_prp(task: Task, research: ResearchResult) -> PRP:
    logger = get_run_logger()
    logger.info(f"Creating PRP for task: {task.id}")
    # PRP creation implementation
    return prp

@task
def review_prp(prp: PRP) -> ReviewResult:
    # PRP review implementation
    return result

@flow(name="PRP Implementation Pipeline")
async def prp_implementation_pipeline(prd: str):
    # Create agent team
    team = AgentTeam(
        researchers=["research_agent_1", "research_agent_2"],
        reviewer="graybeard_agent",
        implementer="coder_agent"
    )

    # Orchestrate workflow
    tasks = await team.breakdown_tasks(prd)

    for task in tasks:
        research = await research_phase(task)
        prp = await create_prp(task, research)

        review = await review_prp(prp)
        if review.needs_revision:
            prp = await create_prp(task, research, review.feedback)

        result = await team.implement(prp)
        validation = await validate_implementation(result)

        if not validation.passed:
            # Retry with addendum
            prp_addendum = await create_addendum(validation.errors)
            prp = merge_prp(prp, prp_addendum)
            result = await team.implement(prp)

    return result
```

**Sources:**
- [Orchestration Tools: Choose the Right Tool](https://www.prefect.io/blog/orchestration-tools-choose-the-right-tool-for-the-job)
- [Prefect AI Teams](https://www.prefect.io/ai-teams)
- [Workflow Orchestration Platforms: Kestra vs Temporal vs Prefect](https://procycons.com/en/blogs/workflow-orchestration-platforms-comparison-2025/)

### Deep Dive: Dagster

**Overview:** Data-aware orchestration platform with strong typing and asset-based workflows.

**Key Features:**
- **Asset-Based:** Define data assets and their dependencies
- **Type-Safe:** Strong typing for dataflow validation
- **Software-Defined Assets:** Code-first approach to data pipelines
- **Observability:** Deep visibility into data lineage
- **Testing:** First-class testing support

**Example: Asset-Based Workflow**
```python
from dagster import asset, multi_asset, AssetExecutionContext, AssetSpec
from dagster._utils.typing import UFDOutput

@asset
def prd_document() -> str:
    """Load PRD document"""
    return load_prd()

@asset(deps=[prd_document])
def task_breakdown(prd_document: str) -> List[Task]:
    """Break down PRD into tasks"""
    return breakdown_tasks(prd_document)

@asset(deps=[task_breakdown])
async def research_results(tasks: List[Task]) -> Dict[str, ResearchResult]:
    """Perform research for all tasks"""
    results = {}
    for task in tasks:
        results[task.id] = await research_task(task)
    return results

@asset(deps=[research_results, task_breakdown])
def prps(tasks: List[Task], research: Dict[str, ResearchResult]) -> List[PRP]:
    """Create PRPs for all tasks"""
    return [create_prp(task, research[task.id]) for task in tasks]

@multi_asset(
    specs=[
        AssetSpec("implementation_results"),
        AssetSpec("validation_results")
    ],
    deps=[prps]
)
async def implement_and_validate(
    context: AssetExecutionContext,
    prps: List[PRP]
) -> UFDOutput[dict]:
    """Implement and validate PRPs"""
    impl_results = []
    val_results = []

    for prp in prps:
        impl = await implement_prp(prp)
        impl_results.append(impl)

        val = await validate_implementation(impl)
        val_results.append(val)

        if not val.passed:
            # Handle validation failure
            context.log.warning(f"Validation failed for {prp.task_id}")

    return {
        "implementation_results": impl_results,
        "validation_results": val_results
    }
```

**Sources:**
- [Orchestrating Multi-Step Agents: Dagster Patterns](https://kinde.com/learn/ai-for-software-engineering/ai-devops/orchestrating-multi-step-agents-temporal-dagster-langgraph-patterns-for-long-running-work/)

### Domain-Specific Languages (DSL) for Workflow Composition

#### Declarative Workflow DSLs

**Example: YAML-Based Workflow DSL**
```yaml
workflow:
  name: "PRP Implementation Pipeline"
  version: "1.0"

  agents:
    researcher:
      type: "research"
      max_retries: 3
      timeout: 300

    reviewer:
      type: "review"
      persona: "graybeard"
      strictness: "high"

    implementer:
      type: "implementation"
      max_attempts: 4
      validation_level: "strict"

  stages:
    - name: "research"
      agent: "researcher"
      inputs:
        - "prd"
        - "task_breakdown"
      outputs:
        - "research_results"
      on_failure: "escalate_to_human"

    - name: "create_prp"
      agent: "researcher"
      inputs:
        - "research_results"
        - "task_context"
      outputs:
        - "prp_document"
      depends_on: ["research"]

    - name: "review_prp"
      agent: "reviewer"
      inputs:
        - "prp_document"
      outputs:
        - "review_result"
      on_failure:
        action: "retry_stage"
        stage: "create_prp"
        max_retries: 2
      depends_on: ["create_prp"]

    - name: "implement"
      agent: "implementer"
      inputs:
        - "approved_prp"
      outputs:
        - "implementation_result"
      on_failure:
        action: "create_addendum"
        target_stage: "create_prp"
      depends_on: ["review_prp"]

    - name: "validate"
      agent: "validator"
      inputs:
        - "implementation_result"
        - "test_suite"
      outputs:
        - "validation_result"
      on_failure:
        action: "escalate"
        escalation_path: ["root_cause_analysis", "fagan_inspection", "human"]
      depends_on: ["implement"]
```

**Sources:**
- [A Declarative Language for Building And Orchestrating Agents](https://arxiv.org/html/2512.19769)
- [AI Model Orchestration with Wity.AI](https://blog.wity.ai/ai-model-orchestration-with-wity.ai-part-1/)

---

## 5. Escalation Paths and Error Handling Best Practices

### Error Handling Patterns for Agent Systems

#### 5.1 Exception Handling and Recovery Pattern

**Core Principles:**
1. **Explicit Error Types:** Categorize errors for appropriate handling
2. **Graceful Degradation:** Degrade functionality rather than fail completely
3. **Recovery Strategies:** Multiple recovery mechanisms with clear escalation
4. **Observability:** Comprehensive error logging and tracking

**Implementation Pattern:**
```typescript
enum ErrorSeverity {
  TRANSIENT = 'transient',      // Temporary failures (network, rate limits)
  RECOVERABLE = 'recoverable',  // Can be fixed with retry/compensation
  PERMANENT = 'permanent',      // Requires human intervention
  CRITICAL = 'critical'         // System-wide failure
}

enum ErrorCategory {
  AGENT_FAILURE = 'agent_failure',
  VALIDATION_FAILURE = 'validation_failure',
  TOOL_FAILURE = 'tool_failure',
  CONTEXT_ERROR = 'context_error',
  TIMEOUT = 'timeout'
}

class AgentError extends Error {
  constructor(
    public severity: ErrorSeverity,
    public category: ErrorCategory,
    message: string,
    public context: Record<string, any>,
    public retryable: boolean = false
  ) {
    super(message);
    this.name = 'AgentError';
  }
}

class ErrorHandler {
  private escalationLevel = 0;
  private maxEscalation = 4;

  async handle(error: AgentError): Promise<RecoveryResult> {
    // Log error with full context
    this.logError(error);

    // Determine recovery strategy based on severity
    switch (error.severity) {
      case ErrorSeverity.TRANSIENT:
        return await this.retryWithBackoff(error);

      case ErrorSeverity.RECOVERABLE:
        return await this.attemptRecovery(error);

      case ErrorSeverity.PERMANENT:
        return await this.escalate(error);

      case ErrorSeverity.CRITICAL:
        return await this.criticalFailure(error);
    }
  }

  private async retryWithBackoff(error: AgentError): Promise<RecoveryResult> {
    const maxRetries = 3;
    const baseDelay = 1000; // 1 second

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      const delay = baseDelay * Math.pow(2, attempt);
      await this.sleep(delay);

      try {
        // Retry the operation
        const result = await this.retryOperation(error.context);
        return { success: true, result };
      } catch (retryError) {
        if (attempt === maxRetries - 1) {
          // Last retry failed, escalate
          return await this.escalate(error);
        }
      }
    }

    return { success: false, error };
  }

  private async attemptRecovery(error: AgentError): Promise<RecoveryResult> {
    // Try recovery strategies based on error category
    switch (error.category) {
      case ErrorCategory.VALIDATION_FAILURE:
        return await this.recoverFromValidationError(error);

      case ErrorCategory.TOOL_FAILURE:
        return await this.recoverFromToolFailure(error);

      case ErrorCategory.AGENT_FAILURE:
        return await this.recoverFromAgentFailure(error);

      default:
        return await this.escalate(error);
    }
  }

  private async escalate(error: AgentError): Promise<RecoveryResult> {
    if (this.escalationLevel >= this.maxEscalation) {
      // Final escalation to human
      return await this.escalateToHuman(error);
    }

    // Progressively escalate
    switch (this.escalationLevel) {
      case 0:
        return await this.rootCauseAnalysis(error);
      case 1:
        return await this.faganInspection(error);
      case 2:
        return await this.independentReview(error);
      case 3:
        return await this.escalateToHuman(error);
    }

    this.escalationLevel++;
    return { success: false, escalated: true };
  }
}
```

**Sources:**
- [Exception Handling and Recovery Pattern - Agentic Design Patterns](https://github.com/ginobefun/agentic-design-patterns-cn/blob/main/15-Chapter-12-Exception-Handling-and-Recovery.md)
- [5 Recovery Strategies for Multi-Agent LLM Failures](https://www.newline.co/@zaoyang/5-recovery-strategies-for-multi-agent-llm-failures--673fe4c4)

#### 5.2 Escalation Path Implementation

**Hawk Agent Escalation Hierarchy:**
```
1. Implementer Failure
   ↓ (retry with updated tools or PRP)
2. Root Cause Analysis Agent
   ↓ (if persistent failure)
3. Fagan Inspection Agent
   ↓ (if problem persists)
4. Independent Review
   ↓ (if still unresolved)
5. Human-in-the-Loop
```

**Implementation:**
```typescript
class EscalationManager {
  private escalationPath: EscalationStage[] = [
    {
      level: 1,
      name: 'implementer_retry',
      agent: 'implementer',
      maxAttempts: 2,
      action: async (error, context) => {
        // Update tools or PRP and retry
        const updatedContext = await this.updateContext(error, context);
        return this.retryAgent(updatedContext);
      }
    },
    {
      level: 2,
      name: 'root_cause_analysis',
      agent: 'rca_agent',
      maxAttempts: 1,
      action: async (error, context) => {
        const analysis = await this.performRootCauseAnalysis(error, context);
        if (analysis.resolvable) {
          return this.applyFix(analysis.fix);
        }
        return { escalate: true };
      }
    },
    {
      level: 3,
      name: 'fagan_inspection',
      agent: 'inspection_agent',
      maxAttempts: 1,
      action: async (error, context) => {
        const findings = await this.performFaganInspection(error, context);
        if (findings.fixable) {
          return this.applyInspectionFix(findings);
        }
        return { escalate: true };
      }
    },
    {
      level: 4,
      name: 'independent_review',
      agent: 'review_agent',
      maxAttempts: 1,
      action: async (error, context) => {
        const review = await this.performIndependentReview(error, context);
        if (review.solution) {
          return this.applySolution(review.solution);
        }
        return { escalate: true };
      }
    },
    {
      level: 5,
      name: 'human_intervention',
      agent: 'human',
      maxAttempts: 1,
      action: async (error, context) => {
        return await this.requestHumanIntervention(error, context);
      }
    }
  ];

  private currentLevel = 0;

  async escalate(error: AgentError, context: WorkflowContext): Promise<Resolution> {
    while (this.currentLevel < this.escalationPath.length) {
      const stage = this.escalationPath[this.currentLevel];
      console.log(`Escalating to level ${stage.level}: ${stage.name}`);

      const result = await stage.action(error, context);

      if (result.success) {
        // Reset escalation level on success
        this.currentLevel = 0;
        return result;
      }

      if (result.escalate) {
        this.currentLevel++;
      } else {
        // Stay at current level for retry
        if (stage.attempts < stage.maxAttempts) {
          stage.attempts++;
        } else {
          this.currentLevel++;
        }
      }
    }

    // All escalation levels exhausted
    return { success: false, exhausted: true };
  }

  private async requestHumanIntervention(
    error: AgentError,
    context: WorkflowContext
  ): Promise<Resolution> {
    // Pause workflow and request human input
    const intervention = await context.callbacks.onRequestHuman({
      error: error.message,
      context: context.summary,
      suggestions: this.generateSuggestions(error),
      actions: ['retry', 'skip', 'abort', 'modify_prp']
    });

    switch (intervention.action) {
      case 'retry':
        return { success: true, retry: true };
      case 'skip':
        return { success: true, skip: true };
      case 'abort':
        return { success: false, abort: true };
      case 'modify_prp':
        const updatedPRP = await this.modifyPRP(intervention.modifications);
        return { success: true, updatedContext: { prp: updatedPRP } };
    }
  }
}
```

**Sources:**
- [The AI Agent Framework Landscape in 2025](https://medium.com/@hieutrantrung.it/the-ai-agent-framework-landscape-in-2025-what-changed-and-what-matters-3cd9b07ef2c3)
- [Best Practices for Building Reliable AI Agents (2025)](https://www.uipath.com/blog/ai/agent-builder-best-practices)

#### 5.3 Retry Patterns

**Exponential Backoff with Jitter:**
```typescript
class RetryPolicy {
  async executeWithRetry<T>(
    operation: () => Promise<T>,
    options: {
      maxRetries: number;
      baseDelay: number;
      maxDelay: number;
      jitter: boolean;
    }
  ): Promise<T> {
    let lastError: Error;

    for (let attempt = 0; attempt <= options.maxRetries; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;

        if (attempt === options.maxRetries) {
          throw new MaxRetriesExceededError(error, options.maxRetries);
        }

        // Calculate delay with exponential backoff and jitter
        const delay = this.calculateDelay(attempt, options);
        await this.sleep(delay);
      }
    }

    throw lastError;
  }

  private calculateDelay(attempt: number, options: RetryOptions): number {
    // Exponential backoff
    const exponentialDelay = options.baseDelay * Math.pow(2, attempt);

    // Add jitter to avoid thundering herd
    const jitter = options.jitter
      ? Math.random() * options.baseDelay
      : 0;

    // Cap at max delay
    return Math.min(exponentialDelay + jitter, options.maxDelay);
  }
}
```

**Sources:**
- [Top 12 AI Agent Frameworks That Actually Do the Job](https://www.kubiya.ai/blog/top-12-ai-agent-frameworks-that-actually-do-the-job)
- [Agentic AI Applications: A Field Guide](https://gradientflow.substack.com/p/agentic-ai-applications-a-field-guide)

### Error Handling Best Practices Summary

1. **Categorize Errors:** Use severity and category for appropriate handling
2. **Implement Escalation Paths:** Progressive escalation from automatic to manual
3. **Retry with Backoff:** Exponential backoff with jitter for transient failures
4. **Compensating Actions:** Rollback mechanisms for distributed transactions
5. **Observability:** Comprehensive logging, tracing, and monitoring
6. **Human-in-the-Loop:** Final escalation point for unresolvable issues
7. **Circuit Breakers:** Prevent cascading failures
8. **Timeout Management:** Appropriate timeouts at each level

---

## 6. Ink Framework Integration for Agent Lifecycles

### Ink Framework Overview

**What is Ink?**
- React for interactive command-line interfaces
- Build CLI tools using React components
- Same component model and paradigms as web React
- Virtual DOM for efficient terminal rendering

**Sources:**
- [Ink GitHub Repository](https://github.com/vadimdemedes/ink)
- [How to use ink-ui to Build Beautiful CLI Tools Like OpenAI's Codex](https://levelup.gitconnected.com/how-to-use-ink-ui-to-build-beautiful-cli-tools-like-openais-codex-d793c752da5f)

### Integration Patterns for Agent Systems

#### 6.1 Agent Lifecycle UI Components

**Workflow Progress Component:**
```tsx
import React, { useState, useEffect } from 'react';
import { Box, Text, useApp } from 'ink';

interface AgentWorkflowProps {
  workflow: WorkflowState;
  onStatusChange?: (status: string) => void;
}

const AgentWorkflow: React.FC<AgentWorkflowProps> = ({ workflow, onStatusChange }) => {
  const { exit } = useApp();
  const [currentAgent, setCurrentAgent] = useState(workflow.currentAgent);
  const [progress, setProgress] = useState(workflow.progress);

  useEffect(() => {
    // Subscribe to workflow state changes
    const unsubscribe = workflow.subscribe((state) => {
      setCurrentAgent(state.currentAgent);
      setProgress(state.progress);

      if (state.status === 'completed') {
        exit();
      }
    });

    return () => unsubscribe();
  }, [workflow]);

  return (
    <Box flexDirection="column" padding={1}>
      <Box marginBottom={1}>
        <Text bold color="green">
          Hawk Agent Workflow
        </Text>
      </Box>

      <Box marginBottom={1}>
        <Text>Current Phase: </Text>
        <Text color="cyan">{workflow.phase}</Text>
      </Box>

      <Box marginBottom={1}>
        <Text>Active Agent: </Text>
        <Text color="yellow">{currentAgent}</Text>
      </Box>

      <Box marginBottom={1}>
        <Text>Progress: </Text>
        <ProgressBar progress={progress} />
      </Box>

      <AgentList agents={workflow.agents} />

      {workflow.error && (
        <ErrorDisplay error={workflow.error} onDismiss={() => workflow.clearError()} />
      )}
    </Box>
  );
};

const ProgressBar: React.FC<{ progress: number }> = ({ progress }) => {
  const width = 40;
  const filled = Math.round((progress / 100) * width);
  const empty = width - filled;

  return (
    <Text>
      <Text color="green">{'█'.repeat(filled)}</Text>
      <Text dimColor>{'░'.repeat(empty)}</Text>
      <Text> {progress}%</Text>
    </Text>
  );
};

const AgentList: React.FC<{ agents: Agent[] }> = ({ agents }) => {
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>Agents:</Text>
      {agents.map((agent) => (
        <Box key={agent.id}>
          <Text>
            {agent.status === 'active' && <Text color="green">●</Text>}
            {agent.status === 'pending' && <Text color="yellow">○</Text>}
            {agent.status === 'completed' && <Text color="blue">✓</Text>}
            {agent.status === 'failed' && <Text color="red">✗</Text>}
            <Text> {agent.name} - {agent.status}</Text>
          </Text>
        </Box>
      ))}
    </Box>
  );
};

const ErrorDisplay: React.FC<{
  error: Error;
  onDismiss: () => void;
}> = ({ error, onDismiss }) => {
  return (
    <Box flexDirection="column" borderStyle="double" borderColor="red" padding={1}>
      <Text bold color="red">Error:</Text>
      <Text>{error.message}</Text>
      <Text color="gray" dimColor>
        Press 'd' to dismiss, 'e' to escalate
      </Text>
    </Box>
  );
};
```

#### 6.2 Interactive Agent Control

**Keyboard Controls for Workflow:**
```tsx
import { useInput } from 'ink';

const WorkflowControls: React.FC<{ workflow: WorkflowState }> = ({ workflow }) => {
  useInput((input, key) => {
    if (key.ctrl && input === 'c') {
      // Graceful shutdown
      workflow.requestShutdown();
    }

    if (key.return) {
      // Pause/resume workflow
      workflow.togglePause();
    }

    if (input === 'e') {
      // Manual escalate current error
      workflow.escalateError();
    }

    if (input === 'h') {
      // Request human intervention
      workflow.requestHumanIntervention();
    }

    if (input === 's') {
      // Skip current task
      workflow.skipCurrentTask();
    }

    if (input === 'r') {
      // Retry current task
      workflow.retryCurrentTask();
    }
  });

  return (
    <Box borderStyle="single" borderColor="blue" padding={1}>
      <Text bold>Controls:</Text>
      <Text>
        Ctrl+C - Shutdown | Enter - Pause/Resume | E - Escalate | H - Human | S - Skip | R - Retry
      </Text>
    </Box>
  );
};
```

#### 6.3 Real-Time Agent Output

**Streaming Agent Output:**
```tsx
import { useState, useEffect, useRef } from 'react';

const AgentOutput: React.FC<{ agentId: string }> = ({ agentId }) => {
  const [output, setOutput] = useState<string[]>([]);
  const [status, setStatus] = useState<string>('running');
  const outputRef = useRef(output);

  useEffect(() => {
    outputRef.current = output;
  }, [output]);

  useEffect(() => {
    const subscription = agentStream(agentId).subscribe({
      next: (message) => {
        setOutput((prev) => [...prev, message.content]);
      },
      complete: () => {
        setStatus('completed');
      },
      error: (error) => {
        setStatus('failed');
        setOutput((prev) => [...prev, `Error: ${error.message}`]);
      }
    });

    return () => subscription.unsubscribe();
  }, [agentId]);

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold>Agent Output ({agentId}):</Text>
        <Text color={status === 'completed' ? 'green' : status === 'failed' ? 'red' : 'yellow'}>
          [{status}]
        </Text>
      </Box>

      <Box flexDirection="column" borderStyle="single" padding={1}>
        {output.slice(-10).map((line, i) => (
          <Text key={i}>{line}</Text>
        ))}
      </Box>
    </Box>
  );
};

// Agent stream service
function agentStream(agentId: string) {
  return {
    subscribe: (observer) => {
      // Subscribe to agent output stream
      const socket = connectToAgentStream(agentId);

      socket.on('message', (data) => {
        observer.next({ content: data.message });
      });

      socket.on('complete', () => {
        observer.complete();
      });

      socket.on('error', (error) => {
        observer.error(error);
      });

      return {
        unsubscribe: () => socket.disconnect()
      };
    }
  };
}
```

#### 6.4 Multi-Agent Dashboard

**Comprehensive Dashboard:**
```tsx
const AgentDashboard: React.FC = () => {
  const [workflow, setWorkflow] = useState<WorkflowState | null>(null);
  const [selectedAgent, setSelectedAgent] = useState<string | null>(null);

  useEffect(() => {
    // Connect to workflow state
    const connection = connectToWorkflow();
    connection.on('stateUpdate', setWorkflow);
    return () => connection.disconnect();
  }, []);

  if (!workflow) {
    return <Text>Connecting to workflow...</Text>;
  }

  return (
    <Box flexDirection="column">
      {/* Header */}
      <Box marginBottom={1}>
        <Text bold color="green" inverse>
          Hawk Agent Dashboard
        </Text>
      </Box>

      {/* Workflow Overview */}
      <WorkflowOverview workflow={workflow} />

      {/* Active Agents */}
      <Box marginBottom={1}>
        <Text bold>Active Agents:</Text>
        <AgentGrid
          agents={workflow.agents}
          onSelectAgent={setSelectedAgent}
        />
      </Box>

      {/* Selected Agent Details */}
      {selectedAgent && (
        <AgentDetails
          agentId={selectedAgent}
          onClose={() => setSelectedAgent(null)}
        />
      )}

      {/* Controls */}
      <WorkflowControls workflow={workflow} />

      {/* Logs */}
      <Box marginTop={1}>
        <Text bold>Recent Logs:</Text>
        <LogStream logs={workflow.recentLogs} />
      </Box>
    </Box>
  );
};

const AgentGrid: React.FC<{
  agents: Agent[];
  onSelectAgent: (agentId: string) => void;
}> = ({ agents, onSelectAgent }) => {
  return (
    <Box flexDirection="column">
      {agents.map((agent) => (
        <AgentCard
          key={agent.id}
          agent={agent}
          onSelect={onSelectAgent}
        />
      ))}
    </Box>
  );
};

const AgentCard: React.FC<{
  agent: Agent;
  onSelect: (agentId: string) => void;
}> = ({ agent, onSelect }) => {
  return (
    <Box
      borderStyle="single"
      borderColor={agent.status === 'active' ? 'green' : 'gray'}
      padding={1}
      marginBottom={1}
      onPress={() => onSelect(agent.id)}
    >
      <Box justifyContent="space-between">
        <Text bold>{agent.name}</Text>
        <Text color={getStatusColor(agent.status)}>
          {agent.status}
        </Text>
      </Box>

      <Box>
        <Text dimColor>Task: {agent.currentTask}</Text>
      </Box>

      {agent.output && (
        <Box flexDirection="column">
          <Text dimColor>Latest Output:</Text>
          <Text>{agent.output.slice(-1)[0]}</Text>
        </Box>
      )}
    </Box>
  );
};
```

**Sources:**
- [I built a complex CLI tool using React (Ink), Zustand, and Redux](https://www.reddit.com/r/reactjs/comments/1pl0t4r/i_built_a_complex_cli_tool-using_react_ink/)
- [Exploring UIs in the terminal part 1: React/Ink](https://cekrem.github.io/posts/do-more-stuff-cli-tool-part-1/)

### State Management for Ink UI

**Using Zustand with Ink:**
```typescript
import create from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';

interface WorkflowStore {
  workflow: WorkflowState | null;
  selectedAgent: string | null;
  logs: LogEntry[];

  setWorkflow: (workflow: WorkflowState) => void;
  selectAgent: (agentId: string) => void;
  addLog: (log: LogEntry) => void;
}

const useWorkflowStore = create<WorkflowStore>()(
  subscribeWithSelector((set, get) => ({
    workflow: null,
    selectedAgent: null,
    logs: [],

    setWorkflow: (workflow) => set({ workflow }),

    selectAgent: (agentId) => set({ selectedAgent: agentId }),

    addLog: (log) => set((state) => ({
      logs: [...state.logs, log].slice(-100) // Keep last 100 logs
    }))
  }))
);

// Connect to backend workflow state
function connectStoreToBackend(store: WorkflowStore) {
  const socket = io('http://localhost:3000');

  socket.on('workflowUpdate', (workflow) => {
    store.setWorkflow(workflow);
  });

  socket.on('log', (log) => {
    store.addLog(log);
  });

  return () => socket.disconnect();
}
```

### Ink Integration Best Practices

1. **Separate UI from Logic:** Keep workflow logic separate from UI components
2. **Reactive State Management:** Use state management libraries (Zustand, Redux)
3. **Real-Time Updates:** WebSocket connections for live workflow state
4. **Responsive Design:** Handle terminal resize gracefully
5. **Keyboard Shortcuts:** Intuitive controls for workflow interaction
6. **Color Coding:** Use colors to indicate status and priority
7. **Progress Indicators:** Visual feedback for long-running operations

---

## 7. Recommendations for Hawk Agent Implementation

### Architecture Recommendations

#### 1. Hybrid Orchestration Approach
**Recommendation:** Combine Orchestrator pattern with Saga-based compensation.

**Rationale:**
- Orchestrator provides clear visibility and control
- Saga pattern handles complex error recovery and compensation
- Fits Hawk Agent's PRP pipeline requirements

**Implementation:**
```typescript
class HawkAgentOrchestrator {
  private sagaEngine: SagaEngine;
  private stateMachine: StateMachine<WorkflowState>;

  async executeWorkflow(prd: PRD): Promise<WorkflowResult> {
    // Define saga for PRP implementation
    const saga = new PRPImplementationSaga({
      workflow: this.stateMachine,
      compensationActions: {
        research: this.compensateResearch,
        create_prp: this.updatePRP,
        implement: this.addPRPAddendum,
        validate: this.escalateValidation
      }
    });

    // Execute saga with orchestration
    return await saga.execute(prd);
  }
}
```

#### 2. Redux-like Context Propagation
**Recommendation:** Implement Redux pattern for non-UI agent context management.

**Rationale:**
- Predictable state updates
- Time-travel debugging
- Clear data flow
- Easy state inspection

**Implementation:**
```typescript
// Central store for workflow state
const workflowStore = new WorkflowStore<WorkflowState>((state, action) => {
  switch (action.type) {
    case 'START_AGENT':
      return {
        ...state,
        activeAgents: [...state.activeAgents, action.agentId],
        context: { ...state.context, ...action.context }
      };
    case 'COMPLETE_AGENT':
      return {
        ...state,
        completedAgents: [...state.completedAgents, action.agentId],
        activeAgents: state.activeAgents.filter(id => id !== action.agentId)
      };
    case 'UPDATE_CONTEXT':
      return {
        ...state,
        context: { ...state.context, ...action.updates }
      };
    default:
      return state;
  }
});

// Agents access context through store
class Agent {
  constructor(private store: WorkflowStore) {}

  getContext(): AgentContext {
    return this.store.getState().context;
  }

  dispatch(action: Action) {
    this.store.dispatch(action);
  }
}
```

#### 3. Phantom Git with Event Sourcing
**Recommendation:** Combine phantom git with event sourcing for comprehensive state tracking.

**Rationale:**
- Phantom git provides file-level tracking
- Event sourcing provides workflow-level tracking
- Both support rollback and debugging
- Natural audit trail

**Implementation:**
```typescript
class PhantomGitWithEvents {
  private eventLog: EventLog;
  private gitRepo: GitRepository;

  async executeAction(action: AgentAction): Promise<ActionResult> {
    // Record event before execution
    this.eventLog.append({
      type: 'ACTION_STARTED',
      timestamp: Date.now(),
      action: action
    });

    try {
      // Execute action
      const result = await action.execute();

      // Commit to phantom git
      await this.gitRepo.commit(action.description, {
        files: result.modifiedFiles
      });

      // Record success event
      this.eventLog.append({
        type: 'ACTION_COMPLETED',
        timestamp: Date.now(),
        action: action,
        result: result
      });

      return result;
    } catch (error) {
      // Record failure event
      this.eventLog.append({
        type: 'ACTION_FAILED',
        timestamp: Date.now(),
        action: action,
        error: error
      });

      // Rollback phantom git
      await this.gitRepo.rollback();

      throw error;
    }
  }

  async getStateAt(timestamp: number): Promise<WorkflowState> {
    // Replay events up to timestamp
    const events = this.eventLog.getEventsBefore(timestamp);
    return this.replayState(events);
  }
}
```

#### 4. Progressive Escalation System
**Recommendation:** Implement the 5-level escalation path defined in PRD.

**Implementation:**
```typescript
class EscalationSystem {
  private levels: EscalationLevel[] = [
    {
      level: 1,
      name: 'implementer_retry',
      handler: new ImplementerRetryHandler()
    },
    {
      level: 2,
      name: 'root_cause_analysis',
      handler: new RootCauseAnalysisHandler()
    },
    {
      level: 3,
      name: 'fagan_inspection',
      handler: new FaganInspectionHandler()
    },
    {
      level: 4,
      name: 'independent_review',
      handler: new IndependentReviewHandler()
    },
    {
      level: 5,
      name: 'human_intervention',
      handler: new HumanInterventionHandler()
    }
  ];

  async handleFailure(
    error: AgentError,
    context: WorkflowContext
  ): Promise<Resolution> {
    let currentLevel = 0;

    while (currentLevel < this.levels.length) {
      const level = this.levels[currentLevel];
      const result = await level.handler.handle(error, context);

      if (result.resolved) {
        return result;
      }

      if (result.escalate) {
        currentLevel++;
      }
    }

    throw new EscalationExhaustedError();
  }
}
```

#### 5. Ink-Based Terminal UI
**Recommendation:** Implement comprehensive terminal UI using Ink.

**Features:**
- Real-time workflow progress
- Agent status dashboard
- Interactive controls (pause, resume, escalate)
- Streaming agent output
- Error display and resolution
- Log viewer

**Implementation:**
```typescript
const HawkAgentUI: React.FC = () => {
  const workflow = useWorkflowStore();
  const [selectedAgent, setSelectedAgent] = useState<string | null>(null);

  return (
    <Box flexDirection="column">
      <WorkflowHeader />
      <WorkflowProgress workflow={workflow} />
      <AgentDashboard
        agents={workflow.agents}
        onSelectAgent={setSelectedAgent}
      />
      {selectedAgent && (
        <AgentDetails agentId={selectedAgent} />
      )}
      <WorkflowControls />
      <LogViewer logs={workflow.logs} />
    </Box>
  );
};
```

### Technology Stack Recommendations

#### Core Framework: Temporal or Custom Implementation
**Recommendation:** Start with custom implementation using patterns from Temporal, consider migration if needed.

**Rationale:**
- Full control over agent lifecycle
- Tailored to Hawk Agent requirements
- Can adopt patterns without framework overhead
- Migrate to Temporal if durable execution needs grow

**Alternative:** Use Temporal directly if:
- Need massive scalability (1000+ concurrent workflows)
- Require multi-language support
- Want enterprise-grade durability guarantees

#### State Management: Redux Pattern
**Recommendation:** Implement Redux-like store for workflow state.

**Benefits:**
- Predictable state updates
- Time-travel debugging
- Easy state inspection
- Clear data flow

#### UI Framework: Ink
**Recommendation:** Use Ink for terminal UI.

**Benefits:**
- Familiar React patterns
- Rich component ecosystem
- Real-time updates
- Interactive controls

#### Workflow Definition: YAML DSL
**Recommendation:** Define workflows as YAML DSL for readability and maintainability.

**Benefits:**
- Human-readable
- Easy to modify
- Version control friendly
- Can be edited by non-developers

### Implementation Roadmap

#### Phase 1: Core Orchestration
1. Implement Orchestrator pattern
2. Create Redux-like store
3. Define workflow state machine
4. Implement basic agent lifecycle

#### Phase 2: Error Handling
1. Implement error categorization
2. Create escalation system
3. Add retry logic with backoff
4. Implement human-in-the-loop

#### Phase 3: State Persistence
1. Implement phantom git
2. Add event sourcing
3. Create state reconstruction
4. Implement rollback mechanisms

#### Phase 4: UI Integration
1. Create Ink components
2. Connect to workflow state
3. Add interactive controls
4. Implement real-time updates

#### Phase 5: Advanced Features
1. Add Saga pattern for complex workflows
2. Implement parallel agent execution
3. Add workflow composition DSL
4. Create workflow templates

### Best Practices Summary

1. **Start Simple:** Begin with sequential orchestration, add complexity as needed
2. **Fail Fast:** Detect errors early and escalate appropriately
3. **Observability First:** Comprehensive logging and tracing from day one
4. **State is King:** Design state management carefully, it's the foundation
5. **Test Escalation Paths:** Verify all escalation levels work correctly
6. **Human-in-the-Loop:** Make human intervention easy and clear
7. **Version Everything:** Track workflows, PRPs, and state changes
8. **Document Decisions:** Record why architectural decisions were made

---

## Sources Summary

### Workflow Orchestration Patterns
- [AI Agent Orchestration Patterns - Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [Agent Workflow Patterns: Essential Guide to AI Orchestration in 2025](https://www.fixtergeek.com/blog/Agent-Workflow-Patterns:-The-Essential-Guide-to-AI-Orchestration-in-2025_5BQ)
- [AWS Workflow Orchestration Agents](https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-patterns/workflow-orchestration-agents.html)
- [AgentX: Orchestrating Robust Agentic Workflows](https://arxiv.org/html/2509.07595v1)

### Saga Pattern
- [Mastering Saga Patterns for Distributed Transactions in Microservices](https://temporal.io/blog/mastering-saga-patterns-for-distributed-transactions-in-microservices)
- [Saga Pattern - microservices.io](https://microservices.io/patterns/data/saga.html)
- [Saga Design Pattern - Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/patterns/saga)
- [Implement Saga Patterns in Microservices with NestJS and Kafka](https://thenewstack.io/implement-saga-patterns-in-microservices-with-nestjs-and-kafka/)

### Context Propagation
- [A Redux-Inspired Backend](https://medium.com/resolvejs/redux-redux-backend-ebcfc79bbbea)
- [Can Redux be Used on the Server?](https://blog.bitsrc.io/can-redux-be-used-on-the-server-e2d3ecbf7ee4)
- [Redux and it's relation to CQRS](https://github.com/reduxjs/redux/issues/351)
- [Event Sourcing - Martin Fowler](https://martinfowler.com/eaaDev/EventSourcing.html)

### Tools and Frameworks
- [Orchestrating Multi-Step Agents: Temporal/Dagster/LangGraph Patterns](https://kinde.com/learn/ai-for-software-engineering/ai-devops/orchestrating-multi-step-agents-temporal-dagster-langgraph-patterns-for-long-running-work/)
- [Temporal Workflow Orchestration Patterns](https://mcpmarket.com/zh/tools/skills/temporal-workflow-orchestration-patterns)
- [LangGraph State Machines: Managing Complex Agent Task Flows](https://dev.to/jamesli/langgraph-state-machines-managing-complex-agent-task-flows-in-production-36f4)
- [Prefect AI Teams](https://www.prefect.io/ai-teams)
- [A Declarative Language for Building And Orchestrating Agents](https://arxiv.org/html/2512.19769)

### Error Handling
- [Exception Handling and Recovery Pattern - Agentic Design Patterns](https://github.com/ginobefun/agentic-design-patterns-cn/blob/main/15-Chapter-12-Exception-Handling-and-Recovery.md)
- [The AI Agent Framework Landscape in 2025](https://medium.com/@hieutrantrung.it/the-ai-agent-framework-landscape-in-2025-what-changed-and-what-matters-3cd9b07ef2c3)
- [Best Practices for Building Reliable AI Agents (2025)](https://www.uipath.com/blog/ai/agent-builder-best-practices)
- [5 Recovery Strategies for Multi-Agent LLM Failures](https://www.newline.co/@zaoyang/5-recovery-strategies-for-multi-agent-llm-failures--673fe4c4)

### Ink Framework
- [Ink GitHub Repository](https://github.com/vadimdemedes/ink)
- [How to use ink-ui to Build Beautiful CLI Tools Like OpenAI's Codex](https://levelup.gitconnected.com/how-to-use-ink-ui-to-build-beautiful-cli-tools-like-openais-codex-d793c752da5f)
- [I built a complex CLI tool using React (Ink), Zustand, and Redux](https://www.reddit.com/r/reactjs/comments/1pl0t4r/i_built_a_complex_cli_tool-using_react_ink/)
- [Exploring UIs in the terminal part 1: React/Ink](https://cekrem.github.io/posts/do-more-stuff-cli-tool-part-1/)

---

## Conclusion

This research report provides a comprehensive foundation for implementing the Hawk Agent workflow composition system. The key takeaways are:

1. **Workflow Orchestration:** Multiple patterns exist (sequential, concurrent, group chat, handoff, orchestrator) - use the right pattern for the right situation
2. **Saga Pattern:** Ideal for long-running agent workflows with complex error recovery and compensation
3. **Context Propagation:** Redux-like patterns work well for non-UI agent systems, providing predictable state management
4. **Tools and Frameworks:** Temporal, LangGraph, Prefect, and Dagster each have strengths - consider custom implementation first
5. **Error Handling:** Progressive escalation with clear paths from automatic retry to human intervention
6. **Ink Integration:** Provides excellent terminal UI for monitoring and controlling agent workflows

The Hawk Agent PRD's requirements are well-supported by these patterns and tools. The recommended approach combines the best of these technologies while maintaining flexibility for future evolution.
