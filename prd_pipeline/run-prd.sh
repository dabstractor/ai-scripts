#!/usr/bin/env zsh

# --- 1. Environment Handling ---
unalias() { builtin unalias "$@" 2>/dev/null || true }

# Load your custom environment
[[ -f ~/.config/zsh/functions.zsh ]] && source ~/.config/zsh/functions.zsh
[[ -f ~/.config/zsh/aliases.zsh ]] && source ~/.config/zsh/aliases.zsh

# Ensure aliases are expanded in the script
setopt aliases

# --- 2. Parameter Parsing ---
SCOPE="${SCOPE:-task}"  # Default to task-level
START_PHASE=1
START_MS=1
START_TASK=1
START_SUBTASK=1
PARALLEL_RESEARCH="${PARALLEL_RESEARCH:-false}"  # Optional parallel research for next item
ONLY_VALIDATE="${ONLY_VALIDATE:-false}" # Run only the validation step
MANUAL_START=false

while getopts "s:p:m:t:u:rv-:" opt; do
  case $opt in
    s) SCOPE=$OPTARG ;;
    p) START_PHASE=$OPTARG; MANUAL_START=true ;;
    m) START_MS=$OPTARG; MANUAL_START=true ;;
    t) START_TASK=$OPTARG; MANUAL_START=true ;;
    u) START_SUBTASK=$OPTARG; MANUAL_START=true ;;
    r) PARALLEL_RESEARCH=true ;;
    v) ONLY_VALIDATE=true ;;
    -)
      case "${OPTARG}" in
        scope)       SCOPE="${!OPTIND}"; OPTIND=$(( OPTIND + 1 )) ;;
        scope=*)     SCOPE="${OPTARG#*=}" ;;
        phase)       START_PHASE="${!OPTIND}"; OPTIND=$(( OPTIND + 1 )); MANUAL_START=true ;;
        phase=*)     START_PHASE="${OPTARG#*=}"; MANUAL_START=true ;;
        milestone)   START_MS="${!OPTIND}"; OPTIND=$(( OPTIND + 1 )); MANUAL_START=true ;;
        milestone=*) START_MS="${OPTARG#*=}"; MANUAL_START=true ;;
        task)        START_TASK="${!OPTIND}"; OPTIND=$(( OPTIND + 1 )); MANUAL_START=true ;;
        task=*)      START_TASK="${OPTARG#*=}"; MANUAL_START=true ;;
        subtask)     START_SUBTASK="${!OPTIND}"; OPTIND=$(( OPTIND + 1 )); MANUAL_START=true ;;
        subtask=*)   START_SUBTASK="${OPTARG#*=}"; MANUAL_START=true ;;
        parallel-research) PARALLEL_RESEARCH=true ;;
        validate)    ONLY_VALIDATE=true ;;
        *) print "Usage: $0 [--scope=phase|milestone|task|subtask] [--phase=N] [--milestone=N] [--task=N] [--subtask=N] [--parallel-research] [--validate]"; exit 1 ;;
      esac ;;
    *) print "Usage: $0 [-s phase|milestone|task|subtask] [-p phase_number] [-m milestone_number] [-t task_number] [-u subtask_number] [-r] [-v]
   Or: $0 [--scope=phase|milestone|task|subtask] [--phase=N] [--milestone=N] [--task=N] [--subtask=N] [--parallel-research] [--validate]"; exit 1 ;;
  esac
done

# Validate scope
case $SCOPE in
  phase|milestone|task|subtask) ;;
  *) print -P "%F{red}[ERROR]%f Invalid scope: '$SCOPE'. Must be: phase, milestone, task, or subtask"; exit 1 ;;
esac

# --- 3. Configuration ---
AGENT="${AGENT:-glp}"
BREAKDOWN_AGENT="${BREAKDOWN_AGENT:-$AGENT}"
TASKS_FILE="${TASKS_FILE:-tasks.json}"
PRD_FILE="${PRD_FILE:-PRD.md}"
PLAN_DIR="${PLAN_DIR:-plan}"

# Auto-resume logic
if [[ "$MANUAL_START" == "false" && -f "$TASKS_FILE" ]]; then
    NEXT_ITEM=$(tsk next -s "$SCOPE" 2>/dev/null)
    if [[ -n "$NEXT_ITEM" ]]; then
        print -P "%F{cyan}[RESUME]%f Auto-resuming from: %F{yellow}$NEXT_ITEM%f"

        # Parse P#
        if [[ $NEXT_ITEM =~ P([0-9]+) ]]; then
            START_PHASE=${match[1]}
        fi

        # Parse M#
        if [[ $NEXT_ITEM =~ M([0-9]+) ]]; then
             START_MS=${match[1]}
        fi

        # Parse T#
        if [[ $NEXT_ITEM =~ T([0-9]+) ]]; then
             START_TASK=${match[1]}
        fi

        # Parse S#
        if [[ $NEXT_ITEM =~ S([0-9]+) ]]; then
             START_SUBTASK=${match[1]}
        fi
    fi
fi

# --- 3a. Graceful Shutdown Handling ---
SHUTDOWN_REQUESTED=false
FORCE_SHUTDOWN=false
CURRENT_CMD_PID=""

handle_sigint() {
    if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
        print -P "\n%F{red}[ABORT]%f Second interrupt received. Forcing immediate exit..."
        FORCE_SHUTDOWN=true
        # Force kill current command and background research
        [[ -n "$CURRENT_CMD_PID" ]] && kill -9 $CURRENT_CMD_PID 2>/dev/null
        [[ -n "$RESEARCH_PID" ]] && kill -9 $RESEARCH_PID 2>/dev/null
        exit 130
    else
        print -P "\n%F{yellow}[SHUTDOWN]%f Graceful shutdown requested. Will exit after current item completes."
        print -P "%F{yellow}[SHUTDOWN]%f Press Ctrl+C again to force immediate exit."
        SHUTDOWN_REQUESTED=true
        # Don't kill processes here - let poll loop detect shutdown and exit cleanly
    fi
}

trap handle_sigint SIGINT

# Check if shutdown was requested (call after each item completes)
check_shutdown() {
    if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
        print -P "%F{yellow}[SHUTDOWN]%f Shutdown requested. Exiting gracefully..."
        # Kill any background research process
        [[ -n "$RESEARCH_PID" ]] && kill -TERM $RESEARCH_PID 2>/dev/null && print -P "%F{yellow}[SHUTDOWN]%f Terminated background research process."
        exit 0
    fi
}

read -r -d '' PRP_README <<EOF
# Product Requirement Prompt (PRP) Concept

"Over-specifying what to build while under-specifying the context, and how to build it, is why so many AI-driven coding attempts stall at 80%. A Product Requirement Prompt (PRP) fixes that by fusing the disciplined scope of a classic Product Requirements Document (PRD) with the “context-is-king” mindset of modern prompt engineering."

## What is a PRP?

Product Requirement Prompt (PRP)
A PRP is a structured prompt that supplies an AI coding agent with everything it needs to deliver a vertical slice of working software—no more, no less.

### How it differs from a PRD

A traditional PRD clarifies what the product must do and why customers need it, but deliberately avoids how it will be built.

A PRP keeps the goal and justification sections of a PRD yet adds three AI-critical layers:

### Context

- Precise file paths and content, library versions and library context, code snippets examples. LLMs generate higher-quality code when given direct, in-prompt references instead of broad descriptions. Usage of a ai_docs/ directory to pipe in library and other docs.

### Implementation Details and Strategy

- In contrast of a traditional PRD, a PRP explicitly states how the product will be built. This includes the use of API endpoints, test runners, or agent patterns (ReAct, Plan-and-Execute) to use. Usage of typehints, dependencies, architectural patterns and other tools to ensure the code is built correctly.

### Validation Gates

- Deterministic checks such as pytest, ruff, or static type passes “Shift-left” quality controls catch defects early and are cheaper than late re-work.
  Example: Each new funtion should be individaully tested, Validation gate = all tests pass.

### PRP Layer Why It Exists

- The PRP folder is used to prepare and pipe PRPs to the agentic coder.

## Why context is non-negotiable

Large-language-model outputs are bounded by their context window; irrelevant or missing context literally squeezes out useful tokens

The industry mantra “Garbage In → Garbage Out” applies doubly to prompt engineering and especially in agentic engineering: sloppy input yields brittle code

## In short

