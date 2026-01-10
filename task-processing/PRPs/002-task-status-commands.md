# PRP-002: Task Status Update Commands

## Goal

### Feature Goal
Implement CLI commands to update the current subtask's status and automatically propagate "Complete" status up the hierarchy when all siblings at each level are complete.

### Deliverable
Six new typer commands in `tsk.py`:
- `tsk complete` - Mark current subtask Complete + cascade completion upward
- `tsk plan` - Mark current subtask Planned
- `tsk research` - Mark current subtask Researching
- `tsk ready` - Mark current subtask Ready
- `tsk implement` - Mark current subtask Implementing
- `tsk fail` - Mark current subtask Failed

### Success Definition
1. Each command updates the current subtask's status correctly
2. `tsk complete` walks up the hierarchy (Subtask → Task → Milestone → Phase)
3. At each parent level, if ALL children are Complete, parent is marked Complete
4. Commands output confirmation message via `rich.console`
5. Tests verify all functionality with 100% coverage of new code

---

## Context

### Codebase References

```yaml
primary_files:
  - path: "/home/dustin/projects/ai-scripts/tasks/tsk.py"
    purpose: "Main CLI application - add new commands here"
    patterns_to_follow:
      - "Use @app.command() decorator (lines 132, 146, 151, 181, 202)"
      - "Use console.print() for user feedback with Rich markup (line 200)"
      - "Use load_backlog() and save_backlog() for persistence (lines 71-88)"
      - "Use find_next_active() to get current subtask context (line 90-116)"

data_models:
  - path: "/home/dustin/projects/ai-scripts/tasks/tsk.py"
    lines: "22-64"
    models:
      - "Status(str, Enum): Planned|Researching|Ready|Implementing|Complete|Failed"
      - "Subtask(BaseModel): id, title, status, story_points, dependencies, context_scope"
      - "Task(BaseModel): id, title, status, description, subtasks:List[Subtask]"
      - "Milestone(BaseModel): id, title, status, description, tasks:List[Task]"
      - "Phase(BaseModel): id, title, status, description, milestones:List[Milestone]"
      - "Backlog(BaseModel): backlog:List[Phase]"

existing_helpers:
  - function: "find_next_active(backlog) -> Dict | None"
    location: "tsk.py:90-116"
    returns: |
      {
        "context": "CURRENT_FOCUS",
        "phase": {...},      # Phase model dict (excludes milestones)
        "milestone": {...},  # Milestone model dict (excludes tasks)
        "task": {...},       # Task model dict (excludes subtasks)
        "subtask": {...}     # Full subtask model dict
      }
    use_case: "Get current subtask ID from focus['subtask']['id']"

  - function: "get_node_by_id(backlog, target_id) -> Model | None"
    location: "tsk.py:118-128"
    use_case: "Find any node by ID for status updates"

  - function: "load_backlog() -> Backlog"
    location: "tsk.py:71-83"
    use_case: "Load tasks.json into Backlog model"

  - function: "save_backlog(backlog: Backlog)"
    location: "tsk.py:85-88"
    use_case: "Persist Backlog to tasks.json"

test_data:
  - path: "/home/dustin/projects/ai-scripts/tasks/test-tasks.json"
    purpose: "Sample task hierarchy for testing"
    structure: "P1 > P1.M1 > P1.M1.T1 > [P1.M1.T1.S1 (Complete), P1.M1.T1.S2 (Planned)]"

hierarchy_id_format:
  pattern: "P{n}.M{n}.T{n}.S{n}"
  examples:
    - "P1 (Phase)"
    - "P1.M1 (Milestone)"
    - "P1.M1.T1 (Task)"
    - "P1.M1.T1.S1 (Subtask)"
```

### External References

```yaml
typer_documentation:
  - url: "https://typer.tiangolo.com/tutorial/commands/"
    section: "Adding CLI commands with @app.command()"
  - url: "https://typer.tiangolo.com/tutorial/testing/"
    section: "Testing typer apps with CliRunner"

pytest_patterns:
  - url: "https://docs.pytest.org/en/stable/how-to/tmp_path.html"
    section: "Using tmp_path for temporary file testing"
  - url: "https://docs.pytest.org/en/stable/how-to/monkeypatch.html"
    section: "Mocking module globals like CONFIG"

rich_console:
  - url: "https://rich.readthedocs.io/en/stable/console.html"
    section: "Console.print() with markup for colored output"
```

### Algorithm: Upward Completion Propagation

