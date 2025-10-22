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

The script detects ASCII box drawing characters (┌┐└┘│─) and automatically realigns them to create properly formatted boxes. It's particularly useful for fixing diagrams that AI models generate with uneven borders.

## Files

- `fix_diagram.py` - Main script that fixes diagram alignment
- `fix_diagrams.sh` - Hook wrapper for integration with file editors
- `config.json` - Pre-configured Claude Code hook settings