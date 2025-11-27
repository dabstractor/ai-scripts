#!/usr/bin/env node

// Demo script showing both programmatic and CLI usage of TypeScript modules

import { TaskManager } from './src/tsk';
import { convertJsonToMarkdown } from './src/json2md';
import * as fs from 'fs';

console.log('=== TypeScript Modules Demo ===\n');

// 1. Programmatic usage of tsk module
console.log('1. Programmatic TaskManager usage:');
try {
  const manager = new TaskManager('test-tasks.json');
  const nextTask = manager.getNextTask();
  console.log('Next task:', JSON.stringify(nextTask, null, 2));
} catch (error) {
  console.log('Error:', error instanceof Error ? error.message : String(error));
}

console.log('\n' + '='.repeat(50) + '\n');

// 2. Programmatic usage of json2md module
console.log('2. Programmatic JSON to Markdown conversion:');
try {
  const jsonData = JSON.parse(fs.readFileSync('test-tasks.json', 'utf8'));
  const markdown = convertJsonToMarkdown(jsonData);
  console.log(markdown);
} catch (error) {
  console.log('Error:', error instanceof Error ? error.message : String(error));
}

console.log('\n' + '='.repeat(50));
console.log('3. CLI Usage Examples:');
console.log('   npm run tsk -- status test-tasks.json');
console.log('   npm run tsk -- next test-tasks.json');
console.log('   npm run json2md -- test-tasks.json');
console.log('   cat test-tasks.json | npm run json2md --');