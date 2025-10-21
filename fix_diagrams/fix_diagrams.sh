#!/bin/bash

# Read hook input from stdin
input=$(cat)

# Get the file path
filepath=$(echo "$input" | jq -r '.path // .file_path // empty')

# Check if it's a markdown file with box characters
if [[ "$filepath" =~ \.md$ ]] && [[ -f "$filepath" ]] && grep -q '[┌┐└┘]' "$filepath" 2>/dev/null; then
    python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/fix_diagram.py" "$filepath"
fi
