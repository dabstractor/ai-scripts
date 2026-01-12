#!/usr/bin/env zsh

# Migration script: Convert old PRD pipeline structure to session-based structure
#
# Old structure:
#   project_root/
#   ├── PRD.md
#   ├── tasks.json
#   ├── bug_hunt_tasks.json (maybe)
#   ├── TEST_RESULTS.md (maybe)
#   └── plan/
#       ├── architecture/
#       ├── docs/
#       ├── P1M1T1S1/
#       └── (anything else)
#
# New structure:
#   project_root/
#   ├── PRD.md
#   └── plan/
#       └── 001_{hash}/
#           ├── tasks.json
#           ├── prd_snapshot.md
#           └── (everything else moved here)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() { echo -e "${CYAN}[MIGRATE]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
PRD_FILE="${PRD_FILE:-PRD.md}"
TASKS_FILE="${TASKS_FILE:-tasks.json}"
PLAN_DIR="${PLAN_DIR:-plan}"
DRY_RUN="${DRY_RUN:-false}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --prd=*)
            PRD_FILE="${1#*=}"
            shift
            ;;
        --tasks=*)
            TASKS_FILE="${1#*=}"
            shift
            ;;
        --plan-dir=*)
            PLAN_DIR="${1#*=}"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Migrate old PRD pipeline structure to session-based structure."
            echo ""
            echo "Options:"
            echo "  --dry-run       Show what would be done without making changes"
            echo "  --prd=FILE      PRD file (default: PRD.md)"
            echo "  --tasks=FILE    Tasks file (default: tasks.json)"
            echo "  --plan-dir=DIR  Plan directory (default: plan)"
            echo "  -h, --help      Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper function to run or preview commands
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] $*"
    else
        eval "$@"
    fi
}

# Generate hash from PRD content
hash_prd_content() {
    local file_path=$1
    sha256sum "$file_path" | cut -c1-12
}

# Check if already migrated
is_already_migrated() {
    # Check if any session directories exist
    if find "$PLAN_DIR" -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null | grep -q .; then
        return 0  # Already migrated
    fi
    return 1  # Not migrated
}

# Main migration logic
main() {
    print_status "Starting migration to session-based structure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    # Pre-flight checks
    print_status "Running pre-flight checks..."

    # Check PRD exists
    if [[ ! -f "$PRD_FILE" ]]; then
        print_error "$PRD_FILE not found. Cannot migrate without a PRD."
        exit 1
    fi
    print_success "Found PRD: $PRD_FILE"

    # Check if already migrated
    if is_already_migrated; then
        print_warning "Project appears to already be migrated (found session directories in $PLAN_DIR)"
        read -r "confirm?Continue anyway? (y/N): "
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_status "Migration cancelled."
            exit 0
        fi
    fi

    # Generate session hash and directory
    PRD_HASH=$(hash_prd_content "$PRD_FILE")
    SESSION_NUM="001"
    SESSION_DIR="$PLAN_DIR/${SESSION_NUM}_${PRD_HASH}"

    print_status "Session directory will be: $SESSION_DIR"
    echo ""

    # Create session directory
    print_status "Creating session directory..."
    run_cmd "mkdir -p '$SESSION_DIR'"

    # Copy PRD as snapshot
    print_status "Creating PRD snapshot..."
    run_cmd "cp '$PRD_FILE' '$SESSION_DIR/prd_snapshot.md'"

    # Move tasks.json from root if it exists
    if [[ -f "$TASKS_FILE" ]]; then
        print_status "Moving $TASKS_FILE from root..."
        run_cmd "mv '$TASKS_FILE' '$SESSION_DIR/tasks.json'"
    fi

    # Move any bug-related task files from root (bug_hunt_tasks.json, bug_fix_tasks.json, etc.)
    setopt nullglob 2>/dev/null || true
    for bugfile in bug_hunt_tasks.json bug_fix_tasks.json *bug*tasks*.json; do
        if [[ -f "$bugfile" ]]; then
            print_status "Moving $bugfile from root..."
            run_cmd "mv '$bugfile' '$SESSION_DIR/$bugfile'"
        fi
    done
    unsetopt nullglob 2>/dev/null || true

    # Move TEST_RESULTS.md from root if exists
    if [[ -f "TEST_RESULTS.md" ]]; then
        print_status "Moving TEST_RESULTS.md from root..."
        run_cmd "mv 'TEST_RESULTS.md' '$SESSION_DIR/TEST_RESULTS.md'"
    fi

    # NOW THE KEY PART: Move EVERYTHING from plan/ into the session directory
    # This catches architecture/, docs/, P*/, bugfix/, and ANYTHING ELSE
    print_status "Moving ALL contents from $PLAN_DIR/ into session..."

    setopt nullglob 2>/dev/null || true
    local moved_count=0

    for item in "$PLAN_DIR"/*; do
        # Skip the session directory itself
        if [[ "$item" == "$SESSION_DIR" ]]; then
            continue
        fi

        # Skip other session directories (NNN_hash pattern)
        local basename=$(basename "$item")
        if [[ "$basename" =~ ^[0-9]+_[a-f0-9]+$ ]]; then
            print_warning "Skipping existing session directory: $basename"
            continue
        fi

        # Move everything else
        if [[ -e "$item" ]]; then
            print_status "Moving: $basename"
            run_cmd "mv '$item' '$SESSION_DIR/$basename'"
            moved_count=$((moved_count + 1))
        fi
    done

    unsetopt nullglob 2>/dev/null || true

    if [[ $moved_count -gt 0 ]]; then
        print_success "Moved $moved_count items into session directory"
    else
        print_status "No additional items found in $PLAN_DIR/"
    fi

    echo ""
    print_success "Migration complete!"
    echo ""

    # Show the result
    print_status "New structure:"
    if [[ "$DRY_RUN" != "true" ]]; then
        if command -v tree &>/dev/null; then
            tree -L 3 "$PLAN_DIR" 2>/dev/null || ls -laR "$PLAN_DIR"
        else
            ls -laR "$PLAN_DIR"
        fi
    else
        echo "  $PLAN_DIR/"
        echo "  └── ${SESSION_NUM}_${PRD_HASH}/"
        echo "      ├── tasks.json"
        echo "      ├── prd_snapshot.md"
        echo "      └── (all other plan/ contents)"
    fi

    # Verify plan/ is clean
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        local remaining=$(find "$PLAN_DIR" -maxdepth 1 -mindepth 1 ! -name '[0-9]*_*' 2>/dev/null | wc -l)
        if [[ $remaining -gt 0 ]]; then
            print_warning "Some items remain outside session directories:"
            find "$PLAN_DIR" -maxdepth 1 -mindepth 1 ! -name '[0-9]*_*' -exec basename {} \;
        else
            print_success "$PLAN_DIR/ is clean (only session directories remain)"
        fi
    fi

    echo ""
    print_status "Next steps:"
    echo "  1. Review the migrated structure"
    echo "  2. Run: git add -A && git commit -m 'Migrate to session-based PRD pipeline'"
    echo "  3. Run: ./run-prd.sh to continue with the session-based pipeline"
}

# Run main
main "$@"
