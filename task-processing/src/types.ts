export type Status = 'Planned' | 'Researching' | 'Ready' | 'Implementing' | 'Complete' | 'Failed';

export interface Subtask {
  type: 'Subtask';
  id: string;
  title: string;
  status: Status;
  story_points: number;
  dependencies: string[];
  context_scope?: string;
}

export interface Task {
  type: 'Task';
  id: string;
  title: string;
  status: Status;
  description?: string;
  subtasks?: Subtask[];
}

export interface Milestone {
  type: 'Milestone';
  id: string;
  title: string;
  status: Status;
  description?: string;
  tasks?: Task[];
}

export interface Phase {
  type: 'Phase';
  id: string;
  title: string;
  status: Status;
  description?: string;
  milestones?: Milestone[];
}

export interface Backlog {
  backlog: Phase[];
}

export interface ContextNode {
  type: string;
  id: string;
  title: string;
  status: Status;
  description?: string;
  story_points?: number;
  dependencies?: string[];
  context_scope?: string;
}

export interface NextTaskContext {
  context: 'CURRENT_FOCUS' | 'ALL_COMPLETE' | 'NO_FAILURES';
  phase?: ContextNode;
  milestone?: ContextNode;
  task?: ContextNode;
  subtask?: ContextNode;
}