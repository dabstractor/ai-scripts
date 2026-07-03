# Diagram Fixer

A utility that fixes misaligned ASCII box diagrams in markdown files, especially those created by AI.

## What It Does

**Before** (typical AI-generated misalignment):
```
┌─────────────┐     ┌─────────────────┐
│   Service A │────▶│   Service B     │
│   Auth      │     │   Processing    │
└─────────────────┘     └──────────────────┘
```

**After** (fixed alignment):
```
┌─────────────┐     ┌─────────────────┐
│   Service A │────▶│   Service B     │
│   Auth      │     │   Processing    │
└─────────────┘     └─────────────────┘
```

## Use Cases

### Claude Code Hook (Primary)
This script is designed to work as an automatic post-write hook. The included `config.json` contains a pre-configured hook that can be used as your `settings.json` or merged with existing settings to automatically fix diagrams whenever you edit markdown files containing box characters.

### Manual Usage
```bash
python3 fix_diagram.py file.md
```

Fixes diagram alignment in `file.md` in place.

## How It Works

The fixer models how LLMs actually break diagrams: the **top border and left corner column are written first and are almost always right**, while errors accumulate to the right (wrong padding before `│`) and downward (bottom borders with the wrong dash count, drifted corners, or missing entirely).

For every box it computes a target geometry — left column from the top-left corner, inner width from the top border (grown if any content line is wider) — then rewrites each row to match:

- Content is preserved verbatim and re-padded to the box width.
- Gaps between side-by-side boxes are *elastic*: arrows like `────▶` stretch or shrink to keep neighbouring boxes aligned.
- A missing bottom border is synthesised when a connector row (`│`/`▼`/`▲`) follows.
- Widths are computed in **display cells**, so CJK/emoji content and ANSI color codes align correctly in a terminal.
- **First, do no harm**: junction characters (`┬┼├┤`), double-line/rounded borders, tab-polluted rows, and anything structurally ambiguous are left untouched.

## Testing

`python3 run_tests.py` runs four independent oracles:

1. **Golden tests** — 50 input/expected pairs in `test_data/` covering arrows, grids, unicode, ANSI, incomplete boxes, etc.
2. **Property tests** — for every case: idempotence (`fix(fix(x)) == fix(x)`), expected files are fixed points, no visible character is created or destroyed, and the output never has more geometry violations than the input.
3. **Corruption fuzzing** — a seeded generator builds random *clean* diagrams (including wide-character content), applies LLM-style corruptions (bad bottom widths, padding drift, gap jitter, dropped bottom borders), and requires the fixer to recover the clean text *exactly*. `--fuzz N` controls the case count (default 300).
4. **Unit tests** — targeted regressions for tricky behaviours.

`diagram_lint.py` is a standalone geometry checker used both as a test oracle and for auditing golden files:

```bash
python3 diagram_lint.py file.md
```

## Files

- `fix_diagram.py` - Main script that fixes diagram alignment
- `diagram_lint.py` - Box-geometry linter (test oracle / audit tool)
- `run_tests.py` - Test suite (golden + property + fuzz + unit)
- `fix_diagrams.sh` - Hook wrapper for integration with file editors
- `config.json` - Pre-configured Claude Code hook settings
