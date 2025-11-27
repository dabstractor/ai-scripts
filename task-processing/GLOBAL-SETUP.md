# Global Task Processing Tools - ✅ Working!

The TypeScript task processing tools can now be run from **any directory**.

## Quick Test

```bash
cd /tmp
json2md --help
tsk --help
```

## Usage Examples

```bash
# Convert JSON to Markdown
json2md ~/path/to/tasks.json

# Get next actionable task
tsk next ~/path/to/tasks.json

# Show status summary
tsk status

# Update task status
tsk update P1.M1.T1.S1 Complete

# Create sample tasks file
tsk init new-tasks.json

# With pipes
cat tasks.json | json2md
echo '{"test": "data"}' | json2md
```

## Setup Method

**Simple Bash Wrappers** - Most reliable approach:

1. **Global Commands**: `~/.local/bin/json2md` and `~/.local/bin/tsk`
2. **Bash Scripts**: Change to project directory, then run npm scripts
3. **Parameter Passing**: All arguments preserved with `"$@"`
4. **No Dependencies**: Works in any shell, no environment setup needed

## File Structure

```
~/.local/bin/
├── json2md    # Bash wrapper -> cd project -> npm run json2md
└── tsk         # Bash wrapper -> cd project -> npm run tsk

~/projects/ai-scripts/task-processing/
├── src/           # TypeScript source files
├── dist/          # Compiled JavaScript
├── scripts/        # Development and test scripts
└── package.json
```

## Verification

To verify setup:

```bash
which json2md  # Should show: ~/.local/bin/json2md
which tsk         # Should show: ~/.local/bin/tsk

# Test from different directory
cd /tmp && json2md --help
cd /tmp && tsk --help
```

## Benefits

✅ **Works from anywhere** - No directory restrictions
✅ **Full compatibility** - Same CLI interface as Python versions
✅ **Type safety** - All TypeScript benefits and Zod validation
✅ **Easy maintenance** - Simple bash wrappers, no complex dependencies
✅ **Piping support** - Full stdin/stdout compatibility
✅ **All commands** - next, status, update, init, tsk alias

The tools are now ready for daily use from any directory!