```python
# Pseudocode for propagate_completion_upward()
def propagate_completion_upward(backlog, subtask_id):
    """
    Walk up hierarchy from subtask. At each parent level,
    check if ALL children are Complete. If yes, mark parent Complete.
    Stop immediately if any sibling is not Complete.
    """
    # Parse ID to get parent chain: P1.M1.T1.S1 -> [P1, P1.M1, P1.M1.T1]
    parts = subtask_id.split('.')

    # Walk up from Task -> Milestone -> Phase
    # Level 3 = Task (has subtasks)
    # Level 2 = Milestone (has tasks)
    # Level 1 = Phase (has milestones)

    for level in [3, 2, 1]:  # Task, Milestone, Phase
        parent_id = '.'.join(parts[:level])
        parent = get_node_by_id(backlog, parent_id)

        if parent is None:
            break

        children = get_children(parent)  # subtasks, tasks, or milestones

        if all(child.status == Status.COMPLETE for child in children):
            parent.status = Status.COMPLETE
            # Continue to next level up
        else:
            break  # Stop propagation - not all children complete
```

### Gotchas & Edge Cases

```yaml
edge_cases:
  - scenario: "No active subtask (all complete)"
    behavior: "find_next_active() returns None"
    handling: "Print error message and exit with code 1"

  - scenario: "Empty subtasks list in task"
    behavior: "all() on empty list returns True"
    handling: "Only propagate if children list is non-empty"

  - scenario: "Already complete subtask"
    behavior: "Marking Complete again should still cascade"
    handling: "Always check parent completion status after update"

validation:
  - "Status enum restricts to valid values only"
  - "Pydantic validates on model assignment"
  - "typer.Exit(code=1) for error conditions"
```

---

## Implementation Tasks

### Task 1: Add Simple Status Commands

**What**: Add 5 status update commands: `plan`, `research`, `ready`, `implement`, `fail`

**File**: `/home/dustin/projects/ai-scripts/tasks/tsk.py`

**Pattern to follow** (existing `update` command at line 181):
```python
@app.command("update")
def update_status(
    node_id: str = typer.Argument(...),
    new_status: Status = typer.Argument(...)
):
```

**Implementation**:
```python
# Add after line 200 (after update command)

def _update_current_subtask_status(new_status: Status):
    """Helper to update current subtask to new status."""
    backlog = load_backlog()
    focus = find_next_active(backlog)

    if not focus:
        console.print("[red]No active subtask found.[/red]")
        raise typer.Exit(code=1)

    subtask_id = focus['subtask']['id']
    subtask = get_node_by_id(backlog, subtask_id)
    old_status = subtask.status
    subtask.status = new_status
    save_backlog(backlog)

    console.print(f"[green]{subtask_id}: {old_status} → {new_status}[/green]")

@app.command("plan")
def set_planned():
    """Set current subtask status to Planned."""
    _update_current_subtask_status(Status.PLANNED)

@app.command("research")
def set_researching():
    """Set current subtask status to Researching."""
    _update_current_subtask_status(Status.RESEARCHING)

@app.command("ready")
def set_ready():
    """Set current subtask status to Ready."""
    _update_current_subtask_status(Status.READY)

@app.command("implement")
def set_implementing():
    """Set current subtask status to Implementing."""
    _update_current_subtask_status(Status.IMPLEMENTING)

@app.command("fail")
def set_failed():
    """Set current subtask status to Failed."""
    _update_current_subtask_status(Status.FAILED)
```

**Verification**: Run `tsk --help` and verify 5 new commands appear.

---

### Task 2: Implement Upward Propagation Helper

**What**: Create `propagate_completion_upward()` function

**File**: `/home/dustin/projects/ai-scripts/tasks/tsk.py`

**Location**: Add after `get_node_by_id()` function (after line 128)

**Implementation**:
```python
def get_children(node):
    """Return children list for any node type."""
    if hasattr(node, 'subtasks'):
        return node.subtasks
    elif hasattr(node, 'tasks'):
        return node.tasks
    elif hasattr(node, 'milestones'):
        return node.milestones
    return []

def propagate_completion_upward(backlog: Backlog, subtask_id: str) -> list[str]:
    """
    Walk up hierarchy from subtask. At each parent level,
    if ALL children are Complete, mark parent Complete.
    Returns list of parent IDs that were updated.
    """
    updated = []
    parts = subtask_id.split('.')

    # Walk up: Task (3 parts), Milestone (2 parts), Phase (1 part)
    for level in [3, 2, 1]:
        if len(parts) < level:
            break

        parent_id = '.'.join(parts[:level])
        parent = get_node_by_id(backlog, parent_id)

        if parent is None:
            break

        children = get_children(parent)

        # Don't auto-complete if no children
        if not children:
            break

        if all(child.status == Status.COMPLETE for child in children):
            if parent.status != Status.COMPLETE:
                parent.status = Status.COMPLETE
                updated.append(parent_id)
        else:
            break  # Stop - not all children complete

    return updated
```

