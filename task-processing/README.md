# Task Processing Tools

TypeScript implementation of task management and JSON-to-Markdown conversion utilities.

## Quick Start

```bash
cd ~/projects/ai-scripts/task-processing
npm install
npm run build
```

## CLI Usage

### Task Management (tsk)
```bash
# Get next actionable task
npm run tsk -- next tasks.json

# Show status summary
npm run tsk -- status tasks.json

# Update task status
npm run tsk -- update P1.M1.T1.S1 Complete tasks.json

# Create sample tasks file
npm run tsk -- init new-tasks.json
```

### JSON to Markdown (json2md)
```bash
# Convert JSON to Markdown
npm run json2md -- tasks.json

# Pipe input
cat tasks.json | npm run json2md --
```

## Programmatic Usage

```typescript
import { TaskManager } from './dist/tsk';
import { convertJsonToMarkdown } from './dist/json2md';

const manager = new TaskManager('tasks.json');
const nextTask = manager.getNextTask();
const status = manager.getStatusSummary();

const markdown = convertJsonToMarkdown(jsonData);
```

## Files

- `src/` - TypeScript source code
- `dist/` - Compiled JavaScript modules
- `types.ts` - Type definitions
- `json2md.ts` - JSON to Markdown converter
- `tsk.ts` - Task management utility
- `demo.ts` - Usage examples

These tools provide full feature parity with the original Python implementations while adding TypeScript type safety and modern JavaScript ecosystem benefits.