# Global Task Processing Tools

## ✅ Setup Complete

The TypeScript task processing tools (`json2md` and `tsk`) can now be run from any directory.

## Usage

### From Any Directory
```bash
# Get help
json2md --help
tsk --help

# Convert JSON to Markdown
json2md ~/path/to/tasks.json

# Get next task
tsk next ~/path/to/tasks.json

# Show status
tsk status ~/path/to/tasks.json

# Update task status
tsk update P1.M1.T1.S1 Complete ~/path/to/tasks.json

# Initialize sample tasks
tsk init ~/path/to/new-tasks.json
```

### With Pipes
```bash
cat tasks.json | json2md
echo '{"data": "test"}' | json2md output.md
```

## Setup Details

The tools use the following approach:

1. **Environment Variable**: `TASK_PROCESSING_DIR` points to project location
2. **Global Symlinks**: `json2md` and `tsk` in `~/.local/bin/`
3. **Wrapper Scripts**: Change to project directory before running modules

## Manual Setup (if needed)

If the global commands don't work, run:

```bash
# Source environment
source ~/.bashrc  # or ~/.zshrc

# Verify setup
echo $TASK_PROCESSING_DIR
which json2md
which tsk
```

## Development

To modify the tools:

```bash
cd ~/projects/ai-scripts/task-processing
npm run build
# Changes are immediately available globally
```

## File Structure

```
~/projects/ai-scripts/task-processing/
├── src/                    # TypeScript source
│   ├── types.ts
│   ├── json2md.ts
│   └── tsk.ts
├── dist/                   # Compiled JavaScript
├── scripts/                 # Global wrappers
│   ├── global-json2md
│   └── global-tsk
├── setup-global.sh         # Setup script
└── README-GLOBAL.md        # This file
```

The tools maintain 100% feature parity with the original Python versions while providing TypeScript type safety and modern JavaScript ecosystem benefits.