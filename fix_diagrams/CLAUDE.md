# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a diagram alignment utility that fixes misaligned ASCII box diagrams in markdown files. The system consists of:

- `fix_diagram.py`: Core Python script that detects and repairs misaligned box characters (┌┐└┘│─)
- `fix_diagrams.sh`: Bash hook wrapper that calls the Python script for markdown files containing box characters
- `config.json`: Claude Code hook configuration that automatically runs the fix after file writes/edits

## Architecture

The diagram fixer works by:
1. **Box Detection**: Scans text for top-left corners (┌) and traces complete box boundaries
2. **Alignment Calculation**: Determines the correct right column position for each box based on maximum width
3. **Line Reconstruction**: Rebuilds each line with properly aligned borders and content

The hook system automatically triggers when markdown files containing box characters are written or edited.

## Development Commands

### Running the diagram fixer manually
```bash
python3 fix_diagram.py <filename>
```

### Testing the hook system
The hooks are configured in `config.json` and will automatically run after file operations. No manual testing commands needed.

## Hook Configuration

The PostToolUse hooks are configured to:
- Trigger on `write_file` and `edit_file` operations
- Only process `.md` files containing box characters
- Use the absolute project path `$CLAUDE_PROJECT_DIR/.claude/hooks/fix_diagrams.py`

## File Locations

- Main script: `fix_diagram.py`
- Hook wrapper: `fix_diagrams.sh`
- Hook config: `config.json`
- Target files: Any markdown files containing box drawing characters