A PRP is PRD + curated codebase intelligence + agent/runbook—the minimum viable packet an AI needs to plausibly ship production-ready code on the first pass.

The PRP can be small and focusing on a single task or large and covering multiple tasks.
The true power of PRP is in the ability to chain tasks together in a PRP to build, self-validate and ship complex features.
EOF

read -r -d '' TASK_BREAKDOWN_SYSTEM_PROMPT <<EOF || true
# LEAD TECHNICAL ARCHITECT & PROJECT SYNTHESIZER

> **ROLE:** Act as a Lead Technical Architect and Project Management Synthesizer.
> **CONTEXT:** You represent the rigorous, unified consensus of a senior panel (Security, DevOps, Backend, Frontend, QA).
> **GOAL:** Validate the PRD through research, document findings, and decompose the PRD into a strict hierarchy: \`Phase\` > \`Milestone\` > \`Task\` > \`Subtask\`.

---

## HIERARCHY DEFINITIONS

*   **PHASE:** Project-scope goals (e.g., MVP, V1.0). *Weeks to months.*
*   **MILESTONE:** Key objectives within a Phase. *1 to 12 weeks.*
*   **TASK:** Complete features within a Milestone. *Days to weeks.*
*   **SUBTASK:** Atomic implementation steps. **0.5, 1, or 2 Story Points (SP).** (Max 2 SP, do not break subtasks down further than 2 SP unless required).

---

## CRITICAL CONSTRAINTS & STANDARD OF WORK (SOW)

### 1. RESEARCH-DRIVEN ARCHITECTURE (NEW PRIORITY)
*   **VALIDATE BEFORE BREAKING DOWN:** You cannot plan what you do not understand.
*   **SPAWN SUBAGENTS:** Use your tools to spawn agents to research the codebase and external documentation *before* defining the hierarchy.
*   **REALITY CHECK:** Verify that the PRD's requests match the current codebase state (e.g., don't plan a React hook if the project is vanilla JS).
*   **PERSISTENCE:** You must store architectural findings in \`$PLAN_DIR/architecture/\` so the downstream PRP (Product Requirement Prompt) agents have access to them.

### 2. COHERENCE & CONTINUITY
*   **NO VACUUMS:** You must ensure architectural flow. Subtasks must not exist in isolation.
*   **EXPLICIT HANDOFFS:** If \`Subtask A\` defines a schema, \`Subtask B\` must be explicitly instructed to consume that schema.
*   **STRICT REFERENCES:** Reference specific file paths, variable names, or API endpoints confirmed during your **Research Phase**.

### 3. IMPLICIT TDD & QUALITY
*   **DO NOT** create subtasks for "Write Tests."
*   **IMPLIED WORKFLOW:** Assume every subtask implies: *"Write the failing test -> Implement the code -> Pass the test."*
*   **DEFINITION OF DONE:** Code is not complete without tests.

### 4. THE "CONTEXT SCOPE" BLINDER
For every Subtask, the \`context_scope\` must be a **strict set of instructions** for a developer who cannot see the rest of the project. It must define:
*   **INPUT:** What specific data/interfaces are available from previous subtasks?
*   **OUTPUT:** What exact interface does this subtask expose?
*   **MOCKING:** What external services must be mocked to keep this subtask isolated?

---

## PROCESS

ULTRATHINK & PLAN

1.  **ANALYZE** the attached or referenced PRD.
2.  **RESEARCH (SPAWN & VALIDATE):**
    *   **Spawn** subagents to map the codebase and verify PRD feasibility.
    *   **Spawn** subagents to find external documentation for new tech.
    *   **Store** findings in \`$PLAN_DIR/architecture/\` (e.g., \`system_context.md\`, \`external_deps.md\`).
3.  **DETERMINE** the highest level of scope (Phase, Milestone, or Task).
4.  **DECOMPOSE** strictly downwards to the Subtask level, using your research to populate the \`context_scope\`.

---

## OUTPUT FORMAT

**CONSTRAINT:** You MUST write the JSON to the file \`./$TASKS_FILE\` (in the CURRENT WORKING DIRECTORY - do NOT search for or use any other tasks.json files from other projects/directories).

Do NOT output JSON to the conversation - WRITE IT TO THE FILE at path \`./$TASKS_FILE\`.

Use your file writing tools to create \`./$TASKS_FILE\` with this structure:

\`\`\`json
{
  "backlog": [
    {
      "type": "Phase",
      "id": "P[#]",
      "title": "Phase Title",
      "status": "Planned | Researching | Ready | Implementing | Complete | Failed",
      "description": "High level goal.",
      "milestones": [
        {
          "type": "Milestone",
          "id": "P[#].M[#]",
          "title": "Milestone Title",
          "status": "Planned",
          "description": "Key objective.",
          "tasks": [
            {
              "type": "Task",
              "id": "P[#].M[#].T[#]",
              "title": "Task Title",
              "status": "Planned",
              "description": "Feature definition.",
              "subtasks": [
                {
                  "type": "Subtask",
                  "id": "P[#].M[#].T[#].S[#]",
                  "title": "Subtask Title",
                  "status": "Planned",
                  "story_points": 1,
                  "dependencies": ["ID of prerequisite subtask"],
                  "context_scope": "CONTRACT DEFINITION:\n1. RESEARCH NOTE: [Finding from $PLAN_DIR/architecture/ regarding this feature].\n2. INPUT: [Specific data structure/variable] from [Dependency ID].\n3. LOGIC: Implement [PRD Section X] logic. Mock [Service Y] for isolation.\n4. OUTPUT: Return [Result Object/Interface] for consumption by [Next Subtask ID]."
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
\`\`\`
EOF

read -r -d '' TASK_BREAKDOWN_PROMPT <<EOF
# PROJECT INITIATION

**INPUT DOCUMENTATION (PRD):**
$(cat "$PRD_FILE")

**INSTRUCTIONS:**
1.  **Analyze** the PRD above.
2.  **Spawn** subagents immediately to research the current codebase state and external documentation. validate that the PRD is feasible and identify architectural patterns to follow.
3.  **Store** your high-level research findings in the \`$PLAN_DIR/architecture/\` directory. This is critical: the downstream PRP agents will rely on this documentation to generate implementation plans.
4.  **Decompose** the project into the JSON Backlog format defined in the System Prompt. Ensure your breakdown is grounded in the reality of the research you just performed.
5.  **CRITICAL: Write the JSON to \`./$TASKS_FILE\` (current working directory) using your file writing tools.** Do NOT output the JSON to the conversation. Do NOT search for or modify any existing tasks.json files in other directories. Create a NEW file at \`./$TASKS_FILE\`. The file MUST exist when you are done.
EOF

read -r -d '' PRP_CREATE_PROMPT <<EOF
# Create PRP for Work Item

## Work Item Information

**ITEM TITLE**: <item_title>
**ITEM DESCRIPTION**: <item_description>

You are creating a PRP (Product Requirement Prompt) for this specific work item.

## PRP Creation Mission

Create a comprehensive PRP that enables **one-pass implementation success** through systematic research and context curation.


**Critical Understanding**:
You must start by reading and understanding the prp concepts in the attached readme
Be aware that the executing AI agent only receives:
- The PRP content you create
- Its training data knowledge
- Access to codebase files (but needs guidance on which ones)


**Therefore**: Your research and context curation directly determines implementation success. Incomplete context = implementation failure.

## Research Process

> During the research process, create clear tasks and spawn as many agents and subagents as needed using the batch tools. The deeper research we do here the better the PRP will be. We optimize for chance of success, not for speed.

1. **Codebase Analysis in depth**
   - Create clear todos and spawn subagents to search the codebase for similar features/patterns. Think hard and plan your approach
   - Identify all the necessary files to reference in the PRP
   - Note all existing conventions to follow
   - Check existing test patterns for validation approach, if none are found plan to find a new one
   - Use the batch tools to spawn subagents to search the codebase for similar features/patterns

2. **Internal Research at scale**
   - Use relevant research and plan information in the plan/architecture directory
   - Consider the scope of this work item within the overall PRD. Respect the boundaries of scope of implementation. Ensure cohesion across
   previously completed work items and guard against harming future work items in your plan

3. **External Research at scale**
   - Create clear todos and spawn subagents with instructions to do deep research for similar features/patterns online and include urls to documentation and examples
   - Library documentation (include specific URLs)
   - Store all research in the work item's research/ subdirectory and reference critical pieces of documentation in the PRP with clear
   reasoning and instructions
   - Implementation examples (GitHub/StackOverflow/blogs)
   - New validation approach none found in existing codebase and user confirms they would like one added
   - Best practices and common pitfalls found during research
   - Use the batch tools to spawn subagents to search for similar features/patterns online and include urls to documentation and examples

4. **User Clarification**
   - Ask for clarification if you need it
   - If no testing framework is found, ask the user if they would like to set one up
   - If a fundamental misalignemnt of objectives across work items is detected, halt and produce a thorough explanation of the problem at a 10th grade level

## PRP Generation Process

### Step 1: Review Template

Use the attached template structure - it contains all necessary sections and formatting.

### Step 2: Context Completeness Validation

Before writing, apply the **"No Prior Knowledge" test** from the template:
_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_

### Step 3: Research Integration

Transform your research findings into the template sections:

**Goal Section**: Use research to define specific, measurable Feature Goal and concrete Deliverable based on the work item title and description
**Context Section**: Populate YAML structure with your research findings - specific URLs, file patterns, gotchas
**Implementation Tasks**: Create dependency-ordered tasks using information-dense keywords from codebase analysis
**Validation Gates**: Use project-specific validation commands that you've verified work in this codebase

### Step 4: Information Density Standards

Ensure every reference is **specific and actionable**:

- URLs include section anchors, not just domain names
- File references include specific patterns to follow, not generic mentions
- Task specifications include exact naming conventions and placement
- Validation commands are project-specific and executable

### Step 5: ULTRATHINK Before Writing

After research completion, create comprehensive PRP writing plan using TodoWrite tool:

- Plan how to structure each template section with your research findings
- Identify gaps that need additional research
- Create systematic approach to filling template with actionable context

## Output

Store the PRP and documentation at the path specified in your instructions.

## PRP Quality Gates

### Context Completeness Check

- [ ] Passes "No Prior Knowledge" test from template
- [ ] All YAML references are specific and accessible
- [ ] Implementation tasks include exact naming and placement guidance
- [ ] Validation commands are project-specific and verified working

### Template Structure Compliance

- [ ] All required template sections completed
- [ ] Goal section has specific Feature Goal, Deliverable, Success Definition
- [ ] Implementation Tasks follow dependency ordering
- [ ] Final Validation Checklist is comprehensive

### Information Density Standards

- [ ] No generic references - all are specific and actionable
- [ ] File patterns point at specific examples to follow
- [ ] URLs include section anchors for exact guidance
- [ ] Task specifications use information-dense keywords from codebase

## Success Metrics

**Confidence Score**: Rate 1-10 for one-pass implementation success likelihood

**Validation**: The completed PRP should enable an AI agent unfamiliar with the codebase to implement the feature successfully using only the PRP content and codebase access.
<PRP-README>
$PRP_README
</PRP-README>

<PRP-TEMPLATE>
name: "Base PRP Template - Implementation-Focused with Precision Standards"
description: |

---

## Goal

**Feature Goal**: [Specific, measurable end state of what needs to be built]

**Deliverable**: [Concrete artifact - API endpoint, service class, integration, etc.]

**Success Definition**: [How you'll know this is complete and working]

## User Persona (if applicable)

**Target User**: [Specific user type - developer, end user, admin, etc.]

**Use Case**: [Primary scenario when this feature will be used]

**User Journey**: [Step-by-step flow of how user interacts with this feature]

**Pain Points Addressed**: [Specific user frustrations this feature solves]

## Why

- [Business value and user impact]
- [Integration with existing features]
- [Problems this solves and for whom]

## What

[User-visible behavior and technical requirements]

### Success Criteria

- [ ] [Specific measurable outcomes]

## All Needed Context

### Context Completeness Check

_Before writing this PRP, validate: "If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_

### Documentation & References

\`\`\`yaml
# MUST READ - Include these in your context window
- url: [Complete URL with section anchor]
  why: [Specific methods/concepts needed for implementation]
  critical: [Key insights that prevent common implementation errors]

- file: [exact/path/to/pattern/file.py]
  why: [Specific pattern to follow - class structure, error handling, etc.]
  pattern: [Brief description of what pattern to extract]
  gotcha: [Known constraints or limitations to avoid]

- docfile: [$PLAN_DIR/ai_docs/domain_specific.md]
  why: [Custom documentation for complex library/integration patterns]
  section: [Specific section if document is large]
\`\`\`

### Current Codebase tree (run \`tree\` in the root of the project) to get an overview of the codebase

\`\`\`bash

\`\`\`

### Desired Codebase tree with files to be added and responsibility of file

\`\`\`bash

\`\`\`

### Known Gotchas of our codebase & Library Quirks

\`\`\`python
# CRITICAL: [Library name] requires [specific setup]
# Example: FastAPI requires async functions for endpoints
# Example: This ORM doesn't support batch inserts over 1000 records
\`\`\`

## Implementation Blueprint

### Data models and structure

Create the core data models, we ensure type safety and consistency.

\`\`\`python
Examples:
 - orm models
 - pydantic models
 - pydantic schemas
 - pydantic validators

\`\`\`

### Implementation Tasks (ordered by dependencies)

\`\`\`yaml
Task 1: CREATE src/models/{domain}_models.py
  - IMPLEMENT: {SpecificModel}Request, {SpecificModel}Response Pydantic models
  - FOLLOW pattern: src/models/existing_model.py (field validation approach)
  - NAMING: CamelCase for classes, snake_case for fields
  - PLACEMENT: Domain-specific model file in src/models/

Task 2: CREATE src/services/{domain}_service.py
  - IMPLEMENT: {Domain}Service class with async methods
  - FOLLOW pattern: src/services/database_service.py (service structure, error handling)
  - NAMING: {Domain}Service class, async def create_*, get_*, update_*, delete_* methods
  - DEPENDENCIES: Import models from Task 1
  - PLACEMENT: Service layer in src/services/

Task 3: CREATE src/tools/{action}_{resource}.py
  - IMPLEMENT: MCP tool wrapper calling service methods
  - FOLLOW pattern: src/tools/existing_tool.py (FastMCP tool structure)
  - NAMING: snake_case file name, descriptive tool function name
  - DEPENDENCIES: Import service from Task 2
  - PLACEMENT: Tool layer in src/tools/

Task 4: MODIFY src/main.py or src/server.py
  - INTEGRATE: Register new tool with MCP server
  - FIND pattern: existing tool registrations
  - ADD: Import and register new tool following existing pattern
  - PRESERVE: Existing tool registrations and server configuration

Task 5: CREATE src/services/tests/test_{domain}_service.py
  - IMPLEMENT: Unit tests for all service methods (happy path, edge cases, error handling)
  - FOLLOW pattern: src/services/tests/test_existing_service.py (fixture usage, assertion patterns)
  - NAMING: test_{method}_{scenario} function naming
  - COVERAGE: All public methods with positive and negative test cases
  - PLACEMENT: Tests alongside the code they test

Task 6: CREATE src/tools/tests/test_{action}_{resource}.py
  - IMPLEMENT: Unit tests for MCP tool functionality
  - FOLLOW pattern: src/tools/tests/test_existing_tool.py (MCP tool testing approach)
  - MOCK: External service dependencies
  - COVERAGE: Tool input validation, success responses, error handling
  - PLACEMENT: Tool tests in src/tools/tests/
\`\`\`

### Implementation Patterns & Key Details

\`\`\`python
# Show critical patterns and gotchas - keep concise, focus on non-obvious details

# Example: Service method pattern
async def {domain}_operation(self, request: {Domain}Request) -> {Domain}Response:
    # PATTERN: Input validation first (follow src/services/existing_service.py)
    validated = self.validate_request(request)

    # GOTCHA: [Library-specific constraint or requirement]
    # PATTERN: Error handling approach (reference existing service pattern)
    # CRITICAL: [Non-obvious requirement or configuration detail]

    return {Domain}Response(status="success", data=result)

# Example: MCP tool pattern
@app.tool()
async def {tool_name}({parameters}) -> str:
    # PATTERN: Tool validation and service delegation (see src/tools/existing_tool.py)
    # RETURN: JSON string with standardized response format
\`\`\`

### Integration Points

\`\`\`yaml
DATABASE:
  - migration: "Add column 'feature_enabled' to users table"
  - index: "CREATE INDEX idx_feature_lookup ON users(feature_id)"

CONFIG:
  - add to: config/settings.py
  - pattern: "FEATURE_TIMEOUT = int(os.getenv('FEATURE_TIMEOUT', '30'))"

ROUTES:
  - add to: src/api/routes.py
  - pattern: "router.include_router(feature_router, prefix='/feature')"
\`\`\`

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

\`\`\`bash
# Run after each file creation - fix before proceeding
ruff check src/{new_files} --fix     # Auto-format and fix linting issues
mypy src/{new_files}                 # Type checking with specific files
ruff format src/{new_files}          # Ensure consistent formatting

# Project-wide validation
ruff check src/ --fix
mypy src/
ruff format src/

# Expected: Zero errors. If errors exist, READ output and fix before proceeding.
\`\`\`

### Level 2: Unit Tests (Component Validation)

\`\`\`bash
# Test each component as it's created
uv run pytest src/services/tests/test_{domain}_service.py -v
uv run pytest src/tools/tests/test_{action}_{resource}.py -v

# Full test suite for affected areas
uv run pytest src/services/tests/ -v
uv run pytest src/tools/tests/ -v

# Coverage validation (if coverage tools available)
uv run pytest src/ --cov=src --cov-report=term-missing

# Expected: All tests pass. If failing, debug root cause and fix implementation.
\`\`\`

### Level 3: Integration Testing (System Validation)

\`\`\`bash
# Service startup validation
uv run python main.py &
sleep 3  # Allow startup time

# Health check validation
curl -f http://localhost:8000/health || echo "Service health check failed"

# Feature-specific endpoint testing
curl -X POST http://localhost:8000/{your_endpoint} \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}' \
  | jq .  # Pretty print JSON response

# MCP server validation (if MCP-based)
# Test MCP tool functionality
echo '{"method": "tools/call", "params": {"name": "{tool_name}", "arguments": {}}}' | \
  uv run python -m src.main

# Database validation (if database integration)
# Verify database schema, connections, migrations
psql $DATABASE_URL -c "SELECT 1;" || echo "Database connection failed"

# Expected: All integrations working, proper responses, no connection errors
\`\`\`

### Level 4: Creative & Domain-Specific Validation

\`\`\`bash
# MCP Server Validation Examples:

# Playwright MCP (for web interfaces)
playwright-mcp --url http://localhost:8000 --test-user-journey

# Docker MCP (for containerized services)
docker-mcp --build --test --cleanup

# Database MCP (for data operations)
database-mcp --validate-schema --test-queries --check-performance

# Custom Business Logic Validation
# [Add domain-specific validation commands here]

# Performance Testing (if performance requirements)
ab -n 100 -c 10 http://localhost:8000/{endpoint}

# Security Scanning (if security requirements)
bandit -r src/

# Load Testing (if scalability requirements)
# wrk -t12 -c400 -d30s http://localhost:8000/{endpoint}

# API Documentation Validation (if API endpoints)
# swagger-codegen validate -i openapi.json

# Expected: All creative validations pass, performance meets requirements
\`\`\`

## Final Validation Checklist

### Technical Validation

- [ ] All 4 validation levels completed successfully
- [ ] All tests pass: \`uv run pytest src/ -v\`
- [ ] No linting errors: \`uv run ruff check src/\`
- [ ] No type errors: \`uv run mypy src/\`
- [ ] No formatting issues: \`uv run ruff format src/ --check\`

### Feature Validation

- [ ] All success criteria from "What" section met
- [ ] Manual testing successful: [specific commands from Level 3]
- [ ] Error cases handled gracefully with proper error messages
- [ ] Integration points work as specified
- [ ] User persona requirements satisfied (if applicable)

### Code Quality Validation

- [ ] Follows existing codebase patterns and naming conventions
- [ ] File placement matches desired codebase tree structure
- [ ] Anti-patterns avoided (check against Anti-Patterns section)
- [ ] Dependencies properly managed and imported
- [ ] Configuration changes properly integrated

### Documentation & Deployment

- [ ] Code is self-documenting with clear variable/function names
- [ ] Logs are informative but not verbose
- [ ] Environment variables documented if new ones added

---

## Anti-Patterns to Avoid

- ❌ Don't create new patterns when existing ones work
- ❌ Don't skip validation because "it should work"
- ❌ Don't ignore failing tests - fix them
- ❌ Don't use sync functions in async context
- ❌ Don't hardcode values that should be config
- ❌ Don't catch all exceptions - be specific
</PRP-TEMPLATE>
EOF


read -r -d '' PRP_EXECUTE_PROMPT <<EOF
# Execute BASE PRP

## PRP File: (path provided below)

## Mission: One-Pass Implementation Success

PRPs enable working code on the first attempt through:

- **Context Completeness**: Everything needed, nothing guessed
- **Progressive Validation**: 4-level gates catch errors early
- **Pattern Consistency**: Follow existing codebase approaches
- Read the attached README to understand PRP concepts

**Your Goal**: Transform the PRP into working code that passes all validation gates.

## Execution Process

1. **Load PRP (CRITICAL FIRST STEP)**
   - **ACTION**: Use the \`Read\` tool to read the PRP file at the path provided in the instructions below.
   - You MUST read this file before doing anything else. It contains your instructions.
   - Absorb all context, patterns, requirements and gather codebase intelligence
   - Use the provided documentation references and file patterns, consume the right documentation before the appropriate todo/task
   - Trust the PRP's context and guidance - it's designed for one-pass success
   - If needed do additional codebase exploration and research as needed

2. **ULTRATHINK & Plan**
   - Create comprehensive implementation plan following the PRP's task order
   - Break down into clear todos using TodoWrite tool
   - Use subagents for parallel work when beneficial (always create prp inspired prompts for subagents when used)
   - Follow the patterns referenced in the PRP
   - Use specific file paths, class names, and method signatures from PRP context
   - Never guess - always verify the codebase patterns and examples referenced in the PRP yourself

3. **Execute Implementation**
   - Follow the PRP's Implementation Tasks sequence, add more detail as needed, especially when using subagents
   - Use the patterns and examples referenced in the PRP
   - Create files in locations specified by the desired codebase tree
   - Apply naming conventions from the task specifications and CLAUDE.md

4. **Progressive Validation**

   **Execute the level validation system from the PRP:**
   - **Level 1**: Run syntax & style validation commands from PRP
   - **Level 2**: Execute unit test validation from PRP
   - **Level 3**: Run integration testing commands from PRP
   - **Level 4**: Execute specified validation from PRP

   **Each level must pass before proceeding to the next.**

5. **Completion Verification**
   - Work through the Final Validation Checklist in the PRP
   - Verify all Success Criteria from the "What" section are met
   - Confirm all Anti-Patterns were avoided
   - Implementation is ready and working

**Failure Protocol**: When validation fails, use the patterns and gotchas from the PRP to fix issues, then re-run validation until passing.

If a fundamental issue with the plan is found, halt and produce a thorough explanation of the problem at a 10th grade level.

Strictly output your results in this JSON format:

\`\`\`json
{
   "result": "success" | "error" | "issue",
   "message": "Detailed explanation of the issue"
}

<PRP-README>
$PRP_README
</PRP-README>
EOF

read -r -d '' CLEANUP_PROMPT <<EOF
Clean up, organize files, and PREPARE FOR COMMIT. Check \`git diff\` for reference.

## DO NOT DELETE OR MODIFY:
1. The 'plan' directory structure (except for organizing docs as specified below)
2. The '$TASKS_FILE' file
3. README.md and any readme-adjacent files (CONTRIBUTING.md, LICENSE, etc.)

## DOCUMENTATION ORGANIZATION:
First, ensure \`plan/docs\` exists: \`mkdir -p plan/docs\`

Then, MOVE (not delete) any markdown documentation files you created during implementation to \`plan/docs/\`:
- Research notes, design docs, architecture documentation
- Implementation notes or technical writeups
- Reference documentation or guides
- Any other .md files that are not core project files

## KEEP IN ROOT:
Only these types of files should remain in the project root:
- README.md and readme-adjacent files (CONTRIBUTING.md, LICENSE, etc.)
- PRD.md and any other files that are already committed into the repository.
- Core config files (package.json, tsconfig.json, etc.)
- Build and script files

## DELETE OR GITIGNORE:
We are preparing to commit. Ensure the repo is clean.

1. **Delete**:
   - Temporary files clearly marked as temp or scratch
   - Duplicate files
   - Files that serve no ongoing purpose

2. **Gitignore** (Update .gitignore if needed):
   - Build artifacts (dist/, build/, etc.)
   - Dependency directories (node_modules/, venv/, etc.)
   - Environment files (.env)
   - OS-specific files (.DS_Store)
   - Any other generated files that should NOT be committed

Be selective - keep the root clean and organized.
EOF

read -r -d '' VALIDATION_PROMPT <<EOF
# Comprehensive Project Validation

Analyze this codebase deeply, create a validation script, and report any issues found.

**INPUTS:**
- PRD: \$(cat "$PRD_FILE")
- Tasks: \$(cat "$TASKS_FILE")

## Step 0: Discover Real User Workflows

**Before analyzing tooling, understand what users ACTUALLY do:**

1. Read workflow documentation:
   - README.md - Look for "Usage", "Quickstart", "Examples" sections
   - CLAUDE.md/AGENTS.md or similar - Look for workflow patterns
   - docs/ folder - User guides, tutorials

2. Identify external integrations:
   - What CLIs does the app use? (Check Dockerfile for installed tools)
   - What external APIs does it call? (Telegram, Slack, GitHub, etc.)
   - What services does it interact with?

3. Extract complete user journeys from docs:
   - Find examples like "Fix Issue (GitHub):" or "User does X → then Y → then Z"
   - Each workflow becomes an E2E test scenario

**Critical: Your E2E tests should mirror actual workflows from docs, not just test internal APIs.**

## Step 1: Deep Codebase Analysis

Explore the codebase to understand:

**What validation tools already exist:**
- Linting config: \`.eslintrc*\`, \`.pylintrc\`, \`ruff.toml\`, etc.
- Type checking: \`tsconfig.json\`, \`mypy.ini\`, etc.
- Style/formatting: \`.prettierrc*\`, \`black\`, \`.editorconfig\`
- Unit tests: \`jest.config.*\`, \`pytest.ini\`, test directories
- Package manager scripts: \`package.json\` scripts, \`Makefile\`, \`pyproject.toml\` tools

**What the application does:**
- Frontend: Routes, pages, components, user flows
- Backend: API endpoints, authentication, database operations
- Database: Schema, migrations, models
- Infrastructure: Docker services, dependencies

**Review Planning Documents:**
- Compare implementation against \`tasks.json\` and the PRD to identify missing features or deviations.

## Step 2: Generate Validation Script

Create a script (e.g., \`validate.sh\`) that sits in the codebase and runs the following phases (ONLY include phases that exist in the codebase):

### Phase 1: Linting
Run the actual linter commands found in the project.

### Phase 2: Type Checking
Run the actual type checker commands found.

### Phase 3: Style Checking
Run the actual formatter check commands found.

### Phase 4: Unit Testing
Run the actual test commands found.

### Phase 5: End-to-End Testing (BE CREATIVE AND COMPREHENSIVE)

Test COMPLETE user workflows from documentation, not just internal APIs.
Simulate the "User" persona defined in the PRD.

**The Three Levels of E2E Testing:**

1. **Internal APIs** (what you might naturally test):
   - Test adapter endpoints work
   - Database queries succeed
   - Commands execute

2. **External Integrations** (what you MUST test):
   - CLI operations (GitHub CLI create issue/PR, etc.)
   - Platform APIs (send Telegram message, post Slack message)
   - Any external services the app depends on

3. **Complete User Journeys** (what gives 100% confidence):
   - Follow workflows from docs start-to-finish
   - Test like a user would actually use the application in production

## Step 3: Validation & Reporting

1. **Execute the validation script** you created.
2. **Manually simulate workflows** if the script cannot cover everything.
3. **Generate a Bug Tracker Report**:
   - Make an itemized list of everything found.
   - Focus on big picture stuff that isn't already covered by unit tests.
   - Use product end-to-end in a simulated workflow to uncover bugs.
   - If any issues are found, list them clearly. This is NOT a fixer agent, it is a validator agent.

## Output

**IMPORTANT: Use these EXACT file names:**
1. Write the validation script to \`./validate.sh\` (this exact path, current directory)
2. Write the bug tracker report to \`./validation_report.md\` (this exact path, current directory)

The validation script should be executable, practical, and give complete confidence in the codebase.
If validation passes, the user should have 100% confidence their application works correctly in production.

**CLEANUP NOTE:** These files (validate.sh and validation_report.md) are temporary and will be deleted after validation completes.
EOF


# --- 4. Helpers ---

# Get the current status of an item from tsk
# Usage: get_item_status <id>
# Returns: The status string (Planned, Researching, Implementing, Complete, Failed) or empty if not found
get_item_status() {
    local id=$1
    # Get status as JSON and extract the status for this specific item
    tsk status -s "$SCOPE" 2>/dev/null | jq -r --arg iid "$id" '.[] | select(.id == $iid) | .status // empty'
}

# Generate ID based on scope
# Usage: generate_id <phase_num> <milestone_num> <task_num> <subtask_num>
# Returns: P1, P1.M1, P1.M1.T1, or P1.M1.T1.S1 depending on SCOPE
generate_id() {
    local phase_num=$1
    local milestone_num=$2
    local task_num=$3
    local subtask_num=$4

    case $SCOPE in
        phase)     echo "P${phase_num}" ;;
        milestone) echo "P${phase_num}.M${milestone_num}" ;;
        task)      echo "P${phase_num}.M${milestone_num}.T${task_num}" ;;
        subtask)   echo "P${phase_num}.M${milestone_num}.T${task_num}.S${subtask_num}" ;;
    esac
}

# Generate directory name based on scope
# Usage: generate_dirname <phase_num> <milestone_num> <task_num> <subtask_num>
# Returns: P1, P1M1, P1M1T1, or P1M1T1S1 depending on SCOPE
generate_dirname() {
    local phase_num=$1
    local milestone_num=$2
    local task_num=$3
    local subtask_num=$4

    case $SCOPE in
        phase)     echo "P${phase_num}" ;;
        milestone) echo "P${phase_num}M${milestone_num}" ;;
        task)      echo "P${phase_num}M${milestone_num}T${task_num}" ;;
        subtask)   echo "P${phase_num}M${milestone_num}T${task_num}S${subtask_num}" ;;
    esac
}

# Get item title from tasks.json
# Usage: get_item_title <phase_num> <milestone_num> <task_num> <subtask_num>
get_item_title() {
    local phase_num=$1
    local milestone_num=$2
    local task_num=$3
    local subtask_num=$4
    local phase_idx=$((phase_num - 1))
    local ms_idx=$((milestone_num - 1))
    local task_idx=$((task_num - 1))
    local subtask_idx=$((subtask_num - 1))

    case $SCOPE in
        phase)
            jq -r ".backlog[$phase_idx].title // empty" "$TASKS_FILE"
            ;;
        milestone)
            jq -r ".backlog[$phase_idx].milestones[$ms_idx].title // empty" "$TASKS_FILE"
            ;;
        task)
            jq -r ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].title // empty" "$TASKS_FILE"
            ;;
        subtask)
            jq -r ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].subtasks[$subtask_idx].title // empty" "$TASKS_FILE"
            ;;
    esac
}

# Get item description from tasks.json
# Usage: get_item_description <phase_num> <milestone_num> <task_num> <subtask_num>
get_item_description() {
    local phase_num=$1
    local milestone_num=$2
    local task_num=$3
    local subtask_num=$4
    local phase_idx=$((phase_num - 1))
    local ms_idx=$((milestone_num - 1))
    local task_idx=$((task_num - 1))
    local subtask_idx=$((subtask_num - 1))

    case $SCOPE in
        phase)
            jq -r ".backlog[$phase_idx].description // empty" "$TASKS_FILE"
            ;;
        milestone)
            jq -r ".backlog[$phase_idx].milestones[$ms_idx].description // empty" "$TASKS_FILE"
            ;;
        task)
            jq -r ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].description // empty" "$TASKS_FILE"
            ;;
        subtask)
            jq -r ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].subtasks[$subtask_idx].context_scope // empty" "$TASKS_FILE"
            ;;
    esac
}

# Generate scope name for prompts (capitalized)
get_scope_name() {
    case $SCOPE in
        phase)     echo "Phase" ;;
        milestone) echo "Milestone" ;;
        task)      echo "Task" ;;
        subtask)   echo "Subtask" ;;
    esac
}

# Generate scope article (a/an) for prompts
get_scope_article() {
    case $SCOPE in
        phase)     echo "a" ;;
        milestone) echo "a" ;;
        task)      echo "a" ;;
        subtask)   echo "a" ;;
    esac
}

# --- Parallel Research Helpers ---
RESEARCH_PID=""
RESEARCH_ITEM_ID=""
RESEARCH_DIRNAME=""

# Start research for an item in the background
# Usage: start_background_research <id> <dirname> <phase_num> <ms_num> <task_num> <subtask_num> <prev_id> <prev_dirname>
start_background_research() {
    local id=$1
    local dirname=$2
    local phase_num=$3
    local ms_num=$4
    local task_num=$5
    local subtask_num=$6
    local prev_id=$7
    local prev_dirname=$8

    # Skip if PRP already exists
    if [[ -f "$dirname/PRP.md" ]]; then
        print -P "%F{yellow}[PARALLEL]%f PRP for $id already exists, skipping background research"
        return 0
    fi

    print -P "%F{cyan}[PARALLEL]%f Starting background research for $id..."
    mkdir -p "$dirname/research"

    # Build context about the previous item being implemented
    local prev_context=""
    if [[ -n "$prev_id" && -f "$prev_dirname/PRP.md" ]]; then
        prev_context="
<parallel_execution_context>
IMPORTANT: This research is running IN PARALLEL while $prev_id is being implemented.

The previous work item ($prev_id) is currently being implemented. You MUST:
1. Read the previous item's PRP at $prev_dirname/PRP.md to understand what it produces
2. Treat that PRP as a CONTRACT - assume it will be implemented exactly as specified
3. Design your PRP to consume/build upon the outputs defined in the previous PRP
4. Do NOT duplicate or conflict with work specified in the previous PRP
5. Reference specific interfaces, files, or outputs from the previous PRP in your context_scope

The previous PRP defines what will exist when your item begins implementation.
</parallel_execution_context>"
    fi

    # Run research in background subshell
    (
        run_with_retry tsk update "$id" Researching
        run_with_retry $AGENT -p "$PRP_CREATE_PROMPT Create a PRP for $(get_scope_name) $id of the PRD. Store it at $dirname/PRP.md.
<item_title>$(get_item_title $phase_num $ms_num $task_num $subtask_num)</item_title>
<item_description>$(get_item_description $phase_num $ms_num $task_num $subtask_num)</item_description>
<plan_status>$(tsk status)</plan_status>$prev_context"
        if [[ ! -f "$dirname/PRP.md" ]]; then
            print -P "%F{yellow}[PARALLEL]%f PRP.md not found for $id, retrying..."
            $AGENT --continue -p "You didn't write the file. Make sure you write the file to $dirname/PRP.md"
        fi
    ) &

    RESEARCH_PID=$!
    RESEARCH_ITEM_ID=$id
    RESEARCH_DIRNAME=$dirname
    print -P "%F{cyan}[PARALLEL]%f Background research started (PID: $RESEARCH_PID)"
}

# Wait for background research to complete if it matches the given item
# Usage: wait_for_background_research <id>
wait_for_background_research() {
    local id=$1

    if [[ -n "$RESEARCH_PID" && "$RESEARCH_ITEM_ID" == "$id" ]]; then
        print -P "%F{cyan}[PARALLEL]%f Waiting for background research of $id to complete..."
        wait $RESEARCH_PID
        local exit_code=$?
        RESEARCH_PID=""
        RESEARCH_ITEM_ID=""
        RESEARCH_DIRNAME=""
        if [[ $exit_code -ne 0 ]]; then
            print -P "%F{yellow}[PARALLEL]%f Background research exited with code $exit_code"
        else
            print -P "%F{green}[PARALLEL]%f Background research for $id completed"
        fi
        return $exit_code
    fi
    return 0
}

# Get the next item coordinates based on current position and scope
# Sets NEXT_* variables or returns 1 if no next item
# Usage: get_next_item <phase_num> <ms_num> <task_num> <subtask_num>
get_next_item() {
    local phase_num=$1
    local ms_num=$2
    local task_num=$3
    local subtask_num=$4
    local phase_idx=$((phase_num - 1))
    local ms_idx=$((ms_num - 1))
    local task_idx=$((task_num - 1))
    local subtask_idx=$((subtask_num - 1))

    NEXT_PHASE=$phase_num
    NEXT_MS=$ms_num
    NEXT_TASK=$task_num
    NEXT_SUBTASK=$subtask_num

    case $SCOPE in
        phase)
            local total_phases=$(jq '.backlog | length' "$TASKS_FILE")
            if (( phase_num < total_phases )); then
                NEXT_PHASE=$((phase_num + 1))
                return 0
            fi
            return 1
            ;;
        milestone)
            local total_ms=$(jq ".backlog[$phase_idx].milestones | length" "$TASKS_FILE")
            if (( ms_num < total_ms )); then
                NEXT_MS=$((ms_num + 1))
                return 0
            fi
            # Try next phase
            local total_phases=$(jq '.backlog | length' "$TASKS_FILE")
            if (( phase_num < total_phases )); then
                NEXT_PHASE=$((phase_num + 1))
                NEXT_MS=1
                return 0
            fi
            return 1
            ;;
        task)
            local total_tasks=$(jq ".backlog[$phase_idx].milestones[$ms_idx].tasks | length" "$TASKS_FILE")
            if (( task_num < total_tasks )); then
                NEXT_TASK=$((task_num + 1))
                return 0
            fi
            # Try next milestone
            local total_ms=$(jq ".backlog[$phase_idx].milestones | length" "$TASKS_FILE")
            if (( ms_num < total_ms )); then
                NEXT_MS=$((ms_num + 1))
                NEXT_TASK=1
                return 0
            fi
            # Try next phase
            local total_phases=$(jq '.backlog | length' "$TASKS_FILE")
            if (( phase_num < total_phases )); then
                NEXT_PHASE=$((phase_num + 1))
                NEXT_MS=1
                NEXT_TASK=1
                return 0
            fi
            return 1
            ;;
        subtask)
            local total_subtasks=$(jq ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].subtasks | length" "$TASKS_FILE")
            if (( subtask_num < total_subtasks )); then
                NEXT_SUBTASK=$((subtask_num + 1))
                return 0
            fi
            # Try next task
            local total_tasks=$(jq ".backlog[$phase_idx].milestones[$ms_idx].tasks | length" "$TASKS_FILE")
            if (( task_num < total_tasks )); then
                NEXT_TASK=$((task_num + 1))
                NEXT_SUBTASK=1
                return 0
            fi
            # Try next milestone
            local total_ms=$(jq ".backlog[$phase_idx].milestones | length" "$TASKS_FILE")
            if (( ms_num < total_ms )); then
                NEXT_MS=$((ms_num + 1))
                NEXT_TASK=1
                NEXT_SUBTASK=1
                return 0
            fi
            # Try next phase
            local total_phases=$(jq '.backlog | length' "$TASKS_FILE")
            if (( phase_num < total_phases )); then
                NEXT_PHASE=$((phase_num + 1))
                NEXT_MS=1
                NEXT_TASK=1
                NEXT_SUBTASK=1
                return 0
            fi
            return 1
            ;;
    esac
    return 1
}

# Execute a single work item (phase/milestone/task/subtask)
# Usage: execute_item <id> <dirname> <phase_num> <ms_num> <task_num> <subtask_num>
execute_item() {
    local id=$1
    local dirname=$2
    local phase_num=$3
    local ms_num=$4
    local task_num=$5
    local subtask_num=$6

    # Check current status from tsk
    local current_status=$(get_item_status "$id")

    # Skip if already completed
    if [[ "$current_status" == "Completed" || "$current_status" == "Complete" ]]; then
        print -P "\n%F{green}[SKIP]%f $id is already %F{green}Completed%f. Skipping..."
        return 0
    fi

    print -P "\n%B%F{green}>>> EXECUTING $id%f%b %F{cyan}(current status: $current_status)%f%b"

    # Wait for any background research for this item to complete
    wait_for_background_research "$id"

    mkdir -p "$dirname/research"

    # If PRP already exists OR status is Implementing, skip to implementation
    if [[ -f "$dirname/PRP.md" || "$current_status" == "Implementing" ]]; then
        print -P "%F{yellow}[SKIP]%f PRP exists or status is Implementing, skipping to implementation"
        run_with_retry tsk update "$id" Implementing
    else
        run_with_retry tsk update "$id" Researching
        run_with_retry $AGENT -p "$PRP_CREATE_PROMPT Create a PRP for $(get_scope_name) $id of the PRD. Store it at $dirname/PRP.md.
<item_title>$(get_item_title $phase_num $ms_num $task_num $subtask_num)</item_title>
<item_description>$(get_item_description $phase_num $ms_num $task_num $subtask_num)</item_description>
<plan_status>$(tsk status)</plan_status>"
        [ ! -f "$dirname/PRP.md" ] && print -P "%F{red}[ERROR]%f PRP.md not found. Retrying..." && $AGENT --continue -p "You didn't write the file. Make sure you write the file to $dirname/PRP.md"
        [ ! -f "$dirname/PRP.md" ] && print -P "%F{red}[ERROR]%f PRP.md not found. Aborting..." && exit 1
        run_with_retry tsk update "$id" Implementing
    fi

    # Start background research for next item if parallel research is enabled
    if [[ "$PARALLEL_RESEARCH" == "true" ]]; then
        if get_next_item $phase_num $ms_num $task_num $subtask_num; then
            local next_id=$(generate_id $NEXT_PHASE $NEXT_MS $NEXT_TASK $NEXT_SUBTASK)
            local next_dirname="$PLAN_DIR/$(generate_dirname $NEXT_PHASE $NEXT_MS $NEXT_TASK $NEXT_SUBTASK)"
            # Pass current item as previous context so next item's research can reference it as a contract
            start_background_research "$next_id" "$next_dirname" $NEXT_PHASE $NEXT_MS $NEXT_TASK $NEXT_SUBTASK "$id" "$dirname"
        fi
    fi

    run_with_retry $AGENT -p "$PRP_EXECUTE_PROMPT Execute the PRP for $(get_scope_name) $id. The PRP file is located at: $dirname/PRP.md. READ IT NOW."

    git add $TASKS_FILE
    [[ -z "$(git diff HEAD --name-only)" ]] && print -P "%F{red}[ERROR]%f No diff found after $id. Aborting..." && exit 1

    run_with_retry tsk update "$id" Complete

    print -P "%F{blue}[CLEANUP]%f Cleaning up $id..."
    run_with_retry $AGENT -p "$CLEANUP_PROMPT" || print -P "%F{yellow}[WARN]%f Cleanup failed, proceeding to commit..."

    smart_commit

    # Check if graceful shutdown was requested
    check_shutdown
}

# Alias-aware retry logic with interruptible wait for graceful shutdown
run_with_retry() {
    local n=1
    local max=3
    local delay=5
    local cmd_pid exit_status

    while true; do
        # Check shutdown before starting new attempt
        if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
            return 130
        fi

        # Run in background subshell - preserves alias expansion via eval
        ( eval "${(q)@}" ) &
        cmd_pid=$!
        CURRENT_CMD_PID=$cmd_pid

        # Poll with sleep (sleep IS interruptible by signals, wait is NOT in zsh)
        while kill -0 $cmd_pid 2>/dev/null; do
            # Check shutdown - trap fires during sleep
            if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
                kill -TERM $cmd_pid 2>/dev/null
                wait $cmd_pid 2>/dev/null
                CURRENT_CMD_PID=""
                return 130
            fi
            sleep 0.1
        done

        # Process finished, get exit status
        wait $cmd_pid 2>/dev/null
        exit_status=$?
        CURRENT_CMD_PID=""

        # Success - return
        if [[ $exit_status -eq 0 ]]; then
            return 0
        fi

        # Retry logic
        if (( n < max )); then
            print -P "%F{yellow}[RETRY]%f Command failed. Attempt $n/$max. Retrying in ${delay}s..."
            sleep $delay
            ((n++))
        else
            print -P "%F{red}[ERROR]%f Command failed after $max attempts: $*"
            return 1
        fi
    done
}

# Protects tasks.json and the plan directory from AI "cleanup"
smart_commit() {
    print -P "%F{blue}[GIT]%f Staging changes..."
    git add -A

    # Critical protection: If tasks.json was removed or mangled, restore it.
    if [[ ! -f "$TASKS_FILE" ]]; then
        print -P "%F{yellow}[WARN]%f $TASKS_FILE missing! Restoring..."
        git checkout HEAD -- "$TASKS_FILE"
        git add "$TASKS_FILE"
    fi

    # Unstage the next item's plan directory if parallel research is active
    if [[ "$PARALLEL_RESEARCH" == "true" && -n "$RESEARCH_DIRNAME" ]]; then
        print -P "%F{cyan}[GIT]%f Unstaging next item's directory: $RESEARCH_DIRNAME"
        git reset HEAD -- "$RESEARCH_DIRNAME" 2>/dev/null || true
    fi

    run_with_retry git commit-claude
}

# --- 5. Main Workflow ---

if [[ "$ONLY_VALIDATE" == "false" ]]; then

# A. Task Breakdown (Only run if tasks.json is missing)
if [[ ! -f "$TASKS_FILE" ]]; then
    print -P "%F{magenta}[PHASE 0]%f Generating breakdown..."
    mkdir -p "$PLAN_DIR/architecture"
    run_with_retry $BREAKDOWN_AGENT --system-prompt="$TASK_BREAKDOWN_SYSTEM_PROMPT" -p "$TASK_BREAKDOWN_PROMPT"

    # If file still doesn't exist, demand the agent write it
    if [[ ! -f "$TASKS_FILE" ]]; then
        print -P "%F{yellow}[PHASE 0]%f $TASKS_FILE not found. Demanding agent write it..."
        run_with_retry $BREAKDOWN_AGENT --continue -p "You did NOT write the tasks file. You MUST write the JSON breakdown to \`./$TASKS_FILE\` (CURRENT WORKING DIRECTORY) immediately. Do NOT search for tasks.json in other directories. Create a NEW file at exactly \`./$TASKS_FILE\`. Use your file writing tools NOW."
    fi

    if [[ -f "$TASKS_FILE" ]]; then
        print -P "%F{green}[PHASE 0]%f Task breakdown complete."

        # Cleanup phase: organize .md files created during breakdown
        print -P "%F{blue}[CLEANUP]%f Organizing files after task breakdown..."
        run_with_retry $AGENT -p "$CLEANUP_PROMPT" || print -P "%F{yellow}[WARN]%f Cleanup failed, proceeding to commit..."

        # Commit the task breakdown
        print -P "%F{blue}[GIT]%f Committing task breakdown..."
        git add "$TASKS_FILE" "$PLAN_DIR"
        git commit -m "Add task breakdown and architecture research" 2>/dev/null || true
    fi
fi

# Verify tasks file exists before looping
[[ ! -f "$TASKS_FILE" ]] && print -P "%F{red}[ERROR]%f $TASKS_FILE not found after breakdown. Agent failed to write file." && exit 1

# Print current scope configuration
print -P "%F{cyan}[CONFIG]%f Scope: %F{yellow}$SCOPE%f (Default: task)"
[[ $BREAKDOWN_AGENT != "$AGENT" ]] && print -P "%F{cyan}[CONFIG]%f Breakdown agent: %F{yellow}$BREAKDOWN_AGENT%f"
print -P "%F{cyan}[CONFIG]%f Execution agent: %F{yellow}$AGENT%f"
[[ "$PARALLEL_RESEARCH" == "true" ]] && print -P "%F{cyan}[CONFIG]%f Parallel research: %F{green}enabled%f"
print -P "%F{cyan}[CONFIG]%f Starting positions: Phase=$START_PHASE"
[[ $SCOPE != "phase" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Milestone=$START_MS"
[[ $SCOPE == "task" || $SCOPE == "subtask" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Task=$START_TASK"
[[ $SCOPE == "subtask" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Subtask=$START_SUBTASK"

total_phases=$(jq '.backlog | length' "$TASKS_FILE")

# Outer loop: Always iterate through phases
for (( phase_idx=0; phase_idx<$total_phases; phase_idx++ )); do
    # Get actual phase ID from JSON (e.g., "P5" -> 5), not array index
    PHASE_ID=$(jq -r ".backlog[$phase_idx].id // empty" "$TASKS_FILE")
    if [[ $PHASE_ID =~ P([0-9]+) ]]; then
        PHASE_NUM=${match[1]}
    else
        PHASE_NUM=$((phase_idx+1))  # Fallback to index-based
    fi

    # Skip if we haven't reached the start phase yet
    [[ $PHASE_NUM -lt $START_PHASE ]] && continue

    # For phase scope, process and continue
    if [[ $SCOPE == "phase" ]]; then
        ID=$(generate_id $PHASE_NUM 1 1 1)
        DIRNAME="$PLAN_DIR/$(generate_dirname $PHASE_NUM 1 1 1)"
        execute_item "$ID" "$DIRNAME" $PHASE_NUM 1 1 1
        continue
    fi

    # Second loop: Milestones (for milestone, task, subtask scope)
    total_ms=$(jq ".backlog[$phase_idx].milestones | length" "$TASKS_FILE")

    for (( ms_idx=0; ms_idx<$total_ms; ms_idx++ )); do
        # Get actual milestone ID from JSON (e.g., "P5.M1" -> 1)
        MS_ID=$(jq -r ".backlog[$phase_idx].milestones[$ms_idx].id // empty" "$TASKS_FILE")
        if [[ $MS_ID =~ M([0-9]+) ]]; then
            MS_NUM=${match[1]}
        else
            MS_NUM=$((ms_idx+1))  # Fallback to index-based
        fi

        # Skip milestones until we reach the start milestone of the start phase
        if [[ $PHASE_NUM -eq $START_PHASE && $MS_NUM -lt $START_MS ]]; then
            continue
        fi

        # For milestone scope, process and continue
        if [[ $SCOPE == "milestone" ]]; then
            ID=$(generate_id $PHASE_NUM $MS_NUM 1 1)
            DIRNAME="$PLAN_DIR/$(generate_dirname $PHASE_NUM $MS_NUM 1 1)"
            execute_item "$ID" "$DIRNAME" $PHASE_NUM $MS_NUM 1 1
            continue
        fi

        # Third loop: Tasks (for task, subtask scope)
        total_tasks=$(jq ".backlog[$phase_idx].milestones[$ms_idx].tasks | length" "$TASKS_FILE")
        [[ $total_tasks == "null" || $total_tasks == "0" ]] && continue

        for (( task_idx=0; task_idx<$total_tasks; task_idx++ )); do
            # Get actual task ID from JSON (e.g., "P5.M1.T1" -> 1)
            TASK_ID=$(jq -r ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].id // empty" "$TASKS_FILE")
            if [[ $TASK_ID =~ T([0-9]+) ]]; then
                TASK_NUM=${match[1]}
            else
                TASK_NUM=$((task_idx+1))  # Fallback to index-based
            fi

            # Skip tasks until we reach the start task of the start milestone/phase
            if [[ $PHASE_NUM -eq $START_PHASE && $MS_NUM -eq $START_MS && $TASK_NUM -lt $START_TASK ]]; then
                continue
            fi

            # For task scope, process and continue
            if [[ $SCOPE == "task" ]]; then
                ID=$(generate_id $PHASE_NUM $MS_NUM $TASK_NUM 1)
                DIRNAME="$PLAN_DIR/$(generate_dirname $PHASE_NUM $MS_NUM $TASK_NUM 1)"
                execute_item "$ID" "$DIRNAME" $PHASE_NUM $MS_NUM $TASK_NUM 1
                continue
            fi

            # Fourth loop: Subtasks (for subtask scope only)
            total_subtasks=$(jq ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].subtasks | length" "$TASKS_FILE")
            [[ $total_subtasks == "null" || $total_subtasks == "0" ]] && continue

            for (( subtask_idx=0; subtask_idx<$total_subtasks; subtask_idx++ )); do
                # Get actual subtask ID from JSON (e.g., "P5.M1.T1.S1" -> 1)
                SUBTASK_ID=$(jq -r ".backlog[$phase_idx].milestones[$ms_idx].tasks[$task_idx].subtasks[$subtask_idx].id // empty" "$TASKS_FILE")
                if [[ $SUBTASK_ID =~ S([0-9]+) ]]; then
                    SUBTASK_NUM=${match[1]}
                else
                    SUBTASK_NUM=$((subtask_idx+1))  # Fallback to index-based
                fi

                # Skip subtasks until we reach the start subtask of the start task/milestone/phase
                if [[ $PHASE_NUM -eq $START_PHASE && $MS_NUM -eq $START_MS && $TASK_NUM -eq $START_TASK && $SUBTASK_NUM -lt $START_SUBTASK ]]; then
                    continue
                fi

ID=$(generate_id $PHASE_NUM $MS_NUM $TASK_NUM $SUBTASK_NUM)
                DIRNAME="$PLAN_DIR/$(generate_dirname $PHASE_NUM $MS_NUM $TASK_NUM $SUBTASK_NUM)"
                execute_item "$ID" "$DIRNAME" $PHASE_NUM $MS_NUM $TASK_NUM $SUBTASK_NUM
            done
        done
    done
done

else
    # Validation Only Mode
    print -P "%F{cyan}[CONFIG]%f Running in %F{magenta}VALIDATION ONLY%f mode"
    if [[ ! -f "$TASKS_FILE" ]]; then
        print -P "%F{red}[ERROR]%f $TASKS_FILE not found. Cannot validate without tasks."
        exit 1
    fi
fi

# Final Validation Step
print -P "\n%F{magenta}[VALIDATION]%f Starting final validation..."
run_with_retry $AGENT -p "$VALIDATION_PROMPT"
print -P "\n%F{magenta}[VALIDATION]%f Validation complete. Check validation_report.md."

if [[ -f "validation_report.md" ]]; then
    print -P "\n%F{magenta}[ANALYSIS]%f Analyzing validation report..."

    REPORT_CONTENT=$(cat validation_report.md)

    # Check if report requires action using a restricted agent
    # We use 'claude' directly to ensure we can disable tools
    CHECK_PROMPT="Here is the validation report.

    CONTENT:
    $REPORT_CONTENT

    INSTRUCTION:
    - If the report shows ANY failures, bugs, or issues: output DIRTY
    - If the report shows passing status and no issues: output CLEAN
    - Output ONLY the single word."

    # First attempt
    RESULT=$(claude --print --allowed-tools "" --system-prompt "You are a binary classifier. Output only CLEAN or DIRTY." "$CHECK_PROMPT")
    CLEAN_RESULT=$(echo "$RESULT" | tr -d '[:space:]')

    # Validate response and retry if necessary
    if [[ "$CLEAN_RESULT" != "CLEAN" && "$CLEAN_RESULT" != "DIRTY" ]]; then
        print -P "%F{yellow}[RETRY]%f Invalid checker output: '$RESULT'. Retrying..."
        RESULT=$(claude --print --continue --allowed-tools "" "ERROR: You replied with '$RESULT'. You MUST output exactly one word: CLEAN or DIRTY.")
        CLEAN_RESULT=$(echo "$RESULT" | tr -d '[:space:]')
    fi

    print -P "%F{cyan}[STATUS]%f Report status: $CLEAN_RESULT"

    if [[ "$CLEAN_RESULT" == "DIRTY" ]]; then
        print -P "\n%F{red}[FIX]%f Issues found. Starting Fixer Agent..."
        FIX_PROMPT="The validation report found issues. Please fix them.

        VALIDATION REPORT:
        $REPORT_CONTENT

        INSTRUCTIONS:
        1. Analyze the issues listed in the report.
        2. Fix the code to resolve these issues.
        3. Verify your fixes."

        run_with_retry $AGENT -p "$FIX_PROMPT"
        print -P "%F{green}[FIX]%f Fixes applied."
    fi
fi

# Cleanup: Delete validation artifacts
print -P "%F{blue}[CLEANUP]%f Removing validation artifacts..."

# Ask agent to delete the files (in case they were created elsewhere)
run_with_retry $AGENT -p "Delete the validation artifacts: remove ./validate.sh and ./validation_report.md from the current directory. These are temporary files that should not be committed."

# Manual deletion as backup (in case agent didn't delete them)
rm -f "./validate.sh" "./validation_report.md" 2>/dev/null

# Mark final task as complete before committing
print -P "%F{blue}[STATUS]%f Marking final task as complete..."
FINAL_TASK=$(tsk next -s "$SCOPE" 2>/dev/null)
if [[ -n "$FINAL_TASK" ]]; then
    run_with_retry tsk update "$FINAL_TASK" Complete
fi

# Final smart commit after validation
print -P "%F{blue}[GIT]%f Committing final changes with smart commit..."
smart_commit

print -P "%F{green}[SUCCESS]%f Workflow completed."
