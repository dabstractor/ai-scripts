# Global Setup Instructions

There are multiple ways to use these tools from anywhere:

## Option 1: Environment Variable + Symlinks (Recommended)

```bash
# Add to ~/.bashrc or ~/.zshrc:
export TASK_PROCESSING_DIR="/home/dustin/projects/ai-scripts/task-processing"

# Create symlinks in your local bin:
ln -sf $TASK_PROCESSING_DIR/scripts/global-json2md ~/.local/bin/json2md
ln -sf $TASK_PROCESSING_DIR/scripts/global-tsk ~/.local/bin/tsk

# Then reload shell:
source ~/.bashrc
```

## Option 2: Bash Aliases

```bash
# Run the setup script:
~/projects/ai-scripts/task-processing/scripts/task-tools-setup

# Or manually add to ~/.bashrc:
alias json2md='cd ~/projects/ai-scripts/task-processing && npm run json2md -- $@ && cd -'
alias tsk='cd ~/projects/ai-scripts/task-processing && npm run tsk -- $@ && cd -'
```

## Option 3: Direct Path Usage

```bash
# Add to PATH:
echo 'export PATH="$HOME/projects/ai-scripts/task-processing/scripts:$PATH"' >> ~/.bashrc

# Use directly:
global-json2md tasks.json
global-tsk next tasks.json
```

## Testing

After setup, test from any directory:

```bash
cd /tmp
json2md --help
tsk status
```

## Make Scripts Executable

```bash
chmod +x ~/projects/ai-scripts/task-processing/scripts/*
```

Choose the option that works best for your workflow!