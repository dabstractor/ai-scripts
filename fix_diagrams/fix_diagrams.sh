#!/bin/bash

# Read hook input from stdin
input=$(cat)

# The edited file path lives under .tool_input in hook payloads;
# fall back to older top-level fields for compatibility.
filepath=$(echo "$input" | jq -r '.tool_input.file_path // .path // .file_path // empty')

# Check if it's a markdown file with box characters
if [[ "$filepath" =~ \.md$ ]] && [[ -f "$filepath" ]] && grep -q '[┌┐└┘]' "$filepath" 2>/dev/null; then
    python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/fix_diagram.py" "$filepath"
fi
