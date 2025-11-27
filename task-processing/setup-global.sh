#!/bin/bash

# Setup script for global task processing tools
echo "Setting up global task processing tools..."

# Add environment variable to shell
SHELL_RC="$HOME/.bashrc"
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

# Add environment variable if not already present
if ! grep -q "TASK_PROCESSING_DIR" "$SHELL_RC"; then
    echo "" >> "$SHELL_RC"
    echo "# Task Processing Tools" >> "$SHELL_RC"
    echo "export TASK_PROCESSING_DIR=\"$HOME/projects/ai-scripts/task-processing\"" >> "$SHELL_RC"
    echo "" >> "$SHELL_RC"
fi

# Make scripts executable
chmod +x "$HOME/projects/ai-scripts/task-processing/scripts/"*

# Create symlinks
ln -sf "$HOME/projects/ai-scripts/task-processing/scripts/global-json2md" "$HOME/.local/bin/json2md"
ln -sf "$HOME/projects/ai-scripts/task-processing/scripts/global-tsk" "$HOME/.local/bin/tsk"

echo "✅ Setup complete!"
echo ""
echo "Please restart your shell or run: source $SHELL_RC"
echo ""
echo "Then you can use from anywhere:"
echo "  json2md tasks.json"
echo "  tsk next tasks.json"
echo "  tsk status"
echo ""
echo "Current setup:"
echo "  TASK_PROCESSING_DIR: $TASK_PROCESSING_DIR"
echo "  json2md: $(which json2md)"
echo "  tsk: $(which tsk)"