**Verification**: Unit test with mock data showing cascade behavior.

---

### Task 3: Implement Complete Command

**What**: Add `complete` command that updates status AND cascades

**File**: `/home/dustin/projects/ai-scripts/tasks/tsk.py`

**Location**: Add after the simple status commands

**Implementation**:
```python
@app.command("complete")
def set_complete():
    """
    Mark current subtask as Complete.
    Cascades completion upward: if all siblings at parent level
    are Complete, parent is also marked Complete.
    """
    backlog = load_backlog()
    focus = find_next_active(backlog)

    if not focus:
        console.print("[red]No active subtask found.[/red]")
        raise typer.Exit(code=1)

    subtask_id = focus['subtask']['id']
    subtask = get_node_by_id(backlog, subtask_id)
    old_status = subtask.status
    subtask.status = Status.COMPLETE

    console.print(f"[green]{subtask_id}: {old_status} → Complete[/green]")

    # Cascade upward
    updated_parents = propagate_completion_upward(backlog, subtask_id)

    for parent_id in updated_parents:
        console.print(f"[cyan]↳ {parent_id} → Complete (all children complete)[/cyan]")

    save_backlog(backlog)
```

**Verification**:
1. Run `tsk complete` on subtask where siblings are incomplete - only subtask updates
2. Run `tsk complete` on last incomplete subtask - cascades to parent

---

### Task 4: Create Test Suite

**What**: Comprehensive pytest tests for new commands

**File**: Create `/home/dustin/projects/ai-scripts/tasks/tests/test_status_commands.py`

**Setup**: Create `tests/__init__.py` and `tests/conftest.py`

**conftest.py**:
```python
import json
import pytest
from pathlib import Path
from typer.testing import CliRunner

@pytest.fixture
def cli_runner():
    return CliRunner()

@pytest.fixture
def sample_backlog_data():
    """Task hierarchy with mixed statuses for testing."""
    return {
        "backlog": [{
            "type": "Phase", "id": "P1", "title": "Test Phase",
            "status": "Implementing", "description": "Test",
            "milestones": [{
                "type": "Milestone", "id": "P1.M1", "title": "Test Milestone",
                "status": "Implementing", "description": "Test",
                "tasks": [{
                    "type": "Task", "id": "P1.M1.T1", "title": "Test Task",
                    "status": "Implementing", "description": "Test",
                    "subtasks": [
                        {"type": "Subtask", "id": "P1.M1.T1.S1", "title": "ST1",
                         "status": "Complete", "story_points": 1, "dependencies": []},
                        {"type": "Subtask", "id": "P1.M1.T1.S2", "title": "ST2",
                         "status": "Implementing", "story_points": 1, "dependencies": []}
                    ]
                }]
            }]
        }]
    }

@pytest.fixture
def tasks_file(tmp_path, sample_backlog_data):
    """Create temporary tasks.json file."""
    file_path = tmp_path / "tasks.json"
    file_path.write_text(json.dumps(sample_backlog_data))
    return file_path
```

