#!/usr/bin/env node

import { Command } from 'commander';
import * as fs from 'fs';
import * as path from 'path';
import chalk from 'chalk';
import { z } from 'zod';
import { Backlog, Status, Subtask, Task, Milestone, Phase, NextTaskContext, ContextNode } from './types';

// Zod schemas for validation
const StatusSchema = z.enum(['Planned', 'Researching', 'Ready', 'Implementing', 'Complete', 'Failed']);

const VALID_STATUSES: Status[] = ['Planned', 'Researching', 'Ready', 'Implementing', 'Complete', 'Failed'];

// Status priority for determining parent status (lower = earlier in workflow)
// Failed is special: excluded from min calculation unless all children failed
const STATUS_PRIORITY: Record<Status, number> = {
  'Planned': 0,
  'Researching': 1,
  'Ready': 2,
  'Implementing': 3,
  'Complete': 4,
  'Failed': -1
};

/**
 * Fuzzy match a string to a valid Status.
 * Tries: exact (case-insensitive), prefix match, substring match.
 * Throws if no match or ambiguous.
 */
function matchStatus(input: string): Status {
  const inputLower = input.toLowerCase().trim();

  // Exact match (case-insensitive)
  for (const s of VALID_STATUSES) {
    if (s.toLowerCase() === inputLower) return s;
  }

  // Prefix match
  const prefixMatches = VALID_STATUSES.filter(s => s.toLowerCase().startsWith(inputLower));
  if (prefixMatches.length === 1) return prefixMatches[0];
  if (prefixMatches.length > 1) {
    throw new Error(`Ambiguous status '${input}'. Matches: ${prefixMatches.join(', ')}`);
  }

  // Substring match
  const substrMatches = VALID_STATUSES.filter(s => s.toLowerCase().includes(inputLower));
  if (substrMatches.length === 1) return substrMatches[0];
  if (substrMatches.length > 1) {
    throw new Error(`Ambiguous status '${input}'. Matches: ${substrMatches.join(', ')}`);
  }

  throw new Error(`Unknown status '${input}'. Valid: ${VALID_STATUSES.join(', ')}`);
}

/**
 * Normalize an ID to uppercase with periods (e.g., 'p1m1t1s1' -> 'P1.M1.T1.S1').
 * Also supports numeric-only format (e.g., '2.2.3.1' -> 'P2.M2.T3.S1').
 */
function normalizeId(nodeId: string): string {
  // Check for numeric-only format: digits separated by dots (e.g., '2.2.3.1')
  if (/^\d+(\.\d+)*$/.test(nodeId)) {
    const prefixes = ['P', 'M', 'T', 'S'];
    const numbers = nodeId.split('.');
    return numbers.map((num, i) => {
      const prefix = prefixes[i] || 'S'; // Default to 'S' if more than 4 levels
      return `${prefix}${num}`;
    }).join('.');
  }

  // Already has periods with letters - just uppercase
  if (nodeId.includes('.')) {
    return nodeId.toUpperCase();
  }

  // Match segments like P1, M1, T1, S1 (case-insensitive)
  const parts = nodeId.match(/[PMTSpmts]\d+/g);
  if (parts && parts.length > 0) {
    return parts.map(p => p.toUpperCase()).join('.');
  }

  // Fallback: just uppercase
  return nodeId.toUpperCase();
}

const SubtaskSchema = z.object({
  type: z.literal('Subtask'),
  id: z.string(),
  title: z.string(),
  status: StatusSchema,
  story_points: z.number(),
  dependencies: z.array(z.string()),
  context_scope: z.string().optional()
});

const TaskSchema = z.object({
  type: z.literal('Task'),
  id: z.string(),
  title: z.string(),
  status: StatusSchema,
  description: z.string().optional(),
  subtasks: z.array(SubtaskSchema).optional()
});

