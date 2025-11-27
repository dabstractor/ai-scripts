#!/usr/bin/env node

import { Command } from 'commander';
import * as fs from 'fs';
import * as path from 'path';
import { Backlog, Status } from './types';

const STATUS_ICONS: Record<Status, string> = {
  'Planned': '📅',       // Grey/Calendar
  'Researching': '🧐',   // Purple/Blue hue context
  'Ready': '🔷',         // Blue/Ready State
  'Implementing': '🚧',  // Yellow/Construction
  'Complete': '✅',      // Green/Done
  'Failed': '❌'         // Red/Fail
};

function getIcon(status?: string): string {
  if (!status) return '⚪';
  return STATUS_ICONS[status as Status] || '⚪';
}

function renderProperties(item: any): string {
  const parts: string[] = [];

  // Always put ID first if it exists
  if (item.id) {
    parts.push(`\`${item.id}\``);
  }

  // Story points
  if (item.story_points !== undefined) {
    parts.push(`**Story Points:** ${item.story_points}`);
  }

  // Dependencies (only if they exist and are not empty)
  if (item.dependencies && item.dependencies.length > 0) {
    parts.push(`**Dependencies:** ${item.dependencies.join(', ')}`);
  } else if (item.dependencies) {
    // Handle empty dependencies array - show empty string
    parts.push(`**Dependencies:** `);
  }

  return parts.join(' | ');
}

function processNode(node: any, level: number = 1): string {
  const output: string[] = [];

  // Extract properties
  const nType = node.type || 'Unknown';
  const title = node.title || 'Untitled';
  const status = node.status;
  const desc = node.description;
  const context = node.context_scope;

  // If this is the root container (has "backlog"), we skip rendering a header for the container itself
  // and just process the children.
  if ("backlog" in node && level === 1) {
    // Don't render header for root, just process children
  } else {
    // Build header string
    const icon = getIcon(status);
    // Cap headers at h6
    const hLevel = '#'.repeat(Math.min(level, 6));

    // Header Line: ### 🚧 Task: My Task Title
    const headerText = `${hLevel} ${icon} ${nType}: ${title}`.trim();
    output.push(headerText);

    // Metadata Line: `ID` | **Points:** 5 | **Status:** Implementing
    let meta = renderProperties(node);
    if (status) {
      const statusStr = `**Status:** ${status}`;
      meta = meta ? `${meta} | ${statusStr}` : statusStr;
    }

    if (meta) {
      output.push(meta);
      output.push('');  // Add blank line after metadata
    }

    // Description
    if (desc) {
      output.push(`> ${desc}\n`);
    }

    // Context Scope (Code block)
    if (context) {
      output.push(`**Context:**\n\`\`\`text\n${context}\n\`\`\`\n`);
    }
  }

  // Recursion (Find children)
  const CHILD_KEYS = ["backlog", "phases", "milestones", "tasks", "subtasks", "items"];
  for (const key of CHILD_KEYS) {
    if (key in node && Array.isArray(node[key])) {
      for (const child of node[key]) {
        // If current node was the root wrapper, don't increase indentation level yet
        const nextLvl = "backlog" in node ? level : level + 1;
        output.push(processNode(child, nextLvl));
      }
    }
  }

  return output.join('\n');
}

function convertJsonToMarkdown(jsonData: any): string {
  return processNode(jsonData);
}

// Module exports for programmatic use
export { convertJsonToMarkdown, processNode, getIcon, renderProperties };

// CLI functionality
function main(): void {
  const program = new Command();

  program
    .name('json2md')
    .description('Convert hierarchical JSON task structures to Markdown')
    .argument('[input-file]', 'Input JSON file (or use stdin)')
    .argument('[output-file]', 'Output Markdown file (or use stdout)')
    .action(async (inputFile?: string, outputFile?: string) => {
      try {
        let inputData: string;

        // Read input data
        // ORIGINAL_CWD is set by our wrapper scripts, INIT_CWD is set by npm
        const cwd = process.env.ORIGINAL_CWD || process.env.INIT_CWD || process.cwd();
        if (inputFile) {
          const resolvedInputFile = path.resolve(cwd, inputFile);
          if (!fs.existsSync(resolvedInputFile)) {
            console.error(`Error: Input file '${inputFile}' not found`);
            process.exit(1);
          }
          inputData = fs.readFileSync(resolvedInputFile, 'utf8');
        } else {
          // Read from stdin
          if (process.stdin.isTTY) {
            console.error('Error: No input provided. Use pipe or provide input file.');
            console.error('Usage: json2md [input-file] [output-file]');
            console.error('   or: cat input.json | json2md [output-file]');
            process.exit(1);
          }
          inputData = await new Promise<string>((resolve, reject) => {
            let data = '';
            process.stdin.on('data', (chunk) => data += chunk);
            process.stdin.on('end', () => resolve(data));
            process.stdin.on('error', reject);
          });
        }

        // Parse JSON
        let jsonData: any;
        try {
          jsonData = JSON.parse(inputData);
        } catch (error) {
          console.error('Error: Invalid JSON input');
          process.exit(1);
        }

        // Convert to Markdown
        const markdown = convertJsonToMarkdown(jsonData);

        // Write output
        if (outputFile) {
          const resolvedOutputFile = path.resolve(cwd, outputFile);
          fs.writeFileSync(resolvedOutputFile, markdown, 'utf8');
          console.log(`Markdown written to ${outputFile}`);
        } else {
          console.log(markdown);
        }

      } catch (error) {
        console.error('Error:', error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  program.parse();
}

// Run CLI if this file is executed directly
if (require.main === module) {
  main();
}