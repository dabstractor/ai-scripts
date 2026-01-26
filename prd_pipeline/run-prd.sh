#!/usr/bin/env zsh

# --- 0. Nested Execution Guard ---
# Prevent agents from accidentally running this script during implementation
# Use a separate variable for nesting detection that can't be bypassed
if [[ -n "$PRP_PIPELINE_RUNNING" ]]; then
    # Only allow through if this is a LEGITIMATE recursive call (has PLAN_DIR set to a bugfix path)
    if [[ "$SKIP_BUG_FINDING" != "true" || "$PLAN_DIR" != *"bugfix"* ]]; then
        echo "[ERROR] PRP Pipeline is already running (PID: $PRP_PIPELINE_RUNNING). Nested execution blocked."
        echo "This script cannot be called from within an agent session."
        echo "[DEBUG] SKIP_BUG_FINDING='$SKIP_BUG_FINDING' PLAN_DIR='$PLAN_DIR' PWD='$PWD'"
        exit 1
    fi
fi
# Export for nesting detection - but DON'T export SKIP_BUG_FINDING (it's only for legitimate recursive calls)
export PRP_PIPELINE_RUNNING=$$

# --- 1. Environment Handling ---
unalias() { builtin unalias "$@" 2>/dev/null || true }

# Load your custom environment
[[ -f ~/.config/zsh/functions.zsh ]] && source ~/.config/zsh/functions.zsh
[[ -f ~/.config/zsh/aliases.zsh ]] && source ~/.config/zsh/aliases.zsh

# Ensure aliases are expanded in the script
setopt aliases

# --- 2. Subcommands ---

# Handle 'task' subcommand: prd task [args...] -> tsk -f <current_tasks_file> [args...]
if [[ "$1" == "task" ]]; then
    shift  # Remove 'task' from arguments

    # Check for -f override - if provided, pass through directly to tsk
    if [[ "$1" == "-f" ]]; then
        exec tsk "$@"
    fi

    # Configuration
    PLAN_DIR="${PLAN_DIR:-plan}"

    # Find the latest session
    get_latest_session() {
        find "$PLAN_DIR" -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null | sort -n | tail -1
    }

    # Check if tasks file has ACTIONABLE items (Planned/Researching/Ready/Implementing)
    # Failed items are NOT actionable - they require manual intervention or retry
    has_actionable_tasks() {
        local file=$1
        [[ ! -f "$file" ]] && return 1
        local actionable=$(jq '[.. | objects | select(.status? and (.status == "Planned" or .status == "Researching" or .status == "Ready" or .status == "Implementing"))] | length' "$file" 2>/dev/null)
        [[ "$actionable" != "0" ]]
    }

    SESSION_DIR=$(get_latest_session)
    if [[ -z "$SESSION_DIR" ]]; then
        print -P "%F{red}[ERROR]%f No session found in $PLAN_DIR"
        exit 1
    fi

    TASKS_FILE=""

    # Priority 1: Check for incomplete bugfix session (new format - preferred)
    if [[ -d "$SESSION_DIR/bugfix" ]]; then
        LATEST_BUGFIX=$(find "$SESSION_DIR/bugfix" -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null | sort -n | tail -1)
        if [[ -n "$LATEST_BUGFIX" && -f "$LATEST_BUGFIX/tasks.json" ]] && has_actionable_tasks "$LATEST_BUGFIX/tasks.json"; then
            TASKS_FILE="$LATEST_BUGFIX/tasks.json"
            print -P "%F{cyan}[prd task]%f Using bugfix tasks: bugfix/$(basename "$LATEST_BUGFIX")/tasks.json" >&2
        fi
    fi

    # Priority 2: Fall back to main session tasks
    if [[ -z "$TASKS_FILE" ]]; then
        TASKS_FILE="$SESSION_DIR/tasks.json"
        if [[ ! -f "$TASKS_FILE" ]]; then
            print -P "%F{red}[ERROR]%f No tasks.json found in $(basename "$SESSION_DIR")"
            exit 1
        fi
        print -P "%F{cyan}[prd task]%f Using main tasks: $(basename "$SESSION_DIR")/tasks.json" >&2
    fi

    # Run tsk with the correct tasks file
    exec tsk -f "$TASKS_FILE" "$@"
fi

# --- 3. Parameter Parsing ---
SCOPE="${SCOPE:-subtask}"  # Default to task-level
START_PHASE=1
START_MS=1
START_TASK=1
START_SUBTASK=1
PARALLEL_RESEARCH="${PARALLEL_RESEARCH:-false}"  # Optional parallel research for next item
ONLY_VALIDATE="${ONLY_VALIDATE:-false}" # Run only the validation step
ONLY_BUG_HUNT="${ONLY_BUG_HUNT:-false}" # Run only the bug finding step
SINGLE_SESSION="${SINGLE_SESSION:-false}" # Disable auto-flow between sessions
TARGET_SESSION="${TARGET_SESSION:-}"       # Manual session selection
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
        bug-hunt)    ONLY_BUG_HUNT=true ;;
        skip-bug-finding) SKIP_BUG_FINDING=true ;;
        single-session) SINGLE_SESSION=true ;;
        no-auto-flow)   SINGLE_SESSION=true ;;
        session)        TARGET_SESSION="${!OPTIND}"; OPTIND=$(( OPTIND + 1 )) ;;
        session=*)      TARGET_SESSION="${OPTARG#*=}" ;;
        *) print "Usage: $0 [--scope=...] [--phase=N] [--milestone=N] [--task=N] [--subtask=N] [--parallel-research] [--validate] [--bug-hunt] [--skip-bug-finding] [--single-session] [--session=N]"; exit 1 ;;
      esac ;;
    *) print "Usage: $0 [-s phase|milestone|task|subtask] [-p N] [-m N] [-t N] [-u N] [-r] [-v]
   Or: $0 [--scope=...] [--phase=N] [--milestone=N] [--task=N] [--subtask=N] [--parallel-research] [--validate] [--bug-hunt] [--skip-bug-finding] [--single-session] [--session=N]"; exit 1 ;;
  esac
done

# Validate scope
case $SCOPE in
  phase|milestone|task|subtask) ;;
  *) print -P "%F{red}[ERROR]%f Invalid scope: '$SCOPE'. Must be: phase, milestone, task, or subtask"; exit 1 ;;
esac

# --- 3. Configuration ---
AGENT="${AGENT:-pglp}"
BREAKDOWN_AGENT="${BREAKDOWN_AGENT:-$AGENT}"
TASKS_FILE="${TASKS_FILE:-tasks.json}"
PRD_FILE="${PRD_FILE:-PRD.md}"
PLAN_DIR="${PLAN_DIR:-plan}"

# MCP server configuration for PRP creation (web search for research)
# DISABLED 2026-01-25: Testing if MCP server causes research phase stalls
# if [[ "$AGENT" == "glp" ]]; then
#     PRP_AGENT_MCP_ARGS="--mcp-config=$(mcpp z-ai-web-search-prime)"
# else
#     PRP_AGENT_MCP_ARGS=""
# fi
PRP_AGENT_MCP_ARGS=""

# --- Session Management Functions ---

# Generate deterministic hash of PRD content
# Usage: hash_prd_content <file_path>
# Returns: First 12 chars of SHA256 hash
hash_prd_content() {
    local file_path=$1
    sha256sum "$file_path" | cut -c1-12
}

# Find all existing sessions
# Returns: Space-separated list of session directory names, sorted
get_all_sessions() {
    find "$PLAN_DIR" -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null | \
        xargs -n1 basename 2>/dev/null | sort -n
}

# Get the latest session number
# Returns: Integer (0 if no sessions)
get_latest_session_number() {
    local latest=$(get_all_sessions | tail -1)
    if [[ -z "$latest" ]]; then
        echo 0
    else
        echo "${latest%%_*}"
    fi
}

# Get session directory by number
# Usage: get_session_dir <number>
get_session_dir() {
    local num=$1
    local padded=$(printf "%03d" $num)
    find "$PLAN_DIR" -maxdepth 1 -type d -name "${padded}_*" 2>/dev/null | head -1
}

# Check if a session is complete
# Usage: is_session_complete <session_dir>
# Returns false (1) if:
#   - tasks.json doesn't exist or has ACTIONABLE items (Planned/Researching/Ready/Implementing)
#   - bugfix sessions exist with actionable items
# NOTE: Failed items do NOT make a session incomplete - they require explicit retry
is_session_complete() {
    local session_dir=$1
    local tasks_file="$session_dir/tasks.json"
    [[ ! -f "$tasks_file" ]] && return 1

    # Check if any items in main tasks are actionable (not Complete/Failed)
    local actionable=$(jq '[.. | objects | select(.status? and (.status == "Planned" or .status == "Researching" or .status == "Ready" or .status == "Implementing"))] | length' "$tasks_file" 2>/dev/null)
    [[ "$actionable" != "0" ]] && return 1

    # Check for actionable items in bugfix sessions (inside session dir)
    if [[ -d "$session_dir/bugfix" ]]; then
        local bugfix_session
        for bugfix_session in "$session_dir/bugfix"/[0-9]*_*(N); do
            [[ ! -d "$bugfix_session" ]] && continue
            # Check tasks.json in bugfix session
            if [[ -f "$bugfix_session/tasks.json" ]]; then
                actionable=$(jq '[.. | objects | select(.status? and (.status == "Planned" or .status == "Researching" or .status == "Ready" or .status == "Implementing"))] | length' "$bugfix_session/tasks.json" 2>/dev/null)
                [[ "$actionable" != "0" ]] && return 1
            fi
        done
    fi

    return 0
}

# Get hash from session's PRD snapshot
# Usage: get_session_hash <session_dir>
# Hashes the prd_snapshot.md file directly - the authoritative source of truth
get_session_hash() {
    local session_dir=$1
    local snapshot="$session_dir/prd_snapshot.md"

    if [[ -f "$snapshot" ]]; then
        hash_prd_content "$snapshot"
    else
        # No snapshot = no hash to compare
        echo ""
    fi
}

