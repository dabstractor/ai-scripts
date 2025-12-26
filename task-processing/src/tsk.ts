#!/usr/bin/env node

import { Command } from 'commander';
import * as fs from 'fs';
import * as path from 'path';
import chalk from 'chalk';
import { z } from 'zod';
import { Backlog, Status, Subtask, Task, Milestone, Phase, NextTaskContext, ContextNode } from './types';

// Zod schemas for validation
const StatusSchema = z.enum(['Planned', 'Researching', 'Ready', 'Implementing', 'Complete', 'Failed']);

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

    try {
      const jsonData = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
      return BacklogSchema.parse(jsonData);
    } catch (error) {
      if (error instanceof z.ZodError) {
        throw new Error(`Invalid task data format: ${error.message}`);
      }
      throw new Error(`Failed to load task file: ${error instanceof Error ? error.message : String(error)}`);
    }
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

  private checkAndCompleteParent(parent: any): void {
    if (!parent) return;

    let allComplete = false;

    if (parent.subtasks) {
      allComplete = parent.subtasks.length > 0 && parent.subtasks.every((s: Subtask) => s.status === 'Complete');
    } else if (parent.tasks) {
      allComplete = parent.tasks.length > 0 && parent.tasks.every((t: Task) => t.status === 'Complete');
    } else if (parent.milestones) {
      allComplete = parent.milestones.length > 0 && parent.milestones.every((m: Milestone) => m.status === 'Complete');
    }

    if (allComplete && parent.status !== 'Complete') {
      parent.status = 'Complete';
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

    // Check if all siblings are Complete, and if so, complete the parent
    this.checkAndCompleteParent(result.parent);

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

  public static createSampleFile(filePath: string): void {
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
    .option('-v, --verbose', 'Enable verbose output');

  // next command
  program
    .command('next')
    .description('Get next actionable subtask as JSON')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .action((jsonFile = 'tasks.json') => {
      try {
        const manager = new TaskManager(jsonFile);
        const nextTask = manager.getNextTask();
        console.log(JSON.stringify(nextTask, null, 2));
      } catch (error) {
        console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  // tsk command (alias for next)
  program
    .command('tsk')
    .description('Alias for next command')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .action((jsonFile = 'tasks.json') => {
      try {
        const manager = new TaskManager(jsonFile);
        const nextTask = manager.getNextTask();
        console.log(JSON.stringify(nextTask, null, 2));
      } catch (error) {
        console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  // status command
  program
    .command('status')
    .description('Show current status of all tasks')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .option('-f, --full', 'Show hierarchical tree view with details')
    .action((jsonFile = 'tasks.json', options) => {
      try {
        const manager = new TaskManager(jsonFile);
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
    .argument('<task-id>', 'Task ID (e.g., P1.M1.T1.S1)')
    .argument('<status>', 'New status (Planned, Researching, Ready, Implementing, Complete, Failed)')
    .argument('[json-file]', 'JSON file containing tasks (default: tasks.json)')
    .action((taskId, newStatus, jsonFile = 'tasks.json') => {
      try {
        // Validate status
        if (!StatusSchema.safeParse(newStatus).success) {
          throw new Error(`Invalid status: ${newStatus}. Must be one of: Planned, Researching, Ready, Implementing, Complete, Failed`);
        }

        const manager = new TaskManager(jsonFile);
        manager.updateTaskStatus(taskId, newStatus as Status);
        console.log(chalk.green(`Updated ${taskId} status to ${newStatus}`));
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
  program.action((jsonFile = 'tasks.json') => {
    try {
      const manager = new TaskManager(jsonFile);
      console.log(manager.getStatusSummary());
    } catch (error) {
      console.error(chalk.red('Error:'), error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

  program.parse();
}

// Run CLI if this file is executed directly
if (require.main === module) {
  main();
}