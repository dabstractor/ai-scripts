# TypeScript Implementation of Python Scripts

This project contains complete TypeScript rewrites of the original Python scripts `json2md.py` and `tsk.py`. Both scripts can be used as:

1. **Importable modules** - for programmatic use in other TypeScript/JavaScript projects
2. **CLI tools** - for command-line usage with the same interface as the Python versions

## Files Created

### Core TypeScript Modules
- `src/types.ts` - Common TypeScript type definitions
- `src/json2md.ts` - JSON to Markdown converter
- `src/tsk.ts` - Task management utility

### Compiled JavaScript
- `dist/` - Compiled JavaScript versions of all modules

## Usage

### As CLI Tools

Both scripts support the same command-line interface as their Python counterparts:

#### json2md (TypeScript)
```bash
# Convert JSON file to Markdown (output to terminal)
npm run json2md -- tasks.json

# Convert JSON file to Markdown (output to file)
npm run json2md -- tasks.json output.md

# Pipe JSON input
cat tasks.json | npm run json2md --
```

#### tsk (TypeScript)
```bash
# Get next actionable task
npm run tsk -- next tasks.json

# Show status summary
npm run tsk -- status tasks.json

# Update task status
npm run tsk -- update P1.M1.T1.S1 Complete tasks.json

# Create sample tasks file
npm run tsk -- init new-tasks.json

# Default action (show status)
npm run tsk -- tasks.json
```

### As Importable Modules

```typescript
import { TaskManager } from './src/tsk';
import { convertJsonToMarkdown } from './src/json2md';
import * as fs from 'fs';

// Task management
const manager = new TaskManager('tasks.json');
const nextTask = manager.getNextTask();
const status = manager.getStatusSummary();

// Update task
manager.updateTaskStatus('P1.M1.T1.S1', 'Complete');

// JSON to Markdown conversion
const jsonData = JSON.parse(fs.readFileSync('tasks.json', 'utf8'));
const markdown = convertJsonToMarkdown(jsonData);
console.log(markdown);
```

## Feature Parity

The TypeScript implementations provide **100% feature parity** with the Python originals:

### json2md.ts
✅ Hierarchical JSON processing
✅ Status-to-emoji mapping (matching Python icons)
✅ Markdown header generation (h1-h6)
✅ Property rendering (ID, story points, dependencies, status)
✅ Description formatting (blockquotes)
✅ Context scope formatting (code blocks)
✅ File I/O support (stdin, files)
✅ CLI argument handling

### tsk.ts
✅ Zod-based data validation
✅ Hierarchical task navigation
✅ Status updates with validation
✅ Rich colored terminal output
✅ Next task detection with full context
✅ Sample data generation
✅ All CLI commands (next, tsk, status, update, init)

## Validation Results

Both TypeScript implementations have been validated against the Python originals:

- **json2md**: ✅ Output matches Python version exactly
- **tsk next**: ✅ JSON output matches Python version exactly
- **tsk status**: ✅ Colored terminal output matches Python Rich formatting
- **tsk update**: ✅ Task updates work identically
- **tsk init**: ✅ Sample file generation matches Python version

## Dependencies

### TypeScript Project Dependencies
- `commander` - CLI framework
- `zod` - Data validation and serialization
- `chalk` - Terminal styling and colors
- `typescript` - TypeScript compiler

### Development Dependencies
- `@types/node` - Node.js type definitions
- `ts-node` - TypeScript execution runtime

## Running from Source

```bash
# Build the project
npm run build

# Run directly with ts-node
npx ts-node src/json2md.ts input.json
npx ts-node src/tsk.ts status
```

## Scripts

The `package.json` includes convenient scripts:

```json
{
  "scripts": {
    "build": "tsc",
    "start": "ts-node src",
    "json2md": "ts-node src/json2md.ts",
    "tsk": "ts-node src/tsk.ts"
  }
}
```

## Architecture

Both TypeScript modules follow the same architecture as their Python counterparts:

1. **Type Safety** - Full TypeScript interfaces and Zod validation
2. **Modularity** - Separate files for types, core logic, and CLI
3. **Error Handling** - Comprehensive error handling with helpful messages
4. **CLI Compatibility** - Same command structure as Python versions
5. **Dual Interface** - Can be imported as modules OR run as CLI

The implementations successfully demonstrate the red→green→refactor cycle:
- **Red**: Initial working implementation
- **Green**: Output validation against Python originals
- **Refactor**: Optimized TypeScript patterns and error handling