# Create new session directory
# Usage: create_session <number> <hash>
# Returns: Path to new session directory
create_session() {
    local num=$1
    local hash=$2
    local padded=$(printf "%03d" $num)
    local session_dir="$PLAN_DIR/${padded}_${hash}"

    # Guard: In bug fix mode (SKIP_BUG_FINDING=true), we should NOT be creating
    # sessions in the main plan/ directory - only in the bugfix subdirectory
    # Check if PLAN_DIR is the root plan directory (not a bugfix subdirectory)
    local plan_basename=$(basename "$PLAN_DIR")
    if [[ "$SKIP_BUG_FINDING" == "true" && "$plan_basename" == "plan" ]]; then
        print -P "%F{red}[ERROR]%f Attempted to create session in main plan/ during bug fix mode!"
        print -P "%F{red}[ERROR]%f This is a bug in the pipeline. PLAN_DIR should be the bugfix session."
        print -P "%F{yellow}[DEBUG]%f PLAN_DIR=$PLAN_DIR, SESSION_DIR=$SESSION_DIR, SKIP_BUG_FINDING=$SKIP_BUG_FINDING"
        exit 1
    fi

    # Additional guard: session_dir should contain "bugfix" if in bug fix mode
    if [[ "$SKIP_BUG_FINDING" == "true" && "$session_dir" != *"bugfix"* ]]; then
        print -P "%F{red}[ERROR]%f Bug fix session path doesn't contain 'bugfix': $session_dir"
        print -P "%F{yellow}[DEBUG]%f PLAN_DIR=$PLAN_DIR, SKIP_BUG_FINDING=$SKIP_BUG_FINDING"
        exit 1
    fi

    mkdir -p "$session_dir/architecture"
    echo "$session_dir"
}

# Determine current session state
# Sets: SESSION_STATE, CURRENT_SESSION_DIR, CURRENT_SESSION_NUM
determine_session_state() {
    local current_hash=$(hash_prd_content "$PRD_FILE")
    local latest_num=$(get_latest_session_number)

    if [[ $latest_num -eq 0 ]]; then
        SESSION_STATE="NO_SESSIONS"
        CURRENT_SESSION_DIR=""
        CURRENT_SESSION_NUM=0
        return
    fi

    local latest_dir=$(get_session_dir $latest_num)
    local latest_hash=$(get_session_hash "$latest_dir")

    CURRENT_SESSION_DIR="$latest_dir"
    CURRENT_SESSION_NUM=$latest_num

    if [[ "$current_hash" == "$latest_hash" ]]; then
        if is_session_complete "$latest_dir"; then
            SESSION_STATE="CURRENT_MATCH_COMPLETE"
        else
            SESSION_STATE="CURRENT_MATCH_INCOMPLETE"
        fi
    else
        if is_session_complete "$latest_dir"; then
            SESSION_STATE="PRD_CHANGED_SESSION_COMPLETE"
        else
            SESSION_STATE="PRD_CHANGED_SESSION_INCOMPLETE"
        fi
    fi
}

# Bug finding configuration
BUG_FINDER_AGENT="${BUG_FINDER_AGENT:-glp}"
BUG_RESULTS_FILE="${BUG_RESULTS_FILE:-TEST_RESULTS.md}"
BUGFIX_SCOPE="${BUGFIX_SCOPE:-subtask}"
SKIP_BUG_FINDING="${SKIP_BUG_FINDING:-false}"

# --- Staged PRD Change Detection ---
# Check if PRD.md has staged changes and classify them before proceeding
check_staged_prd_changes() {
    # Only check if we're in a git repo and PRD exists
    [[ ! -d ".git" ]] && return 0
    [[ ! -f "$PRD_FILE" ]] && return 0

    # Check if PRD.md is in the staging area
    if ! git diff --cached --name-only | grep -q "^PRD\.md$"; then
        return 0  # PRD not staged, nothing to do
    fi

    print -P "%F{yellow}[PRD CHECK]%f Detected staged changes to PRD.md"

    # Get the diff for analysis
    local PRD_DIFF=$(git diff --cached "$PRD_FILE")

    if [[ -z "$PRD_DIFF" ]]; then
        return 0  # No actual diff content
    fi

    print -P "%F{cyan}[PRD CHECK]%f Analyzing changes..."

    local CLASSIFY_PROMPT="Analyze this git diff of a Product Requirements Document (PRD.md).

DIFF:
$PRD_DIFF

CLASSIFICATION RULES:
- COSMETIC: Only whitespace, formatting, markdown table alignment, blank lines, typo fixes, or rewording that doesn't change requirements
- SUBSTANTIVE: Any change to actual requirements, features, constraints, scope, acceptance criteria, or technical specifications

Output ONLY one word: COSMETIC or SUBSTANTIVE"

    local RESULT=$(claude --print --allowed-tools "" --system-prompt "You are a binary classifier for PRD changes. Output only COSMETIC or SUBSTANTIVE." "$CLASSIFY_PROMPT" 2>/dev/null)
    local CLEAN_RESULT=$(echo "$RESULT" | tr -d '[:space:]')

    # Retry if invalid response
    if [[ "$CLEAN_RESULT" != "COSMETIC" && "$CLEAN_RESULT" != "SUBSTANTIVE" ]]; then
        print -P "%F{yellow}[RETRY]%f Invalid response: '$RESULT'. Retrying..."
        RESULT=$(claude --print --continue --allowed-tools "" "ERROR: You replied with '$RESULT'. Output exactly one word: COSMETIC or SUBSTANTIVE." 2>/dev/null)
        CLEAN_RESULT=$(echo "$RESULT" | tr -d '[:space:]')
    fi

    print -P "%F{cyan}[PRD CHECK]%f Classification: $CLEAN_RESULT"

    if [[ "$CLEAN_RESULT" == "SUBSTANTIVE" ]]; then
        print -P "%F{red}[PRD CHECK]%f Substantive PRD changes detected!"
        print -P "%F{yellow}[PRD CHECK]%f Removing PRD.md from staging area."
        print -P "%F{yellow}[PRD CHECK]%f To apply PRD changes, commit other files first, then run the pipeline to handle PRD changes properly."
        git reset HEAD "$PRD_FILE" >/dev/null 2>&1
        print -P "%F{green}[PRD CHECK]%f PRD.md unstaged. Other staged files remain."
    elif [[ "$CLEAN_RESULT" == "COSMETIC" ]]; then
        print -P "%F{green}[PRD CHECK]%f Cosmetic changes only. Updating snapshot..."
        # Find current session and update its snapshot
        local latest_num=$(get_latest_session_number)
        if [[ $latest_num -gt 0 ]]; then
            local latest_dir=$(get_session_dir $latest_num)
            if [[ -d "$latest_dir" ]]; then
                cp "$PRD_FILE" "$latest_dir/prd_snapshot.md"
                print -P "%F{green}[PRD CHECK]%f Snapshot updated in $(basename "$latest_dir")"
            fi
        fi
    else
        print -P "%F{yellow}[PRD CHECK]%f Could not classify changes. Proceeding without action."
    fi
}

# Run the staged PRD check
check_staged_prd_changes

# --- Session State Resolution ---
# Must happen before bug hunt auto-detect so paths are correct

# Initialize session variables
SESSION_STATE=""
CURRENT_SESSION_DIR=""
CURRENT_SESSION_NUM=0
PREV_SESSION_DIR=""
INTEGRATE_CHANGES=false
QUEUE_DELTA=false
CREATE_DELTA=false
SKIP_EXECUTION_LOOP=false

# Bug fix mode: PLAN_DIR is already the session, use it directly
# This happens during recursive calls for bug fixes
if [[ "$SKIP_BUG_FINDING" == "true" && -d "$PLAN_DIR" ]]; then
    print -P "%F{magenta}[BUGFIX MODE]%f SKIP_BUG_FINDING=true, using PLAN_DIR as session"
    print -P "%F{cyan}[DEBUG]%f PLAN_DIR=$PLAN_DIR"
    SESSION_DIR="$PLAN_DIR"
    TASKS_FILE="$SESSION_DIR/tasks.json"
    # Copy PRD to session as prd_snapshot if not already there
    if [[ -f "$PRD_FILE" && ! -f "$SESSION_DIR/prd_snapshot.md" ]]; then
        cp "$PRD_FILE" "$SESSION_DIR/prd_snapshot.md"
    fi
    print -P "%F{cyan}[BUGFIX]%f Using session: $(basename "$SESSION_DIR")"

