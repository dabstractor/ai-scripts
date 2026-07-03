# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a diagram alignment utility that fixes misaligned ASCII box diagrams in markdown files. The system consists of:

- `fix_diagram.py`: Core Python script that detects and repairs misaligned box characters (┌┐└┘│─)
- `diagram_lint.py`: Box-geometry linter used as a test oracle and golden-file audit tool
- `run_tests.py`: Test suite (golden + property + corruption-fuzz + unit oracles)
- `fix_diagrams.sh`: Bash hook wrapper that calls the Python script for markdown files containing box characters
- `config.json`: Claude Code hook configuration that automatically runs the fix after file writes/edits

## Architecture

The fixer's error model: LLMs write the top border and left corner column correctly; errors accumulate rightward (content padding) and downward (bottom borders). Pipeline in `fix_diagram.py`:

1. **Trace** (`_find_boxes`/`_trace_box`): each `┌───┐` top border is traced downward, matching left/right edge tokens per row within a drift-tolerance window. Searches are anchored on the left neighbour's *actual* token positions so cumulative drift doesn't break matching. Already-matched tokens are "claimed" so neighbouring boxes can't steal them.
2. **Layout** (`_compute_layout`): target inner width = max(top-border width, widest rstripped content line), measured in display cells (`dwidth`: ANSI escapes are zero-width, CJK is double-width).
3. **Render** (`_render`): each box row is rebuilt at its target geometry; gaps between boxes are elastic (dash runs stretch/shrink via `_fit_gap`); missing bottom borders are synthesised when a pure connector row (`│▼▲`) follows.

Conservative bail-outs ("do no harm"): junction chars in borders, tab-containing rows, malformed bottom borders, connector pipes mistaken for edges, height > 40 rows — all leave the text untouched.

## Development Commands

```bash
python3 run_tests.py              # full suite (300 fuzz cases)
python3 run_tests.py --fuzz 3000  # heavier fuzzing
python3 run_tests.py --verbose    # show passing cases too
python3 fix_diagram.py <file.md>  # fix a file in place
python3 diagram_lint.py <file.md> # report box-geometry violations
```

## Testing Rules

- Golden files (`test_data/**/*_expected.md`) must satisfy `diagram_lint.py` and be fixed points of `fix_text()` — the property oracle enforces this. Never hand-edit an expected file without running the suite.
- Never add input-specific special cases to `fix_diagram.py` to satisfy a single golden test; fix the general algorithm or adjudicate the golden file instead (the corpus was once auto-generated and has been repaired before).
- The fuzz oracle (`gen_case`) is the strongest signal: it builds clean diagrams, corrupts them the way LLMs do, and requires byte-exact recovery.

## Hook Configuration

The PostToolUse hook in `config.json`:
- Matcher `Write|Edit|MultiEdit` (Claude Code tool names)
- `fix_diagrams.sh` reads the hook JSON from stdin and extracts `.tool_input.file_path`
- Only processes `.md` files containing box characters
- Expects the scripts deployed at `$CLAUDE_PROJECT_DIR/.claude/hooks/`