**test_status_commands.py**:
```python
import json
import sys
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from tsk import app, CONFIG

def test_plan_command(cli_runner, tasks_file):
    """Test tsk plan sets status to Planned."""
    CONFIG["file"] = tasks_file
    result = cli_runner.invoke(app, ["plan"])
    assert result.exit_code == 0
    assert "Planned" in result.output

    # Verify file was updated
    data = json.loads(tasks_file.read_text())
    subtask = data["backlog"][0]["milestones"][0]["tasks"][0]["subtasks"][1]
    assert subtask["status"] == "Planned"

def test_complete_no_cascade(cli_runner, tasks_file):
    """Test complete when sibling is not complete."""
    CONFIG["file"] = tasks_file
    result = cli_runner.invoke(app, ["complete"])
    assert result.exit_code == 0
    assert "Complete" in result.output
    # Should NOT cascade because S1 was already Complete but Task not updated

def test_complete_with_cascade(cli_runner, tmp_path):
    """Test complete cascades when all siblings complete."""
    # Create data where completing S2 completes everything
    data = {
        "backlog": [{
            "type": "Phase", "id": "P1", "title": "P", "status": "Implementing", "description": "",
            "milestones": [{
                "type": "Milestone", "id": "P1.M1", "title": "M", "status": "Implementing", "description": "",
                "tasks": [{
                    "type": "Task", "id": "P1.M1.T1", "title": "T", "status": "Implementing", "description": "",
                    "subtasks": [
                        {"type": "Subtask", "id": "P1.M1.T1.S1", "title": "S1",
                         "status": "Complete", "story_points": 1, "dependencies": []},
                        {"type": "Subtask", "id": "P1.M1.T1.S2", "title": "S2",
                         "status": "Implementing", "story_points": 1, "dependencies": []}
                    ]
                }]
            }]
        }]
    }

    file_path = tmp_path / "cascade.json"
    file_path.write_text(json.dumps(data))
    CONFIG["file"] = file_path

    result = cli_runner.invoke(app, ["complete"])
    assert result.exit_code == 0

    # Verify cascade
    updated = json.loads(file_path.read_text())
    task = updated["backlog"][0]["milestones"][0]["tasks"][0]
    milestone = updated["backlog"][0]["milestones"][0]
    phase = updated["backlog"][0]

    assert task["status"] == "Complete"
    assert milestone["status"] == "Complete"
    assert phase["status"] == "Complete"

def test_no_active_subtask(cli_runner, tmp_path):
    """Test error when all subtasks are complete."""
    data = {
        "backlog": [{
            "type": "Phase", "id": "P1", "title": "P", "status": "Complete", "description": "",
            "milestones": [{
                "type": "Milestone", "id": "P1.M1", "title": "M", "status": "Complete", "description": "",
                "tasks": [{
                    "type": "Task", "id": "P1.M1.T1", "title": "T", "status": "Complete", "description": "",
                    "subtasks": [
                        {"type": "Subtask", "id": "P1.M1.T1.S1", "title": "S1",
                         "status": "Complete", "story_points": 1, "dependencies": []}
                    ]
                }]
            }]
        }]
    }

    file_path = tmp_path / "done.json"
    file_path.write_text(json.dumps(data))
    CONFIG["file"] = file_path

    result = cli_runner.invoke(app, ["complete"])
    assert result.exit_code == 1
    assert "No active subtask" in result.output
```

**Verification**: Run `pytest tests/ -v` from `/home/dustin/projects/ai-scripts/tasks/`

---

## Validation Gates

### Pre-Implementation Checklist
- [ ] Read existing `tsk.py` completely (lines 1-267)
- [ ] Understand `find_next_active()` return structure
- [ ] Understand ID parsing pattern (P1.M1.T1.S1)
- [ ] Review test-tasks.json for sample data structure

### Post-Implementation Validation

```bash
# Navigate to tasks directory
cd /home/dustin/projects/ai-scripts/tasks

# 1. Verify commands exist
./tsk.py --help
# Expected: plan, research, ready, implement, fail, complete in output

# 2. Test simple status update
./tsk.py test-tasks.json status
./tsk.py test-tasks.json plan
./tsk.py test-tasks.json status
# Expected: Status changes to Planned

# 3. Test cascade (need proper test data)
# Create test file with one incomplete subtask
./tsk.py test-cascade.json complete
# Expected: Subtask + parents marked Complete

# 4. Run tests
pip install pytest  # if not installed
pytest tests/ -v

# 5. Verify no regressions
./tsk.py test-tasks.json next
./tsk.py test-tasks.json status --full
```

### Final Validation Checklist
- [ ] All 6 new commands appear in `--help`
- [ ] `tsk plan` updates current subtask to Planned
- [ ] `tsk research` updates current subtask to Researching
- [ ] `tsk ready` updates current subtask to Ready
- [ ] `tsk implement` updates current subtask to Implementing
- [ ] `tsk fail` updates current subtask to Failed
- [ ] `tsk complete` updates current subtask to Complete
- [ ] `tsk complete` cascades to Task when all subtasks Complete
- [ ] `tsk complete` cascades to Milestone when all tasks Complete
- [ ] `tsk complete` cascades to Phase when all milestones Complete
- [ ] `tsk complete` stops cascade when sibling not Complete
- [ ] Error message shown when no active subtask
- [ ] All tests pass
- [ ] Existing commands (`next`, `status`, `update`, `init`) still work

---

## Confidence Score

**8/10** - High confidence for one-pass implementation success

**Factors supporting confidence:**
- Clear existing patterns to follow (typer commands, pydantic models)
- Well-documented algorithm with pseudocode
- Comprehensive test coverage plan
- Edge cases explicitly identified

**Factors reducing confidence:**
- First pytest setup in this codebase (may need dependency installation)
- ID parsing logic needs careful implementation
- Rich console output testing may need adjustment

---

## Notes for Implementing Agent

1. **Read First**: Study the existing `update` command pattern before implementing
2. **Test Data**: Use `test-tasks.json` for manual testing, create `tests/` directory for pytest
3. **Order Matters**: Implement helper functions BEFORE the commands that use them
4. **Console Output**: Follow existing pattern using `console.print()` with Rich markup
5. **Save Once**: In `complete` command, call `save_backlog()` AFTER propagation, not before