# Only resolve sessions if PRD exists (skip for --bug-hunt without PRD)
elif [[ -f "$PRD_FILE" ]]; then
    # Handle manual session selection first
    if [[ -n "$TARGET_SESSION" ]]; then
        TARGET_DIR=$(get_session_dir "$TARGET_SESSION")
        if [[ -z "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
            print -P "%F{red}[ERROR]%f Session $TARGET_SESSION not found."
            print -P "%F{cyan}[INFO]%f Available sessions:"
            get_all_sessions | while read -r sess; do
                [[ -n "$sess" ]] && print "  - $sess"
            done
            exit 1
        fi
        CURRENT_SESSION_DIR="$TARGET_DIR"
        CURRENT_SESSION_NUM="$TARGET_SESSION"
        SESSION_STATE="MANUAL_SELECTION"
        print -P "%F{cyan}[SESSION]%f Manually selected session: $(basename "$CURRENT_SESSION_DIR")"
    else
        determine_session_state
    fi

    case "$SESSION_STATE" in
        MANUAL_SELECTION)
            # Already handled above, just continue with selected session
            ;;

        NO_SESSIONS)
            print -P "%F{cyan}[SESSION]%f No existing sessions found. Creating first session..."
            CURRENT_SESSION_NUM=1
            CURRENT_SESSION_DIR=$(create_session 1 "$(hash_prd_content "$PRD_FILE")")
            cp "$PRD_FILE" "$CURRENT_SESSION_DIR/prd_snapshot.md"
            print -P "%F{green}[SESSION]%f Created: $(basename "$CURRENT_SESSION_DIR")"
            ;;

        CURRENT_MATCH_INCOMPLETE)
            print -P "%F{cyan}[SESSION]%f Resuming session: $(basename "$CURRENT_SESSION_DIR")"

            # Check if this is a delta session that never got its delta PRD generated
            if [[ -f "$CURRENT_SESSION_DIR/delta_from.txt" && ! -f "$CURRENT_SESSION_DIR/delta_prd.md" ]]; then
                local prev_session_num=$(cat "$CURRENT_SESSION_DIR/delta_from.txt")
                local prev_session_pattern=$(printf "%03d_*" "$prev_session_num")
                local prev_session_match=("$PLAN_DIR"/$prev_session_pattern(N))
                if [[ ${#prev_session_match[@]} -gt 0 && -d "${prev_session_match[1]}" ]]; then
                    PREV_SESSION_DIR="${prev_session_match[1]}"
                    CREATE_DELTA=true
                    print -P "%F{yellow}[DELTA]%f Delta PRD missing, will regenerate from session $prev_session_num"
                fi
            fi
            ;;

        CURRENT_MATCH_COMPLETE)
            print -P "%F{green}[SESSION]%f Session $(basename "$CURRENT_SESSION_DIR") is complete."
            if [[ "$SINGLE_SESSION" == "true" ]]; then
                if [[ "$SKIP_BUG_FINDING" == "false" || "$ONLY_BUG_HUNT" == "true" || "$ONLY_VALIDATE" == "true" ]]; then
                     print -P "%F{cyan}[SESSION]%f Session complete. Ready for validation/bug hunt."
                     read -q "choice?Start bug hunt / validation? [Y/n] "
                     print ""
                     if [[ "$choice" != "n" && "$choice" != "N" ]]; then
                         SKIP_EXECUTION_LOOP=true
                     else
                         print -P "%F{green}[DONE]%f Single-session mode. Exiting."
                         exit 0
                     fi
                else
                    print -P "%F{green}[DONE]%f Single-session mode. Exiting."
                    exit 0
                fi
            fi
            # Check for queued delta from previous run
            if [[ -f "$CURRENT_SESSION_DIR/.pending_delta_hash" ]]; then
                PENDING_HASH=$(cat "$CURRENT_SESSION_DIR/.pending_delta_hash")
                CURRENT_HASH=$(hash_prd_content "$PRD_FILE")
                if [[ "$PENDING_HASH" == "$CURRENT_HASH" ]]; then
                    print -P "%F{cyan}[SESSION]%f Processing queued delta..."
                    rm "$CURRENT_SESSION_DIR/.pending_delta_hash"
                    PREV_SESSION_DIR="$CURRENT_SESSION_DIR"
                    CURRENT_SESSION_NUM=$((CURRENT_SESSION_NUM + 1))
                    CURRENT_SESSION_DIR=$(create_session $CURRENT_SESSION_NUM "$CURRENT_HASH")
                    echo "$((CURRENT_SESSION_NUM - 1))" > "$CURRENT_SESSION_DIR/delta_from.txt"
                    cp "$PRD_FILE" "$CURRENT_SESSION_DIR/prd_snapshot.md"
                    print -P "%F{green}[SESSION]%f Created delta session: $(basename "$CURRENT_SESSION_DIR")"
                    CREATE_DELTA=true
                fi
            else
                if [[ "$SKIP_BUG_FINDING" == "false" || "$ONLY_BUG_HUNT" == "true" || "$ONLY_VALIDATE" == "true" ]]; then
                     print -P "%F{cyan}[SESSION]%f Session complete. Ready for validation/bug hunt."
                     read -q "choice?Start bug hunt / validation? [Y/n] "
                     print ""
                     if [[ "$choice" != "n" && "$choice" != "N" ]]; then
                         SKIP_EXECUTION_LOOP=true
                     else
                         print -P "%F{yellow}[SESSION]%f Nothing to do. PRD unchanged and session complete."
                         print -P "%F{cyan}[INFO]%f Modify PRD.md to create a new delta session, or use --session=N to revisit."
                         exit 0
                     fi
                else
                    print -P "%F{yellow}[SESSION]%f Nothing to do. PRD unchanged and session complete."
                    print -P "%F{cyan}[INFO]%f Modify PRD.md to create a new delta session, or use --session=N to revisit."
                    exit 0
                fi
            fi
            ;;

        PRD_CHANGED_SESSION_INCOMPLETE)
            print -P "%F{yellow}[SESSION]%f PRD has changed but session $(basename "$CURRENT_SESSION_DIR") is incomplete."
            print -P "%F{yellow}[QUESTION]%f How would you like to proceed?"
            print "  1) Integrate changes into current session (update tasks)"
            print "  2) Finish current session first, then start delta session"
            print "  3) Ignore changes (cosmetic/unrelated edits - update hash only)"
            read -r "choice?Select [1/2/3]: "

            case "$choice" in
                1)
                    INTEGRATE_CHANGES=true
                    print -P "%F{cyan}[SESSION]%f Will integrate changes into current session..."
                    # Update snapshot to reflect new PRD
                    cp "$PRD_FILE" "$CURRENT_SESSION_DIR/prd_snapshot.md"
                    print -P "%F{cyan}[SESSION]%f Updated prd_snapshot.md with current PRD"
                    ;;
                2)
                    QUEUE_DELTA=true
                    print -P "%F{cyan}[SESSION]%f Will queue delta for after current session completes..."
                    # Store the new PRD hash for later
                    echo "$(hash_prd_content "$PRD_FILE")" > "$CURRENT_SESSION_DIR/.pending_delta_hash"
                    ;;
                3)
                    print -P "%F{cyan}[SESSION]%f Acknowledging PRD change as non-impacting..."
                    # Update snapshot so future detection sees current PRD as baseline
                    cp "$PRD_FILE" "$CURRENT_SESSION_DIR/prd_snapshot.md"
                    print -P "%F{cyan}[SESSION]%f Updated snapshot. Continuing with current tasks."
                    ;;
                *)
                    print -P "%F{red}[ERROR]%f Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
            ;;

        PRD_CHANGED_SESSION_COMPLETE)
            print -P "%F{cyan}[SESSION]%f Previous session complete. PRD has changed."
            print -P "%F{cyan}[SESSION]%f Creating delta session for changes..."

            PREV_SESSION_DIR="$CURRENT_SESSION_DIR"
            CURRENT_SESSION_NUM=$((CURRENT_SESSION_NUM + 1))
            CURRENT_SESSION_DIR=$(create_session $CURRENT_SESSION_NUM "$(hash_prd_content "$PRD_FILE")")
            echo "$((CURRENT_SESSION_NUM - 1))" > "$CURRENT_SESSION_DIR/delta_from.txt"
            cp "$PRD_FILE" "$CURRENT_SESSION_DIR/prd_snapshot.md"

            print -P "%F{green}[SESSION]%f Created delta session: $(basename "$CURRENT_SESSION_DIR")"
            CREATE_DELTA=true
            ;;
    esac

    # Update path variables to use session directory
    SESSION_DIR="$CURRENT_SESSION_DIR"

    # Only update TASKS_FILE if it's the default "tasks.json", otherwise respect the passed file (e.g. for bugfixes)
    if [[ "$TASKS_FILE" == "tasks.json" ]]; then
        TASKS_FILE="$SESSION_DIR/tasks.json"
    fi
fi

# Auto-detect bug hunt cycle: check for actionable bug hunt tasks
# Sets RESUME_BUGFIX_TASKS_FILE if found, so bug hunt section can resume properly
# NOTE: Failed items do NOT trigger auto-resume - use `tsk next --failed` to retry them
RESUME_BUGFIX_TASKS_FILE=""
RESUME_BUGFIX_SESSION=""

if [[ "$ONLY_BUG_HUNT" == "false" && "$SKIP_BUG_FINDING" == "false" && -n "$SESSION_DIR" ]]; then
    # Helper to check if a tasks file has actionable items (not Complete/Failed)
    has_actionable_bugfix_tasks() {
        local file=$1
        [[ ! -f "$file" ]] && return 1
        local actionable=$(jq '[.. | objects | select(.status? and (.status == "Planned" or .status == "Researching" or .status == "Ready" or .status == "Implementing"))] | length' "$file" 2>/dev/null)
        [[ "$actionable" != "0" ]]
    }

    # Priority 1: Check for actionable bugfix sessions (new format - preferred)
    if [[ -d "$SESSION_DIR/bugfix" ]]; then
        LATEST_BUGFIX=$(find "$SESSION_DIR/bugfix" -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null | sort -n | tail -1)
        if [[ -n "$LATEST_BUGFIX" && -f "$LATEST_BUGFIX/tasks.json" ]] && has_actionable_bugfix_tasks "$LATEST_BUGFIX/tasks.json"; then
            print -P "%F{yellow}[AUTO-DETECT]%f Found actionable bugfix session: bugfix/$(basename "$LATEST_BUGFIX")"
            ONLY_BUG_HUNT=true
            RESUME_BUGFIX_TASKS_FILE="$LATEST_BUGFIX/tasks.json"
            RESUME_BUGFIX_SESSION="$LATEST_BUGFIX"
        fi
    fi
fi

# Load file contents only if they exist (avoids errors during --bug-hunt mode)
PRD_CONTENT=""
[[ -f "$PRD_FILE" ]] && PRD_CONTENT=$(cat "$PRD_FILE")
TASKS_CONTENT=""
[[ -f "$TASKS_FILE" ]] && TASKS_CONTENT=$(cat "$TASKS_FILE")

# Wrapper for tsk command to always use the correct tasks file
# Defined early so auto-resume can use it
tsk_cmd() {
    tsk -f "$TASKS_FILE" "$@"
}

# Auto-resume logic
# Use bug hunt tasks file if resuming a bug fix, otherwise use main tasks
AUTO_RESUME_TASKS_FILE="$TASKS_FILE"
if [[ -n "$RESUME_BUGFIX_TASKS_FILE" && -f "$RESUME_BUGFIX_TASKS_FILE" ]]; then
    AUTO_RESUME_TASKS_FILE="$RESUME_BUGFIX_TASKS_FILE"
fi

# Clean up orphaned "Researching" items that don't have a PRP
# These occur when parallel research was started but never completed
cleanup_orphan_researching() {
    local tasks_file=$1
    local session_dir=$2
    [[ ! -f "$tasks_file" ]] && return

    # Find all items with status "Researching"
    local researching_items=$(jq -r '.. | objects | select(.status? == "Researching") | .id // empty' "$tasks_file" 2>/dev/null)

    for item_id in $researching_items; do
        # Convert ID to directory name (P3.M1.T2.S1 -> P3M1T2S1)
        local dirname=$(echo "$item_id" | tr -d '.')
        local prp_path="$session_dir/$dirname/PRP.md"

        # If no PRP exists, this is an orphan - reset to Planned
        if [[ ! -f "$prp_path" ]]; then
            print -P "%F{yellow}[CLEANUP]%f Resetting orphan item $item_id (no PRP.md) to Planned"
            tsk -f "$tasks_file" update "$item_id" Planned 2>/dev/null
        fi
    done
}