const MilestoneSchema = z.object({
  type: z.literal('Milestone'),
  id: z.string(),
  title: z.string(),
  status: StatusSchema,
  description: z.string().optional(),
  tasks: z.array(TaskSchema).optional()
});

const PhaseSchema = z.object({
  type: z.literal('Phase'),
  id: z.string(),
  title: z.string(),
  status: StatusSchema,
  description: z.string().optional(),
  milestones: z.array(MilestoneSchema).optional()
});

const BacklogSchema = z.object({
  backlog: z.array(PhaseSchema)
});

class TaskManager {
  private filePath: string;
  private data: Backlog;

  constructor(filePath: string) {
    // Resolve path relative to the original cwd
    // ORIGINAL_CWD is set by our wrapper scripts, INIT_CWD is set by npm
    const cwd = process.env.ORIGINAL_CWD || process.env.INIT_CWD || process.cwd();
    this.filePath = path.resolve(cwd, filePath);
    this.data = this.loadBacklog();
  }

  private loadBacklog(): Backlog {
    if (!fs.existsSync(this.filePath)) {
      throw new Error(`Task file not found: ${this.filePath}`);
    }

    let jsonData: unknown;
    try {
      jsonData = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
    } catch (error) {
      throw new Error(`Failed to parse JSON: ${error instanceof Error ? error.message : String(error)}`);
    }

    try {
      return BacklogSchema.parse(jsonData);
    } catch (error) {
      if (error instanceof z.ZodError) {
        throw new Error(this.formatZodError(error, jsonData));
      }
      throw new Error(`Failed to load task file: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * Format a ZodError into a helpful, actionable error message.
   * Shows: location (with ID), invalid value, valid options, and how to fix.
   */
  private formatZodError(error: z.ZodError, data: unknown): string {
    const lines: string[] = ['Invalid task data:'];

    for (const issue of error.issues) {
      // Cast path to avoid PropertyKey type issues
      const { path, location, value } = this.resolvePathInfo(issue.path as (string | number)[], data);

      lines.push('');
      lines.push(`  Location: ${location}`);
      lines.push(`  Path:     ${path}`);
      lines.push(`  Found:    ${JSON.stringify(value)}`);

      // Zod 4.x uses 'invalid_value' for enum errors
      if (issue.code === 'invalid_value') {
        const iss = issue as any;
        const values = iss.values as string[] | undefined;
        if (values) {
          lines.push(`  Expected: ${values.map((o: string) => JSON.stringify(o)).join(' | ')}`);
        }
      } else if (issue.code === 'invalid_type') {
        lines.push(`  Expected: ${(issue as any).expected}`);
      } else {
        lines.push(`  Problem:  ${issue.message}`);
      }

      // Provide fix suggestion
      lines.push(`  Fix:      ${this.getSuggestion(issue, value)}`);
    }

    return lines.join('\n');
  }

  /**
   * Resolve a Zod path to human-readable location info.
   * Returns the path string, a friendly location description, and the actual value.
   */
  private resolvePathInfo(zodPath: (string | number)[], data: unknown): { path: string; location: string; value: unknown } {
    const pathStr = zodPath.map(p => typeof p === 'number' ? `[${p}]` : `.${p}`).join('').replace(/^\./, '');

    // Walk the data to find the value and build location info
    let current: any = data;
    const locationParts: string[] = [];
    let lastId: string | null = null;

    for (let i = 0; i < zodPath.length; i++) {
      const segment = zodPath[i];

      if (current === undefined || current === null) break;

      // Track IDs as we traverse
      if (typeof current === 'object' && 'id' in current && typeof current.id === 'string') {
        lastId = current.id;
      }

      // Build location description
      if (segment === 'backlog') {
        // Skip 'backlog' in location
      } else if (typeof segment === 'number') {
        // Array index - look ahead to get the item's id/title if possible
        const item = current[segment];
        if (item && typeof item === 'object') {
          const itemId = item.id || `#${segment}`;
          const itemTitle = item.title ? ` "${item.title}"` : '';
          const itemType = item.type || 'item';
          locationParts.push(`${itemType} ${itemId}${itemTitle}`);
          lastId = item.id || lastId;
        }
      } else if (segment === 'milestones' || segment === 'tasks' || segment === 'subtasks') {
        // Skip collection names in location output
      } else {
        // This is a field name (like 'status', 'title', etc.)
        locationParts.push(`field '${segment}'`);
      }

      current = current[segment];
    }