if [[ "$MANUAL_START" == "false" && -f "$AUTO_RESUME_TASKS_FILE" ]]; then
    # Clean up orphans before finding next item
    cleanup_orphan_researching "$AUTO_RESUME_TASKS_FILE" "$SESSION_DIR"

    # Note: -s must come BEFORE the subcommand for commander.js to parse it as a global option
    NEXT_ITEM=$(tsk -f "$AUTO_RESUME_TASKS_FILE" -s "$SCOPE" next 2>/dev/null)
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
*   **PERSISTENCE:** You must store architectural findings in \`$SESSION_DIR/architecture/\` so the downstream PRP (Product Requirement Prompt) agents have access to them.

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
    *   **Store** findings in \`$SESSION_DIR/architecture/\` (e.g., \`system_context.md\`, \`external_deps.md\`).
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
                  "context_scope": "CONTRACT DEFINITION:\n1. RESEARCH NOTE: [Finding from $SESSION_DIR/architecture/ regarding this feature].\n2. INPUT: [Specific data structure/variable] from [Dependency ID].\n3. LOGIC: Implement [PRD Section X] logic. Mock [Service Y] for isolation.\n4. OUTPUT: Return [Result Object/Interface] for consumption by [Next Subtask ID]."
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

## FORBIDDEN OPERATIONS - CRITICAL

**You are a TASK BREAKDOWN agent. You create the task hierarchy ONLY.**

### NEVER MODIFY:
- \`PRD.md\` - The product requirements document (READ-ONLY, owned by humans)
- \`.gitignore\` - Never modify gitignore
- Source code files - you are planning, not implementing
- Any existing tasks.json in other directories - create ONLY at specified path

### YOUR OUTPUT:
You write ONLY to \`$TASKS_FILE\` and \`$SESSION_DIR/architecture/\`.
Nothing else. Do not modify any other files.
EOF

read -r -d '' TASK_BREAKDOWN_PROMPT <<EOF
# PROJECT INITIATION

**INPUT DOCUMENTATION (PRD):**
$PRD_CONTENT

**INSTRUCTIONS:**
1.  **Analyze** the PRD above.
2.  **Spawn** subagents immediately to research the current codebase state and external documentation. validate that the PRD is feasible and identify architectural patterns to follow.
3.  **Store** your high-level research findings in the \`$SESSION_DIR/architecture/\` directory. This is critical: the downstream PRP agents will rely on this documentation to generate implementation plans.
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

## FORBIDDEN OPERATIONS - CRITICAL

**You are a RESEARCH agent creating a PRP. You do NOT modify the codebase or pipeline.**

### NEVER MODIFY:
- \`PRD.md\` - The product requirements document (READ-ONLY, owned by humans)
- \`**/tasks.json\` - Any tasks.json file anywhere (owned by orchestrator)
- \`**/prd_snapshot.md\` - Any PRD snapshots (owned by orchestrator)
- \`.gitignore\` - Never add plan/, PRD.md, or task files to gitignore
- Any source code files - you are researching, not implementing

### YOUR OUTPUT:
You write ONLY to the PRP.md file path specified in your instructions.
You may also write research notes to the research/ subdirectory of the work item.
Nothing else. Do not modify any other files.

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

- docfile: [$SESSION_DIR/ai_docs/domain_specific.md]
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

## FORBIDDEN OPERATIONS - CRITICAL

**You are an IMPLEMENTATION agent. You implement the PRP. You do NOT manage the pipeline.**

The following files and directories are managed by the orchestration pipeline and you must NEVER read, modify, delete, move, or reference them in any way:

### NEVER MODIFY:
- \`PRD.md\` - The product requirements document (READ-ONLY, owned by humans)
- \`plan/\` - The entire plan directory and all contents (owned by orchestrator)
- \`**/tasks.json\` - Any tasks.json file anywhere (owned by orchestrator)
- \`**/prd_snapshot.md\` - Any PRD snapshots (owned by orchestrator)
- \`**/PRP.md\` - The PRP files in plan directories (you READ them, never WRITE them)
- \`**/TEST_RESULTS.md\` - Bug hunt results (owned by QA agent)

### NEVER ADD TO .gitignore:
- \`plan/\` or any subdirectory
- \`PRD.md\`
- Any \`*.json\` task files
- Any \`*.md\` documentation that is part of the project

### NEVER RUN:
- \`prd\`, \`run-prd.sh\`, or any pipeline/orchestration scripts
- Any command that would trigger the pipeline to run again
- \`tsk\` commands (the orchestrator handles task status)

### YOUR SCOPE:
You may ONLY modify files in the \`src/\`, \`tests/\`, \`lib/\`, or other **implementation directories**.
If you need to create configuration files, create them in the project root (not plan/).

**Violation of these rules will corrupt the entire pipeline state. You have been warned.**

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

## SESSION-SPECIFIC PATHS (CURRENT SESSION):
- Session directory: $SESSION_DIR
- Tasks file: $SESSION_DIR/tasks.json
- Bug report: $SESSION_DIR/TEST_RESULTS.md
- Architecture docs: $SESSION_DIR/architecture/
- Documentation: $SESSION_DIR/docs/

## CRITICAL - NEVER DELETE OR MOVE THESE FILES:
**IMPORTANT**: The following files are CRITICAL to the pipeline and must NEVER be deleted, moved, or modified:
- **$SESSION_DIR/tasks.json** - Pipeline state tracking (NEVER DELETE OR MOVE)
- **$SESSION_DIR/prd_snapshot.md** - PRD snapshot for this session (NEVER DELETE OR MOVE)
- **$SESSION_DIR/delta_prd.md** - Delta PRD for incremental sessions (NEVER DELETE OR MOVE)
- **$SESSION_DIR/delta_from.txt** - Delta session linkage (NEVER DELETE OR MOVE)
- **PRD.md** - Product requirements document in project root (NEVER DELETE OR MOVE)
- **$SESSION_DIR/TEST_RESULTS.md** - Bug report file (NEVER DELETE OR MOVE)
- Any file matching \`*tasks*.json\` pattern (NEVER DELETE OR MOVE)
- Any file directly in $SESSION_DIR/ root (NEVER MOVE to subdirectories)

If you delete any of the above files, the entire pipeline will break. Do NOT delete them under any circumstances.

## DO NOT DELETE OR MODIFY:
1. The session directory structure: $SESSION_DIR/
2. The '$TASKS_FILE' file (CRITICAL - this is the pipeline state)
3. README.md and any readme-adjacent files (CONTRIBUTING.md, LICENSE, etc.)

## DOCUMENTATION ORGANIZATION:
First, ensure session docs directory exists: \`mkdir -p $SESSION_DIR/docs\`

Then, MOVE (not delete) any markdown documentation files you created during implementation to \`$SESSION_DIR/docs/\`:
- Research notes, design docs, architecture documentation
- Implementation notes or technical writeups
- Reference documentation or guides
- Any other .md files that are not core project files

## KEEP IN ROOT:
Only these types of files should remain in the project root:
- README.md and readme-adjacent files (CONTRIBUTING.md, LICENSE, etc.)
- PRD.md (the human-edited source document)
- Core config files (package.json, tsconfig.json, etc.)
- Build and script files

**IMPORTANT**: Any files that are ALREADY COMMITTED into the repository must NOT be deleted.
Run \`git ls-files\` to see what's tracked. If a file is tracked by git, DO NOT DELETE IT.
Only delete files that are untracked AND clearly temporary/scratch files.

## DELETE OR GITIGNORE:
We are preparing to commit. Ensure the repo is clean.

1. **Delete**:
   - Temporary files clearly marked as temp or scratch
   - Duplicate files
   - Files that serve no ongoing purpose

2. **Gitignore** - ONLY add these standard entries if they're missing:
   - Build artifacts (dist/, build/)
   - Dependency directories (node_modules/, venv/)
   - Environment files (.env)
   - OS-specific files (.DS_Store)

## FORBIDDEN OPERATIONS - CRITICAL

**You are a CLEANUP agent. You organize files. You do NOT modify pipeline state.**

### NEVER MODIFY OR DELETE:
- \`PRD.md\` - The product requirements document (NEVER TOUCH)
- \`plan/\` - NEVER create, delete, or modify plan directories
- \`**/tasks.json\` - NEVER touch any tasks.json file
- \`**/prd_snapshot.md\` - NEVER touch any prd_snapshot.md file
- \`**/TEST_RESULTS.md\` - NEVER touch bug report files

### NEVER ADD TO .gitignore:
- \`plan/\` or any subdirectory of plan
- \`PRD.md\`
- Any \`*.json\` task files
- Any pipeline-related files

### NEVER CREATE:
- New directories matching pattern \`[0-9]*_*\` (these are session directories)
- Any files in the plan/ directory

Your job is ONLY to organize documentation files into \$SESSION_DIR/docs/ and clean temporary files.
Nothing else.
EOF

# --- Delta Operation Prompts ---

read -r -d '' DELTA_PRD_GENERATION_PROMPT <<EOF
# Generate Delta PRD from Changes

You are analyzing changes between two versions of a PRD to create a focused delta PRD.

## CRITICAL: PROPORTIONAL SIZING

**The delta PRD size MUST be proportional to the actual change size.**

- 1-line change → 1-2 paragraph PRD, 1 task with 1-2 subtasks
- Small tweak (few lines) → Short PRD, 1 phase, 1 milestone, 1-3 tasks
- Medium feature addition → Medium PRD, 1 phase, 1-2 milestones
- Large new feature → Full PRD structure

**If you produce a 9-phase PRD for a 3-line change, you have FAILED.**

Count the actual lines/words changed. Match your output complexity to input complexity.

## Previous PRD (Completed Session):
\$(cat "$PREV_SESSION_DIR/prd_snapshot.md")

## Current PRD:
\$(cat "$PRD_FILE")

## Previous Session's Completed Tasks:
\$(cat "$PREV_SESSION_DIR/tasks.json")

## Previous Session's Architecture Research:
Check $PREV_SESSION_DIR/architecture/ for existing research that may still apply.

## Instructions:
1. **DIFF ANALYSIS**: Identify what ACTUALLY changed (count lines/words)
2. **SIZE CHECK**: Small diff = small PRD. Do NOT inflate scope.
3. **SCOPE DELTA**: Create a PRD focusing ONLY on:
   - New features/requirements added
   - Modified requirements (note what changed from original)
   - Removed requirements (note for awareness, but don't create tasks)
4. **REFERENCE COMPLETED WORK**: The previous session implemented the original PRD.
   - Reference existing implementations rather than re-implementing
   - If a modification affects completed work, note which files/functions need updates
5. **LEVERAGE PRIOR RESEARCH**: Check $PREV_SESSION_DIR/architecture/ for research that applies
   - Don't duplicate research that's already been done
6. **OUTPUT**: Write the delta PRD to \`$SESSION_DIR/delta_prd.md\`

**Remember: Minimal change = minimal PRD. Do NOT over-engineer.**
EOF

read -r -d '' TASK_UPDATE_PROMPT <<EOF
# Update Tasks for PRD Changes (Mid-Session Integration)

The PRD has changed while implementation is in progress. You need to update the task breakdown
to incorporate these changes without losing progress on work already completed.

## Original PRD Snapshot (from session start):
\$(cat "$SESSION_DIR/prd_snapshot.md")

## Updated PRD (current):
\$(cat "$PRD_FILE")

## Current Tasks State:
\$(cat "$TASKS_FILE")

## Instructions:

### 1. IDENTIFY CHANGES
Analyze the diff between the original and updated PRD:
- What's new? (entirely new requirements)
- What's modified? (changed requirements)
- What's removed? (deleted requirements)

### 2. IMPACT ANALYSIS
For each change, determine which existing tasks are affected:
- Tasks for removed requirements → Mark as "Obsolete"
- Tasks for modified requirements → Update description, potentially add subtasks
- New requirements → Add new tasks

### 3. PRIORITIZE UPDATES TO COMPLETED ITEMS
**CRITICAL**: If changes affect already-COMPLETED tasks:
- These get HIGHEST priority for re-implementation
- Add new subtasks under the completed task with status "Planned"
- Add a note in the task description: "UPDATE REQUIRED: [brief description]"
- The completed parent task keeps its status, but new subtasks are created

### 4. UPDATE TASK HIERARCHY
Modify \`$TASKS_FILE\` following these rules:
- **Preserve status** of unaffected tasks (do NOT reset completed work)
- **Add new phases/milestones/tasks/subtasks** for new requirements
- **Update descriptions** for modified requirements
- **Mark obsolete** tasks for removed requirements (status: "Obsolete")

### 5. MAINTAIN COHERENCE
Ensure the updated task hierarchy still makes sense:
- Dependencies should still be valid
- Context_scope should reference correct prior subtasks
- New tasks should integrate logically with existing structure

## Output

Update \`$TASKS_FILE\` in place. Use the same JSON structure as the existing file.

## JSON Schema Reference
The file must maintain this structure:
\`\`\`json
{
  "backlog": [
    {
      "type": "Phase",
      "id": "P[#]",
      "title": "...",
      "status": "Planned | Researching | Ready | Implementing | Complete | Failed | Obsolete",
      ...
    }
  ]
}
\`\`\`

## FORBIDDEN OPERATIONS - CRITICAL

**You are a TASK UPDATE agent. You modify the task hierarchy ONLY.**

### NEVER MODIFY:
- \`PRD.md\` - The product requirements document (READ-ONLY, owned by humans)
- \`.gitignore\` - Never modify gitignore
- Source code files - you are planning, not implementing
- \`prd_snapshot.md\` - You read this for comparison only

### YOUR OUTPUT:
You modify ONLY \`$TASKS_FILE\` as specified.
Nothing else. Do not modify any other files.
EOF

read -r -d '' PREVIOUS_SESSION_CONTEXT_PROMPT <<EOF
### PREVIOUS SESSION AWARENESS
**CRITICAL**: Documentation from previous sessions exists and takes PRIORITY over web searches.

Previous session directory: $PREV_SESSION_DIR

When researching for this delta session:
1. **FIRST** check \`$PREV_SESSION_DIR/architecture/\` for existing research
2. **FIRST** check \`$PREV_SESSION_DIR/docs/\` for implementation notes
3. Reference completed work from previous sessions instead of re-researching
4. Build upon existing patterns and decisions
5. Only do web searches for genuinely NEW topics not covered in prior sessions
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

## FORBIDDEN OPERATIONS - CRITICAL

**You are a VALIDATION agent. You test and report. You do NOT fix code or modify the pipeline.**

### NEVER MODIFY:
- \`PRD.md\` - The product requirements document (READ-ONLY)
- \`plan/\` - The entire plan directory and all contents
- \`**/tasks.json\` - Any tasks.json file anywhere
- \`.gitignore\` - Never add plan/, PRD.md, or task files to gitignore
- Source code files - you are validating, not implementing

### YOUR OUTPUT:
You write ONLY to \`./validate.sh\` and \`./validation_report.md\`.
Nothing else. Do not modify any other files.
EOF

read -r -d '' BUG_FINDING_PROMPT <<EOF
# Creative Bug Finding - End-to-End PRD Validation

You are a creative QA engineer and bug hunter. Your mission is to rigorously test the implementation against the original PRD scope and find any issues that the standard validation might have missed.

## Inputs

**Original PRD:**
\$(cat "$PRD_FILE")

**Completed Tasks:**
\$(cat "$TASKS_FILE")

## Your Mission

### Phase 1: PRD Scope Analysis
1. Read and deeply understand the original PRD requirements
2. Map each requirement to what should have been implemented
3. Identify the expected user journeys and workflows
4. Note any edge cases or corner cases implied by the requirements

### Phase 2: Creative End-to-End Testing
Think like a user, then think like an adversary. Test the implementation:

1. **Happy Path Testing**: Does the primary use case work as specified?
2. **Edge Case Testing**: What happens at boundaries? (empty inputs, max values, unicode, special chars)
3. **Workflow Testing**: Can a user complete the full journey described in the PRD?
4. **Integration Testing**: Do all the pieces work together correctly?
5. **Error Handling**: What happens when things go wrong? Are errors graceful?
6. **State Testing**: Does the system handle state transitions correctly?
7. **Concurrency Testing** (if applicable): What if multiple operations happen at once?
8. **Regression Testing**: Did fixing one thing break another?

### Phase 3: Adversarial Testing
Think creatively about what could go wrong:

1. **Unexpected Inputs**: What inputs did the PRD not explicitly define?
2. **Missing Features**: What did the PRD ask for that might not be implemented?
3. **Incomplete Features**: What is partially implemented but not fully working?
4. **Implicit Requirements**: What should obviously work but wasn't explicitly stated?
5. **User Experience Issues**: Is the implementation usable and intuitive?

### Phase 4: Documentation as Bug Report

Write a structured bug report to \`\$BUG_RESULTS_FILE\` that can be used as a PRD for fixes:

\`\`\`markdown
# Bug Fix Requirements

## Overview
Brief summary of testing performed and overall quality assessment.

## Critical Issues (Must Fix)
Issues that prevent core functionality from working.

### Issue 1: [Title]
**Severity**: Critical
**PRD Reference**: [Which section/requirement]
**Expected Behavior**: What should happen
**Actual Behavior**: What actually happens
**Steps to Reproduce**: How to see the bug
**Suggested Fix**: Brief guidance on resolution

## Major Issues (Should Fix)
Issues that significantly impact user experience or functionality.

### Issue N: [Title]
[Same format as above]

## Minor Issues (Nice to Fix)
Small improvements or polish items.

### Issue N: [Title]
[Same format as above]

## Testing Summary
- Total tests performed: X
- Passing: X
- Failing: X
- Areas with good coverage: [list]
- Areas needing more attention: [list]
\`\`\`

## Important Guidelines

1. **Be Thorough**: Test everything you can think of
2. **Be Creative**: Think outside the box - what would a real user do?
3. **Be Specific**: Provide exact reproduction steps for every bug
4. **Be Constructive**: Frame issues as improvements, not criticisms
5. **Prioritize**: Focus on what matters most to users
6. **Document Everything**: Even if you're not sure it's a bug, note it

## Output - IMPORTANT

**It is IMPORTANT that you follow these rules exactly:**

- **If you find Critical or Major bugs**: You MUST write the bug report to \`\$BUG_RESULTS_FILE\`. It is imperative that actionable bugs are documented.
- **If you find NO Critical or Major bugs**: Do NOT write any file. Do NOT create \`\$BUG_RESULTS_FILE\`. Leave no trace. The absence of the file signals success.

This is imperative. The presence or absence of the bug report file controls the entire bugfix pipeline. Writing an empty or "no bugs found" file will cause unnecessary work. Not writing the file when there ARE bugs will cause bugs to be missed.

## FORBIDDEN OPERATIONS - CRITICAL

**You are a BUG HUNTER agent. You test and report bugs. You do NOT fix code or modify the pipeline.**

### NEVER MODIFY:
- \`PRD.md\` - The product requirements document (READ-ONLY)
- \`plan/\` - The entire plan directory and all contents
- \`**/tasks.json\` - Any tasks.json file anywhere
- \`.gitignore\` - Never add plan/, PRD.md, or task files to gitignore
- Source code files - you are hunting bugs, not fixing them

### YOUR OUTPUT:
You write ONLY to \`\$BUG_RESULTS_FILE\` (if bugs are found).
Nothing else. Do not modify any other files.
EOF

# Bug Fix Task Breakdown - SIMPLE flat structure for bug fixes
# This is intentionally simpler than the full TASK_BREAKDOWN_SYSTEM_PROMPT
read -r -d '' BUG_FIX_BREAKDOWN_SYSTEM_PROMPT <<'EOF'
# Bug Fix Task Breakdown Agent

You convert bug reports into a SIMPLE, FLAT task list. Bug fixes do NOT need phases, milestones, or complex hierarchies.

## Output Format

Create a SINGLE phase with ONE milestone containing ONE task per bug. Each bug = one task with 1-3 subtasks max.

```json
{
  "backlog": [
    {
      "type": "Phase",
      "id": "P1",
      "title": "Bug Fixes",
      "status": "Planned",
      "milestones": [
        {
          "type": "Milestone",
          "id": "P1.M1",
          "title": "Critical and Major Bug Fixes",
          "status": "Planned",
          "tasks": [
            {
              "type": "Task",
              "id": "P1.M1.T1",
              "title": "[Bug title from report]",
              "status": "Planned",
              "subtasks": [
                {
                  "type": "Subtask",
                  "id": "P1.M1.T1.S1",
                  "title": "Fix [specific issue]",
                  "status": "Planned",
                  "story_points": 1,
                  "context_scope": "Fix: [brief description]. File: [file path]. Change: [what to change]."
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

## Rules

1. **ONE task per bug** - Do not split a single bug into multiple tasks
2. **1-3 subtasks per task MAX** - Keep it simple
3. **Small story points** - 0.5 to 2 points per subtask
4. **Direct context_scope** - Just say what file to change and how
5. **NO research tasks** - Bug reports already contain the research
6. **NO documentation tasks** - Just fix the bugs
7. **Critical bugs first** - Order tasks by severity

## FORBIDDEN OPERATIONS - CRITICAL

**You are a BUG FIX BREAKDOWN agent. You create a simple task list ONLY.**

### NEVER MODIFY:
- `PRD.md` - The product requirements document (READ-ONLY)
- `.gitignore` - Never modify gitignore
- Source code files - you are planning, not implementing
- Any files except the tasks.json you are creating

### YOUR OUTPUT:
You write ONLY to the tasks.json file path specified.
Nothing else.
EOF

read -r -d '' BUG_FIX_BREAKDOWN_PROMPT <<EOF
# Bug Fix Task Breakdown

**BUG REPORT:**
\$(cat "\$PRD_FILE")

**INSTRUCTIONS:**
1. Read the bug report above
2. Create ONE task per Critical/Major bug (ignore Minor issues)
3. Each task should have 1-3 simple subtasks that directly fix the issue
4. Write the JSON to \`./\$TASKS_FILE\`

Keep it SIMPLE. This is bug fixing, not a new project.
EOF


# --- 4. Helpers ---

# Get the current status of an item from tsk
# Usage: get_item_status <id>
# Returns: The status string (Planned, Researching, Implementing, Complete, Failed) or empty if not found
get_item_status() {
    local id=$1
    # Get status as JSON and extract the status for this specific item
    # Suppress jq errors in case tsk returns non-JSON output
    tsk_cmd status -s "$SCOPE" 2>/dev/null | jq -r --arg iid "$id" '.[] | select(.id == $iid) | .status // empty' 2>/dev/null
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

# Find array index for a phase by its ID (handles delta sessions where P3 is at index 0)
# Usage: find_phase_idx <phase_num>
# Returns: array index via stdout, or -1 if not found
find_phase_idx() {
    local phase_num=$1
    local total=$(jq '.backlog | length' "$TASKS_FILE")
    for (( i=0; i<total; i++ )); do
        local pid=$(jq -r ".backlog[$i].id // empty" "$TASKS_FILE")
        if [[ "$pid" == "P$phase_num" ]]; then
            echo $i
            return 0
        fi
    done
    echo -1
    return 1
}

# Get item title from tasks.json
# Usage: get_item_title <phase_num> <milestone_num> <task_num> <subtask_num>
get_item_title() {
    local phase_num=$1
    local milestone_num=$2
    local task_num=$3
    local subtask_num=$4
    local phase_idx=$(find_phase_idx $phase_num)
    [[ $phase_idx -lt 0 ]] && return 1
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
    local phase_idx=$(find_phase_idx $phase_num)
    [[ $phase_idx -lt 0 ]] && return 1
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

    # Skip if item is already complete
    local item_status=$(get_item_status "$id")
    if [[ "$item_status" == "Complete" || "$item_status" == "Completed" ]]; then
        print -P "%F{yellow}[PARALLEL]%f $id already complete, skipping"
        return 0
    fi

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
    # Status: Researching (in progress) -> Ready (PRP created, ready to implement)
    # The orphan cleanup function handles cases where research fails before PRP is created
    (
        tsk -f "$TASKS_FILE" update "$id" Researching
        $AGENT $PRP_AGENT_MCP_ARGS -p "$PRP_CREATE_PROMPT Create a PRP for $(get_scope_name) $id of the PRD.

CRITICAL OUTPUT PATHS (use these EXACT paths):
- PRP file: $dirname/PRP.md
- Research files: $dirname/research/

DO NOT write files to any other location. All research MUST go in $dirname/research/ and the final PRP MUST be at $dirname/PRP.md.

<item_title>$(get_item_title $phase_num $ms_num $task_num $subtask_num)</item_title>
<item_description>$(get_item_description $phase_num $ms_num $task_num $subtask_num)</item_description>
<plan_status>$(tsk -f "$TASKS_FILE" status)</plan_status>$prev_context"
        if [[ ! -f "$dirname/PRP.md" ]]; then
            print -P "%F{yellow}[PARALLEL]%f PRP.md not found for $id, retrying..."
            $AGENT --continue -p "You didn't write the file. Make sure you write the file to $dirname/PRP.md"
        fi
        # Mark as Ready when PRP is successfully created, or exit with error
        if [[ -f "$dirname/PRP.md" ]]; then
            tsk -f "$TASKS_FILE" update "$id" Ready
        else
            print -P "%F{red}[PARALLEL]%f Background research FAILED for $id - no PRP created"
            exit 1
        fi
    ) &

    RESEARCH_PID=$!
    RESEARCH_ITEM_ID=$id
    RESEARCH_DIRNAME=$dirname
    print -P "%F{cyan}[PARALLEL]%f Background research started (PID: $RESEARCH_PID)"
}

# Wait for background research to complete if it matches the given item
# Handles: PRP ready, process died, process HUNG (alive but stuck)
# Usage: wait_for_background_research <id>
wait_for_background_research() {
    local id=$1
    local elapsed=0
    local max_wait=${RESEARCH_TIMEOUT:-600}  # 10 min max for hung processes

    if [[ -n "$RESEARCH_PID" && "$RESEARCH_ITEM_ID" == "$id" ]]; then
        print -P "%F{cyan}[PARALLEL]%f Waiting for $id (PID $RESEARCH_PID, max ${max_wait}s)..."

        while true; do
            # 1. Check if PRP exists - success
            if [[ -f "$RESEARCH_DIRNAME/PRP.md" ]]; then
                print -P "%F{green}[PARALLEL]%f PRP ready (${elapsed}s)"
                RESEARCH_PID=""
                RESEARCH_ITEM_ID=""
                RESEARCH_DIRNAME=""
                return 0
            fi

            # 2. Check if process died
            if ! kill -0 $RESEARCH_PID 2>/dev/null; then
                wait $RESEARCH_PID 2>/dev/null
                local exit_code=$?
                local saved_dirname="$RESEARCH_DIRNAME"
                RESEARCH_PID=""
                RESEARCH_ITEM_ID=""
                RESEARCH_DIRNAME=""

                if [[ -f "$saved_dirname/PRP.md" ]]; then
                    print -P "%F{green}[PARALLEL]%f Done (${elapsed}s)"
                    return 0
                else
                    print -P "%F{red}[PARALLEL]%f FAILED (exit $exit_code, ${elapsed}s) - retrying sync"
                    return 1
                fi
            fi

            # 3. Process alive - check timeout for HUNG processes
            if (( elapsed >= max_wait )); then
                print -P "%F{red}[PARALLEL]%f HUNG! PID $RESEARCH_PID alive but no PRP after ${elapsed}s - killing"
                kill -9 $RESEARCH_PID 2>/dev/null
                wait $RESEARCH_PID 2>/dev/null
                RESEARCH_PID=""
                RESEARCH_ITEM_ID=""
                RESEARCH_DIRNAME=""
                return 1
            fi

            # 4. Still waiting
            sleep 5
            elapsed=$((elapsed + 5))
            (( elapsed % 60 == 0 )) && print -P "%F{cyan}[PARALLEL]%f PID $RESEARCH_PID alive, ${elapsed}s/${max_wait}s..."
        done
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

    # Find actual array index for this phase (handles delta sessions)
    local phase_idx=$(find_phase_idx $phase_num)
    [[ $phase_idx -lt 0 ]] && return 1

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
        run_with_retry tsk_cmd update "$id" Implementing
    else
        run_with_retry tsk_cmd update "$id" Researching
        run_with_retry $AGENT $PRP_AGENT_MCP_ARGS -p "$PRP_CREATE_PROMPT Create a PRP for $(get_scope_name) $id of the PRD. Store it at $dirname/PRP.md.
<item_title>$(get_item_title $phase_num $ms_num $task_num $subtask_num)</item_title>
<item_description>$(get_item_description $phase_num $ms_num $task_num $subtask_num)</item_description>
<plan_status>$(tsk_cmd status)</plan_status>"
        if [[ ! -f "$dirname/PRP.md" ]]; then
            print -P "%F{yellow}[RETRY]%f PRP.md not found. Retrying..."
            $AGENT --continue -p "You didn't write the file. Make sure you write the file to $dirname/PRP.md"
        fi
        if [[ ! -f "$dirname/PRP.md" ]]; then
            print -P "%F{red}[FAILED]%f PRP creation failed for $id - marking as Failed and continuing"
            run_with_retry tsk_cmd update "$id" Failed
            return 1
        fi
        run_with_retry tsk_cmd update "$id" Implementing
    fi

    # Start background research for next item if parallel research is enabled
    if [[ "$PARALLEL_RESEARCH" == "true" ]]; then
        if get_next_item $phase_num $ms_num $task_num $subtask_num; then
            local next_id=$(generate_id $NEXT_PHASE $NEXT_MS $NEXT_TASK $NEXT_SUBTASK)
            local next_dirname="$SESSION_DIR/$(generate_dirname $NEXT_PHASE $NEXT_MS $NEXT_TASK $NEXT_SUBTASK)"
            # Pass current item as previous context so next item's research can reference it as a contract
            start_background_research "$next_id" "$next_dirname" $NEXT_PHASE $NEXT_MS $NEXT_TASK $NEXT_SUBTASK "$id" "$dirname"
        fi
    fi

    if ! run_with_retry $AGENT -p "$PRP_EXECUTE_PROMPT Execute the PRP for $(get_scope_name) $id. The PRP file is located at: $dirname/PRP.md. READ IT NOW."; then
        print -P "%F{red}[FAILED]%f Agent execution failed for $id - marking as Failed and continuing"
        run_with_retry tsk_cmd update "$id" Failed
        return 1
    fi

    git add $TASKS_FILE
    if [[ -z "$(git diff HEAD --name-only)" ]]; then
        print -P "%F{red}[FAILED]%f No changes produced for $id - marking as Failed and continuing"
        run_with_retry tsk_cmd update "$id" Failed
        return 1
    fi

    run_with_retry tsk_cmd update "$id" Complete

    print -P "%F{blue}[CLEANUP]%f Cleaning up $id..."
    run_with_retry $AGENT -p "$CLEANUP_PROMPT" || print -P "%F{yellow}[WARN]%f Cleanup failed, proceeding to commit..."

    smart_commit

    # Check if graceful shutdown was requested
    check_shutdown
}

# Simple retry logic with shutdown support
run_with_retry() {
    local n=1
    local max=3
    local delay=5

    while true; do
        # Check shutdown before starting new attempt
        if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
            return 130
        fi

        # Run command directly
        eval "${(q)@}"
        local exit_status=$?

        # Success
        if [[ $exit_status -eq 0 ]]; then
            return 0
        fi

        # Retry logic
        if (( n < max )); then
            print -P "%F{yellow}[RETRY]%f Command failed (exit $exit_status). Attempt $n/$max. Retrying in ${delay}s..."
            sleep $delay
            ((n++))
        else
            print -P "%F{red}[ERROR]%f Command failed after $max attempts"
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

# Bug Hunt Resume Mode - resume incomplete bug fix with existing tasks
# This runs BEFORE the if/elif to modify variables so main loop runs
if [[ "$ONLY_BUG_HUNT" == "true" && -n "$RESUME_BUGFIX_TASKS_FILE" ]]; then
    print -P "%F{cyan}[CONFIG]%f Running in %F{magenta}BUG FIX RESUME%f mode"

    # Set SESSION_DIR to the bugfix session so artifacts go to the right place
    if [[ -n "$RESUME_BUGFIX_SESSION" ]]; then
        SESSION_DIR="$RESUME_BUGFIX_SESSION"
        print -P "%F{cyan}[CONFIG]%f Bugfix session: %F{yellow}$(basename "$RESUME_BUGFIX_SESSION")%f"
    fi

    # Override TASKS_FILE to use the bug fix tasks
    TASKS_FILE="$RESUME_BUGFIX_TASKS_FILE"
    TASKS_CONTENT=$(cat "$TASKS_FILE")
    print -P "%F{cyan}[CONFIG]%f Tasks file: %F{yellow}$TASKS_FILE%f"

    # Clear ONLY_BUG_HUNT so main execution loop runs
    ONLY_BUG_HUNT=false
    SKIP_BUG_FINDING=true  # Don't run bug finding after - we're mid-fix
fi

# Bug Hunt Only Mode - skip to bug finding stage
if [[ "$ONLY_BUG_HUNT" == "true" ]]; then
    print -P "%F{cyan}[CONFIG]%f Running in %F{magenta}BUG HUNT ONLY%f mode"
    print -P "%F{cyan}[CONFIG]%f Bug finder agent: %F{yellow}$BUG_FINDER_AGENT%f"

    # Validate requirements
    if [[ ! -f "$PRD_FILE" ]]; then
        print -P "%F{red}[ERROR]%f $PRD_FILE not found. Need PRD to run bug discovery."
        exit 1
    fi
    if [[ ! -f "$TASKS_FILE" ]]; then
        print -P "%F{red}[ERROR]%f $TASKS_FILE not found. Need completed tasks to run bug discovery."
        exit 1
    fi
    # Skip to bug finding stage (handled at end of script)

elif [[ "$ONLY_VALIDATE" == "false" ]]; then

# Handle delta session: generate delta PRD first
if [[ "$CREATE_DELTA" == "true" && -n "$PREV_SESSION_DIR" ]]; then
    print -P "%F{magenta}[DELTA]%f Generating delta PRD from changes..."
    print -P "%F{cyan}[DELTA]%f Previous session: $(basename "$PREV_SESSION_DIR")"

    # Inject previous session context into the breakdown prompts
    DELTA_CONTEXT="
## PREVIOUS SESSION CONTEXT
Previous session directory: $PREV_SESSION_DIR
- Check $PREV_SESSION_DIR/architecture/ for existing research (PRIORITY over web searches)
- Check $PREV_SESSION_DIR/docs/ for implementation notes
- Reference completed work rather than re-researching
"

    # Run delta PRD generation
    run_with_retry $BREAKDOWN_AGENT -p "$DELTA_PRD_GENERATION_PROMPT

$PREVIOUS_SESSION_CONTEXT_PROMPT"

    # Retry if delta PRD wasn't created
    if [[ ! -f "$SESSION_DIR/delta_prd.md" ]]; then
        print -P "%F{yellow}[DELTA]%f delta_prd.md not found. Demanding agent write it..."
        run_with_retry $BREAKDOWN_AGENT --continue -p "You did NOT write the delta PRD file. You MUST write it to $SESSION_DIR/delta_prd.md immediately. This file is REQUIRED before we can proceed."
    fi

    # Final validation - FAIL if delta PRD is still missing
    if [[ -f "$SESSION_DIR/delta_prd.md" ]]; then
        print -P "%F{green}[DELTA]%f Delta PRD generated: $SESSION_DIR/delta_prd.md"
        # Use delta PRD as input for task breakdown
        PRD_CONTENT=$(cat "$SESSION_DIR/delta_prd.md")
    else
        print -P "%F{red}[ERROR]%f Delta PRD generation FAILED. Required file missing: $SESSION_DIR/delta_prd.md"
        print -P "%F{red}[ERROR]%f Cannot proceed with delta session without delta PRD."
        exit 1
    fi
fi

# Handle mid-session integration: update existing tasks
if [[ "$INTEGRATE_CHANGES" == "true" && -f "$TASKS_FILE" ]]; then
    print -P "%F{magenta}[UPDATE]%f Integrating PRD changes into existing tasks..."

    run_with_retry $AGENT -p "$TASK_UPDATE_PROMPT"

    print -P "%F{green}[UPDATE]%f Task hierarchy updated with PRD changes."

    # Commit the updated tasks
    git add "$TASKS_FILE" 2>/dev/null
    git commit -m "Update tasks for PRD changes (mid-session integration)" &>/dev/null || true
fi

# A. Task Breakdown (Only run if tasks.json is missing)
if [[ ! -f "$TASKS_FILE" ]]; then
    print -P "%F{magenta}[PHASE 0]%f Generating breakdown..."
    mkdir -p "$SESSION_DIR/architecture"
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
        git add "$TASKS_FILE" "$SESSION_DIR" 2>/dev/null
        git commit -m "Add task breakdown and architecture research" &>/dev/null || true
    fi
fi

# Verify tasks file exists before looping
[[ ! -f "$TASKS_FILE" ]] && print -P "%F{red}[ERROR]%f $TASKS_FILE not found after breakdown. Agent failed to write file." && exit 1

# Print current scope configuration
print -P "%F{cyan}[CONFIG]%f Scope: %F{yellow}$SCOPE%f (Default: task)"
[[ $BREAKDOWN_AGENT != "$AGENT" ]] && print -P "%F{cyan}[CONFIG]%f Breakdown agent: %F{yellow}$BREAKDOWN_AGENT%f"
print -P "%F{cyan}[CONFIG]%f Execution agent: %F{yellow}$AGENT%f"
[[ "$PARALLEL_RESEARCH" == "true" ]] && print -P "%F{cyan}[CONFIG]%f Parallel research: %F{green}enabled%f"
[[ "$SKIP_BUG_FINDING" == "true" ]] && print -P "%F{cyan}[CONFIG]%f Bug finding: %F{yellow}skipped%f" || print -P "%F{cyan}[CONFIG]%f Bug finder agent: %F{yellow}$BUG_FINDER_AGENT%f"
print -P "%F{cyan}[CONFIG]%f Starting positions: Phase=$START_PHASE"
[[ $SCOPE != "phase" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Milestone=$START_MS"
[[ $SCOPE == "task" || $SCOPE == "subtask" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Task=$START_TASK"
[[ $SCOPE == "subtask" ]] && print -P "%F{cyan}[CONFIG]%f Starting positions: Subtask=$START_SUBTASK"

# Validate tasks file before proceeding
if [[ ! -f "$TASKS_FILE" ]]; then
    print -P "%F{red}[ERROR]%f Tasks file not found: $TASKS_FILE"
    exit 1
fi

# Validate SESSION_DIR is set to prevent root directory writes
if [[ -z "$SESSION_DIR" ]]; then
    print -P "%F{red}[ERROR]%f SESSION_DIR is not set. PRD file or Session directory missing?"
    exit 1
fi

if ! jq empty "$TASKS_FILE" 2>/dev/null; then
    print -P "%F{red}[ERROR]%f Tasks file is not valid JSON: $TASKS_FILE"
    print -P "%F{yellow}[DEBUG]%f First 100 chars: $(head -c 100 "$TASKS_FILE")"
    exit 1
fi

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
        DIRNAME="$SESSION_DIR/$(generate_dirname $PHASE_NUM 1 1 1)"
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
            DIRNAME="$SESSION_DIR/$(generate_dirname $PHASE_NUM $MS_NUM 1 1)"
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
                DIRNAME="$SESSION_DIR/$(generate_dirname $PHASE_NUM $MS_NUM $TASK_NUM 1)"
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
                DIRNAME="$SESSION_DIR/$(generate_dirname $PHASE_NUM $MS_NUM $TASK_NUM $SUBTASK_NUM)"
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

# Final Validation Step (skip if bug-hunt only mode)
if [[ "$ONLY_BUG_HUNT" != "true" ]]; then
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
FINAL_TASK=$(tsk -f "$TASKS_FILE" -s "$SCOPE" next 2>/dev/null)
if [[ -n "$FINAL_TASK" ]]; then
    run_with_retry tsk_cmd update "$FINAL_TASK" Complete
fi

# Final smart commit after validation
print -P "%F{blue}[GIT]%f Committing final changes with smart commit..."
smart_commit

fi  # End of validation block (skip if bug-hunt only mode)

# --- Creative Bug Finding Stage ---
# Each bug hunt iteration creates its own session in bugfix/
if [[ "$SKIP_BUG_FINDING" == "false" ]]; then
    BUGFIX_DIR="${SESSION_DIR}/bugfix"
    mkdir -p "$BUGFIX_DIR"

    # Find or create bug hunt session
    # Check for actionable bug hunt session (has tasks in Planned/Researching/Ready/Implementing)
    get_latest_bugfix_session() {
        find "$BUGFIX_DIR" -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null | sort -n | tail -1
    }

    # Returns true (0) if session has no actionable items (all Complete or Failed)
    is_bugfix_session_complete() {
        local bugfix_dir=$1
        local tasks_file="$bugfix_dir/tasks.json"
        [[ ! -f "$tasks_file" ]] && return 1
        local actionable=$(jq '[.. | objects | select(.status? and (.status == "Planned" or .status == "Researching" or .status == "Ready" or .status == "Implementing"))] | length' "$tasks_file" 2>/dev/null)
        [[ "$actionable" != "0" ]] && return 1
        return 0
    }

    CURRENT_BUGFIX_SESSION=$(get_latest_bugfix_session)

    # Determine if we need a new session or should resume existing
    if [[ -n "$CURRENT_BUGFIX_SESSION" ]]; then
        if is_bugfix_session_complete "$CURRENT_BUGFIX_SESSION"; then
            # Previous session complete (or only has failures) - start fresh
            BUGFIX_NUM=$(( $(basename "$CURRENT_BUGFIX_SESSION" | cut -d_ -f1 | sed 's/^0*//') + 1 ))
            CURRENT_BUGFIX_SESSION=""
        else
            print -P "%F{yellow}[BUG HUNT]%f Resuming actionable bug hunt session: $(basename "$CURRENT_BUGFIX_SESSION")"
        fi
    fi

    # Create new session if needed
    if [[ -z "$CURRENT_BUGFIX_SESSION" ]]; then
        BUGFIX_NUM=${BUGFIX_NUM:-1}
        BUGFIX_HASH=$(date +%s | sha256sum | cut -c1-12)
        CURRENT_BUGFIX_SESSION="$BUGFIX_DIR/$(printf "%03d" $BUGFIX_NUM)_${BUGFIX_HASH}"
        mkdir -p "$CURRENT_BUGFIX_SESSION"
        print -P "%F{cyan}[BUG HUNT]%f Created bug hunt session: $(basename "$CURRENT_BUGFIX_SESSION")"
    fi

    BUG_RESULTS_FILE="$CURRENT_BUGFIX_SESSION/TEST_RESULTS.md"

    # --- Check for failed tasks from previous session ---
    # Priority: previous bugfix session > main session
    FAILED_TASKS_INFO=""
    PREVIOUS_SESSION_FOR_FAILURES=""

    # Find previous bugfix session (the most recent one that isn't the current session)
    # zsh arrays are 1-indexed
    ALL_BUGFIX_SESSIONS=("${(@f)$(find "$BUGFIX_DIR" -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null | sort -n)}")
    for session in "${(Oa)ALL_BUGFIX_SESSIONS[@]}"; do
        [[ -z "$session" ]] && continue
        if [[ "$session" != "$CURRENT_BUGFIX_SESSION" && -f "$session/tasks.json" ]]; then
            PREVIOUS_SESSION_FOR_FAILURES="$session"
            break
        fi
    done

    # If no previous bugfix session, check main session
    if [[ -z "$PREVIOUS_SESSION_FOR_FAILURES" ]]; then
        PREVIOUS_SESSION_FOR_FAILURES="$SESSION_DIR"
    fi

    # Check for failed tasks in the previous session
    if [[ -n "$PREVIOUS_SESSION_FOR_FAILURES" && -f "$PREVIOUS_SESSION_FOR_FAILURES/tasks.json" ]]; then
        FAILED_TASK_OUTPUT=$(tsk -f "$PREVIOUS_SESSION_FOR_FAILURES/tasks.json" next-failed 2>/dev/null || true)
        if [[ -n "$FAILED_TASK_OUTPUT" && "$FAILED_TASK_OUTPUT" != *"No failed tasks"* ]]; then
            # Count failed tasks
            FAILED_COUNT=$(jq '[.. | objects | select(.status? == "Failed")] | length' "$PREVIOUS_SESSION_FOR_FAILURES/tasks.json" 2>/dev/null || echo "0")
            if [[ "$FAILED_COUNT" -gt 0 ]]; then
                print -P "%F{yellow}[BUG HUNT]%f Found $FAILED_COUNT failed task(s) in previous session: $(basename "$PREVIOUS_SESSION_FOR_FAILURES")"
                FAILED_TASKS_INFO="
## Previously Failed Tasks - PRIORITY

The following tasks FAILED in the previous session and should be investigated as part of bug hunting:

**Source**: \`$(basename "$PREVIOUS_SESSION_FOR_FAILURES")/tasks.json\`
**Failed Count**: $FAILED_COUNT

\`\`\`json
$(jq '[.. | objects | select(.status? == "Failed")]' "$PREVIOUS_SESSION_FOR_FAILURES/tasks.json" 2>/dev/null)
\`\`\`

These failures may indicate:
1. Implementation bugs that need fixing
2. Test issues that need investigation
3. Edge cases that weren't handled

Please include these in your bug report if they represent real issues.
"
            fi
        fi
    fi

    print -P "\n%F{magenta}[BUG HUNT]%f Starting creative bug finding with $BUG_FINDER_AGENT..."

    # Check if bug report already exists (resuming interrupted session)
    if [[ -f "$BUG_RESULTS_FILE" ]]; then
        print -P "%F{yellow}[BUG HUNT]%f Existing bug report found: $BUG_RESULTS_FILE"
        print -P "%F{cyan}[BUG HUNT]%f Skipping discovery, proceeding to bug fix pipeline..."
    else
        # Run bug finding - agent will ONLY create file if bugs found
        # Expand $BUG_RESULTS_FILE in the prompt template and inject failed tasks info
        EXPANDED_BUG_PROMPT=$(echo "$BUG_FINDING_PROMPT" | BUG_RESULTS_FILE="$BUG_RESULTS_FILE" envsubst '$BUG_RESULTS_FILE')

        # Prepend failed tasks info if we have any
        if [[ -n "$FAILED_TASKS_INFO" ]]; then
            EXPANDED_BUG_PROMPT="${FAILED_TASKS_INFO}

${EXPANDED_BUG_PROMPT}"
        fi

        run_with_retry $BUG_FINDER_AGENT -p "$EXPANDED_BUG_PROMPT"
    fi

    # If no file was created, no bugs were found - we're done!
    if [[ ! -f "$BUG_RESULTS_FILE" ]]; then
        print -P "%F{green}[BUG HUNT]%f No bugs found. Quality looks good!"
        # Clean up empty session
        rmdir "$CURRENT_BUGFIX_SESSION" 2>/dev/null
    else
        # Bug report exists - run the fix pipeline
        print -P "%F{cyan}[BUG HUNT]%f Bug report generated: $BUG_RESULTS_FILE"
        print -P "\n%F{yellow}[BUG FIX]%f Bugs found! Starting bug fix pipeline..."
        print -P "%F{yellow}[BUG FIX]%f PRD: $BUG_RESULTS_FILE"
        print -P "%F{yellow}[BUG FIX]%f Session: $(basename "$CURRENT_BUGFIX_SESSION")"
        print -P "%F{yellow}[BUG FIX]%f Scope: $BUGFIX_SCOPE"

        # Commit the bug report before starting fix cycle
        git add "$BUG_RESULTS_FILE" 2>/dev/null
        git commit -m "Add bug report: $(basename "$CURRENT_BUGFIX_SESSION")" &>/dev/null || true

        # Re-run the pipeline with bug fixes - session dir IS the bugfix session
        SKIP_BUG_FINDING=true \
        PRD_FILE="$BUG_RESULTS_FILE" \
        SCOPE="$BUGFIX_SCOPE" \
        AGENT="$AGENT" \
        PLAN_DIR="$CURRENT_BUGFIX_SESSION" \
        "$0"

        # Check if bugfix pipeline succeeded
        if [[ $? -ne 0 ]]; then
            print -P "%F{red}[ERROR]%f Bug fix pipeline failed. Session preserved for review: $(basename "$CURRENT_BUGFIX_SESSION")"
        else
            print -P "%F{green}[BUG HUNT]%f Bug fix session complete: $(basename "$CURRENT_BUGFIX_SESSION")"
            print -P "%F{cyan}[INFO]%f Run again to check for more bugs"
        fi
    fi
else
    print -P "%F{cyan}[CONFIG]%f Bug finding skipped (SKIP_BUG_FINDING=true)"
fi

# --- Session Flow Logic ---
# Check if we should continue to next session or process queued delta

if [[ "$SINGLE_SESSION" == "false" && -n "$SESSION_DIR" ]]; then
    # Check for queued delta from earlier in this run
    if [[ -f "$SESSION_DIR/.pending_delta_hash" ]]; then
        PENDING_HASH=$(cat "$SESSION_DIR/.pending_delta_hash")
        CURRENT_HASH=$(hash_prd_content "$PRD_FILE")

        if [[ "$PENDING_HASH" == "$CURRENT_HASH" ]]; then
            print -P "%F{cyan}[SESSION]%f Processing queued delta session..."
            rm "$SESSION_DIR/.pending_delta_hash"

            # Create new delta session
            PREV_SESSION_DIR="$SESSION_DIR"
            NEW_SESSION_NUM=$((CURRENT_SESSION_NUM + 1))
            NEW_SESSION_DIR=$(create_session $NEW_SESSION_NUM "$CURRENT_HASH")
            echo "$CURRENT_SESSION_NUM" > "$NEW_SESSION_DIR/delta_from.txt"
            cp "$PRD_FILE" "$NEW_SESSION_DIR/prd_snapshot.md"

            print -P "%F{green}[SESSION]%f Created delta session: $(basename "$NEW_SESSION_DIR")"
            print -P "%F{cyan}[SESSION]%f Re-running pipeline for delta session..."

            # Re-exec to process the new session
            exec "$0" "$@"
        fi
    fi

    # Check if PRD changed during execution
    FINAL_HASH=$(hash_prd_content "$PRD_FILE")
    SESSION_HASH=$(get_session_hash "$SESSION_DIR")

    if [[ "$FINAL_HASH" != "$SESSION_HASH" ]]; then
        print -P "%F{yellow}[SESSION]%f PRD changed during execution."
        print -P "%F{cyan}[SESSION]%f Run again to process changes as a new delta session."
    fi
fi

print -P "%F{green}[SUCCESS]%f Workflow completed for session: $(basename "$SESSION_DIR")"