    // Build a friendly location string
    let location: string;
    if (locationParts.length > 0) {
      location = locationParts.join(' → ');
    } else if (lastId) {
      location = lastId;
    } else {
      location = pathStr;
    }

    return { path: pathStr, location, value: current };
  }

  /**
   * Generate a fix suggestion based on the error type and value.
   */
  private getSuggestion(issue: z.ZodIssue, value: unknown): string {
    // Zod 4.x uses 'invalid_value' for enum validation errors
    if (issue.code === 'invalid_value') {
      const iss = issue as any;
      const options = (iss.values as string[] | undefined) || VALID_STATUSES;

      // Try to fuzzy match the invalid value to suggest the closest option
      if (typeof value === 'string') {
        const valueLower = value.toLowerCase();

        // Check for common typos/alternatives
        const suggestion = options.find((opt: string) =>
          opt.toLowerCase().startsWith(valueLower) ||
          valueLower.startsWith(opt.toLowerCase())
        );

        if (suggestion) {
          return `Change "${value}" to "${suggestion}"`;
        }
      }

      return `Use one of: ${options.join(', ')}`;
    }

    if (issue.code === 'invalid_type') {
      return `Change value to type ${(issue as any).expected}`;
    }

    return issue.message;
  }

  private saveBacklog(): void {
    fs.writeFileSync(this.filePath, JSON.stringify(this.data, null, 2), 'utf8');
  }

  private findNodeById(id: string): { node: any; parent: any; parentType: string } | null {
    for (const phase of this.data.backlog) {
      if (phase.id === id) return { node: phase, parent: null, parentType: '' };

      if (phase.milestones) {
        for (const milestone of phase.milestones) {
          if (milestone.id === id) return { node: milestone, parent: phase, parentType: 'milestones' };

          if (milestone.tasks) {
            for (const task of milestone.tasks) {
              if (task.id === id) return { node: task, parent: milestone, parentType: 'tasks' };

              if (task.subtasks) {
                for (const subtask of task.subtasks) {
                  if (subtask.id === id) return { node: subtask, parent: task, parentType: 'subtasks' };
                }
              }
            }
          }
        }
      }
    }
    return null;
  }

  private findNextActiveSubtask(): NextTaskContext {
    for (const phase of this.data.backlog) {
      if (phase.milestones) {
        for (const milestone of phase.milestones) {
          if (milestone.tasks) {
            for (const task of milestone.tasks) {
              if (task.subtasks) {
                for (const subtask of task.subtasks) {
                  if (subtask.status !== 'Complete' && subtask.status !== 'Failed') {
                    return {
                      context: 'CURRENT_FOCUS',
                      phase: {
                        type: phase.type,
                        id: phase.id,
                        title: phase.title,
                        status: phase.status,
                        description: phase.description
                      },
                      milestone: {
                        type: milestone.type,
                        id: milestone.id,
                        title: milestone.title,
                        status: milestone.status,
                        description: milestone.description
                      },
                      task: {
                        type: task.type,
                        id: task.id,
                        title: task.title,
                        status: task.status,
                        description: task.description
                      },
                      subtask: subtask
                    };
                  }
                }
              }
            }
          }
        }
      }
    }

    return { context: 'ALL_COMPLETE' };
  }

  public getNextTask(): NextTaskContext {
    return this.findNextActiveSubtask();
  }

  private findNextFailedSubtask(): NextTaskContext {
    for (const phase of this.data.backlog) {
      if (phase.milestones) {
        for (const milestone of phase.milestones) {
          if (milestone.tasks) {
            for (const task of milestone.tasks) {
              if (task.subtasks) {
                for (const subtask of task.subtasks) {
                  if (subtask.status === 'Failed') {
                    return {
                      context: 'CURRENT_FOCUS',
                      phase: {
                        type: phase.type,
                        id: phase.id,
                        title: phase.title,
                        status: phase.status,
                        description: phase.description
                      },
                      milestone: {
                        type: milestone.type,
                        id: milestone.id,
                        title: milestone.title,
                        status: milestone.status,
                        description: milestone.description
                      },
                      task: {
                        type: task.type,
                        id: task.id,
                        title: task.title,
                        status: task.status,
                        description: task.description
                      },
                      subtask: subtask
                    };
                  }
                }
              }
            }
          }
        }
      }
    }

    return { context: 'NO_FAILURES' };
  }

  public getNextFailed(): NextTaskContext {
    return this.findNextFailedSubtask();
  }

  private completeChildrenRecursively(node: any): void {
    if (node.subtasks) {
      for (const subtask of node.subtasks) {
        subtask.status = 'Complete';
      }
    }
    if (node.tasks) {
      for (const task of node.tasks) {
        task.status = 'Complete';
        this.completeChildrenRecursively(task);
      }
    }
    if (node.milestones) {
      for (const milestone of node.milestones) {
        milestone.status = 'Complete';
        this.completeChildrenRecursively(milestone);
      }
    }
  }

  /**
   * Compute the minimum status from a list of children.
   * Failed items are excluded unless all children are Failed.
   */
  private getMinChildStatus(children: { status: Status }[]): Status {
    if (children.length === 0) return 'Planned';

    // Separate failed and non-failed children
    const nonFailed = children.filter(c => c.status !== 'Failed');

    // If all children failed, parent is Failed
    if (nonFailed.length === 0) return 'Failed';

    // Find the minimum status (lowest priority = earliest in workflow)
    let minStatus = nonFailed[0].status;
    let minPriority = STATUS_PRIORITY[minStatus];

    for (const child of nonFailed) {
      const priority = STATUS_PRIORITY[child.status];
      if (priority < minPriority) {
        minPriority = priority;
        minStatus = child.status;
      }
    }

    return minStatus;
  }

  /**
   * Update parent status to reflect the minimum status of its children.
   */
  private updateParentStatus(parent: any): void {
    if (!parent) return;

    let children: { status: Status }[] = [];

    if (parent.subtasks && parent.subtasks.length > 0) {
      children = parent.subtasks;
    } else if (parent.tasks && parent.tasks.length > 0) {
      children = parent.tasks;
    } else if (parent.milestones && parent.milestones.length > 0) {
      children = parent.milestones;
    }

    if (children.length > 0) {
      const newStatus = this.getMinChildStatus(children);
      parent.status = newStatus;
    }
  }

  /**
   * Find the full ancestry chain for a node by ID.
   * Returns array from root (phase) to immediate parent, or empty if node is a phase.
   */
  private findAncestors(id: string): any[] {
    const ancestors: any[] = [];

    for (const phase of this.data.backlog) {
      if (phase.id === id) return []; // Phase has no ancestors

      if (phase.milestones) {
        for (const milestone of phase.milestones) {
          if (milestone.id === id) return [phase];

          if (milestone.tasks) {
            for (const task of milestone.tasks) {
              if (task.id === id) return [phase, milestone];

              if (task.subtasks) {
                for (const subtask of task.subtasks) {
                  if (subtask.id === id) return [phase, milestone, task];
                }
              }
            }
          }
        }
      }
    }
    return [];
  }

  /**
   * Update all ancestors of a node to reflect their children's statuses.
   * Processes from immediate parent up to root (phase).
   */
  private updateAllAncestors(id: string): void {
    const ancestors = this.findAncestors(id);
    // Update from immediate parent up to root (reverse order)
    for (let i = ancestors.length - 1; i >= 0; i--) {
      this.updateParentStatus(ancestors[i]);
    }
  }

  public updateTaskStatus(id: string, newStatus: Status): void {
    const result = this.findNodeById(id);
    if (!result) {
      throw new Error(`Task with ID '${id}' not found`);
    }

    result.node.status = newStatus;

    // If marking a parent as Complete, complete all children
    if (newStatus === 'Complete') {
      this.completeChildrenRecursively(result.node);
    }

    // Update all ancestors to reflect the minimum status of their children
    this.updateAllAncestors(id);

    this.saveBacklog();
  }

  public getStatusSummary(): string {
    let summary = chalk.cyan.bold('Task Status Summary\n');
    summary += chalk.gray('='.repeat(50) + '\n\n');

    for (const phase of this.data.backlog) {
      const statusColor = this.getStatusColor(phase.status);
      summary += `${chalk.bold(phase.id)}: ${statusColor(phase.title)} - ${statusColor(phase.status)}\n`;

      if (phase.milestones) {
        for (const milestone of phase.milestones) {
          const milestoneColor = this.getStatusColor(milestone.status);
          summary += `  ${chalk.bold(milestone.id)}: ${milestoneColor(milestone.title)} - ${milestoneColor(milestone.status)}\n`;

          if (milestone.tasks) {
            for (const task of milestone.tasks) {
              const taskColor = this.getStatusColor(task.status);
              summary += `    ${chalk.bold(task.id)}: ${taskColor(task.title)} - ${taskColor(task.status)}\n`;

              if (task.subtasks) {
                for (const subtask of task.subtasks) {
                  const subtaskColor = this.getStatusColor(subtask.status);
                  summary += `      ${chalk.bold(subtask.id)}: ${subtaskColor(subtask.title)} - ${subtaskColor(subtask.status)} (${subtask.story_points} points)\n`;
                }
              }
            }
          }
        }
      }
      summary += '\n';
    }

    return summary;
  }

  private getStatusColor(status: Status): (text: string) => string {
    switch (status) {
      case 'Planned': return chalk.gray;
      case 'Researching': return chalk.yellow;
      case 'Ready': return chalk.blue;
      case 'Implementing': return chalk.magenta;
      case 'Complete': return chalk.green;
      case 'Failed': return chalk.red;
      default: return chalk.white;
    }
  }

  public static createSampleFile(inputPath: string): void {
    // Resolve path relative to the original cwd
    const cwd = process.env.ORIGINAL_CWD || process.env.INIT_CWD || process.cwd();
    const filePath = path.resolve(cwd, inputPath);
    const sampleData: Backlog = {
      backlog: [
        {
          type: 'Phase',
          id: 'P1',
          title: 'Sample Project Phase 1',
          status: 'Planned',
          description: 'Sample phase for task tracking demonstration',
          milestones: [
            {
              type: 'Milestone',
              id: 'P1.M1',
              title: 'Environment & Infrastructure',
              status: 'Ready',
              description: 'Set up development environment and basic infrastructure',
              tasks: [
                {
                  type: 'Task',
                  id: 'P1.M1.T1',
                  title: 'Project Configuration',
                  status: 'Researching',
                  description: 'Configure PlatformIO for RP2040-Zero and external libraries',
                  subtasks: [
                    {
                      type: 'Subtask',
                      id: 'P1.M1.T1.S1',
                      title: 'PlatformIO Configuration',
                      status: 'Researching',
                      story_points: 1,
                      dependencies: [],
                      context_scope: 'CONTRACT DEFINITION:\\n1. INPUT: PRD Section 5.1 (Toolchain).\\n2. LOGIC: Create platformio.ini with RP2040-Zero configuration\\n3. OUTPUT: Valid platformio.ini file'
                    },
                    {
                      type: 'Subtask',
                      id: 'P1.M1.T1.S2',
                      title: 'Library Dependencies',
                      status: 'Planned',
                      story_points: 1,
                      dependencies: ['P1.M1.T1.S1'],
                      context_scope: 'CONTRACT DEFINITION:\\n1. INPUT: PRD Section 5.2 (Libraries).\\n2. LOGIC: Add required libraries to platformio.ini\\n3. OUTPUT: Working library configuration'
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    };

    fs.writeFileSync(filePath, JSON.stringify(sampleData, null, 2), 'utf8');
    console.log(chalk.green(`Sample tasks file created: ${filePath}`));
  }
}

// Module exports for programmatic use
export { TaskManager, Status };

// CLI functionality
function main(): void {
  const program = new Command();

  program
    .name('tsk')
    .description('Task processing utility for Agentic TDD environments')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .option('-v, --verbose', 'Enable verbose output')
    .option('-s, --scope <level>', 'Scope to specific level (phase, milestone, task, subtask)')
    .option('-f, --file <path>', 'Path to tasks JSON file (overrides positional argument and TASKS_FILE env var)');

  // Helper to resolve target file: -f option > positional arg > TASKS_FILE env > default
  const resolveTargetFile = (jsonFile: string | undefined, options: any): string => {
    if (options?.file) return options.file;
    if (typeof jsonFile === 'string') return jsonFile;
    if (process.env.TASKS_FILE) return process.env.TASKS_FILE;
    return 'tasks.json';
  };

  const handleNextCommand = (jsonFile: string | undefined, options: { scope?: string; file?: string } | undefined, cmd: any) => {
    try {
      // Merge global options with command options
      const globalOptions = cmd && cmd.parent ? cmd.parent.opts() : {};
      const cmdOptions = (typeof options === 'object') ? options : {};
      const mergedOptions = { ...globalOptions, ...cmdOptions };

      const targetFile = resolveTargetFile(jsonFile, mergedOptions);

      const manager = new TaskManager(targetFile);
      const nextTask = manager.getNextTask();

      if (mergedOptions.scope) {
        const scope = mergedOptions.scope.toLowerCase();

        if (!['phase', 'milestone', 'task', 'subtask'].includes(scope)) {
          throw new Error(`Invalid scope '${scope}'. Valid scopes: phase, milestone, task, subtask`);
        }

        if (nextTask.context === 'ALL_COMPLETE') {
          return;
        }

        let result: ContextNode | undefined;

        switch (scope) {
          case 'phase':
            result = nextTask.phase;
            break;
          case 'milestone':
            result = nextTask.milestone;
            break;
          case 'task':
            result = nextTask.task;
            break;
          case 'subtask':
            result = nextTask.subtask;
            break;
        }

        if (result && result.id) {
          console.log(result.id);
        } else {
          console.error(chalk.red(`Error: Could not find ${scope} in next task context.`));
          process.exit(1);
        }
      } else {
        console.log(JSON.stringify(nextTask, null, 2));
      }
    } catch (error) {
      console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  };

  // next command
  program
    .command('next')
    .description('Get next actionable subtask as JSON')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .action(handleNextCommand);

  // tsk command (alias for next)
  program
    .command('tsk')
    .description('Alias for next command')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .action(handleNextCommand);

  // next-failed command - find and optionally retry failed tasks
  const handleNextFailedCommand = (jsonFile: string | undefined, options: { scope?: string; file?: string; retry?: boolean } | undefined, cmd: any) => {
    try {
      const globalOptions = cmd && cmd.parent ? cmd.parent.opts() : {};
      const cmdOptions = (typeof options === 'object') ? options : {};
      const mergedOptions = { ...globalOptions, ...cmdOptions };

      const targetFile = resolveTargetFile(jsonFile, mergedOptions);
      const manager = new TaskManager(targetFile);
      const nextFailed = manager.getNextFailed();

      if (nextFailed.context === 'NO_FAILURES') {
        console.log(chalk.green('No failed tasks found.'));
        return;
      }

      // If --retry flag is set, reset the failed task to Planned
      if (mergedOptions.retry && nextFailed.subtask) {
        const subtaskId = nextFailed.subtask.id;
        manager.updateTaskStatus(subtaskId, 'Planned');
        console.log(chalk.yellow(`Reset ${subtaskId} from Failed to Planned for retry`));
        return;
      }

      if (mergedOptions.scope) {
        const scope = mergedOptions.scope.toLowerCase();

        if (!['phase', 'milestone', 'task', 'subtask'].includes(scope)) {
          throw new Error(`Invalid scope '${scope}'. Valid scopes: phase, milestone, task, subtask`);
        }

        let result: ContextNode | undefined;

        switch (scope) {
          case 'phase':
            result = nextFailed.phase;
            break;
          case 'milestone':
            result = nextFailed.milestone;
            break;
          case 'task':
            result = nextFailed.task;
            break;
          case 'subtask':
            result = nextFailed.subtask;
            break;
        }

        if (result && result.id) {
          console.log(result.id);
        } else {
          console.error(chalk.red(`Error: Could not find ${scope} in failed task context.`));
          process.exit(1);
        }
      } else {
        console.log(JSON.stringify(nextFailed, null, 2));
      }
    } catch (error) {
      console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  };

  program
    .command('next-failed')
    .description('Get next failed subtask as JSON (for retry)')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .option('--retry', 'Reset the failed task to Planned status for retry')
    .action(handleNextFailedCommand);

  // status command
  program
    .command('status')
    .description('Show current status of all tasks')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .option('--full', 'Show hierarchical tree view with details')
    .action((jsonFile, options, cmd) => {
      try {
        const globalOptions = cmd.parent ? cmd.parent.opts() : {};
        const mergedOptions = { ...globalOptions, ...options };
        const targetFile = resolveTargetFile(jsonFile, mergedOptions);
        const manager = new TaskManager(targetFile);
        console.log(manager.getStatusSummary());
      } catch (error) {
        console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  // update command
  program
    .command('update')
    .description('Update task status')
    .argument('<task-id>', 'Task ID (e.g., P1.M1.T1.S1 or p1m1t1s1)')
    .argument('<status>', 'New status (fuzzy matched, e.g., "comp" -> Complete)')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .action((taskId, statusInput, jsonFile, options, cmd) => {
      try {
        const globalOptions = cmd.parent ? cmd.parent.opts() : {};
        const targetFile = resolveTargetFile(jsonFile, globalOptions);
        const normalizedId = normalizeId(taskId);
        const matchedStatus = matchStatus(statusInput);

        const manager = new TaskManager(targetFile);
        manager.updateTaskStatus(normalizedId, matchedStatus);
        console.log(chalk.green(`Updated ${normalizedId} status to ${matchedStatus}`));
      } catch (error) {
        console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  // init command
  program
    .command('init')
    .description('Create sample tasks.json file')
    .argument('[json-file]', 'JSON file name (default: tasks.json)')
    .action((jsonFile = 'tasks.json') => {
      try {
        TaskManager.createSampleFile(jsonFile);
      } catch (error) {
        console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  // Default action when no command specified
  program.action((jsonFile, options) => {
    try {
      const targetFile = resolveTargetFile(jsonFile, options);
      if (options.scope) {
        handleNextCommand(jsonFile, options, undefined);
      } else {
        const manager = new TaskManager(targetFile);
        console.log(manager.getStatusSummary());
      }
    } catch (error) {
      console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

  program.parse();
}

// Run CLI - always run main() since this is loaded by wrapper scripts
main();