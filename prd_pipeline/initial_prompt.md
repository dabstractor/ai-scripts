I've been using the "PRP" framework for a while to help my agents one-shot larger features. A PRP is a PRD plus implementation details gathered after doing thorough research through the codebase and online to validate implementation strategy before development. It's the dev agent's game plan. A smarter agent makes the PRP, and an implementation agent can get it done, sometimes. There's usually very little left to do by the end of PRP implementation.

I want to write a script to better control context and provide more determinant behavior. I will pass this script the name of a PRD.

1. Agent #1 will need to determine if the PRD should be broken down into individual PRP tasks.

2. If so, Agent #2 will be responsible for doing a full deep dive into the codebase and all necessary web searches to validate tech stacks, project standards and best practices for dividing tasks and creating high-level API contracts and type definitions for each task to retain coherence. This step will provide high level implementation details to all tasks created from it. Agent #1 will re-assess the new tasks to determine if they need to be broken down further, recursively, after being given the knowledge that these tasks have already been broken down at least once. Target task size will be 1 - 3 story points.

3. Agent #3 will be a task prioritizer and multithreader. It will determine necessary task priority of all tasks, adding architecture and review tasks as needed for best development flow. Group tasks that can safely be implemented simultaneously into groups. A group represents 1 task in the list, but is processed as multiple tasks. This applies recursively. Example, if 6 tasks are created, task order could be:

1 2 3 4 5 6
1 (2 3) (4 5) 6
4 2 3 1 6 5
(1 3 6) 2 5
(1 2 3 4 5 6)
(1 <2 3>) 5 6 4

In the last example, 1 and 2 start at the same time. 3 starts when 1 does. Only once they are all complete does 5 begin. Then 6. Then 4.

The multithreader will be extremely cautious not to let conflicting responsibilities or modifications be developed concurrently. It will always err on the side of caution, developing consecutively if there is any doubt whatsoever.

If the original PRD didn't need to be broken down, if it is a simple, 1 - 3 story point size or "small" t-shirt size task, then we simply convert the PRD into a single task instead of breaking it down into multiple tasks.

4. From here, the tasks are turned into PRPs by Agent #4. This is a research-intensive, lengthy operation. It usually takes longer than the actual development. You can see the entire PRP base-create document at https://raw.githubusercontent.com/Wirasm/PRPs-agentic-eng/refs/heads/development/.claude/commands/prp-commands/prp-base-create.md. This agent context may be reused for PRP edits in the next step. This agent instructs that tasks are to be implemented in a manner that preserves project integrity. Its plans ensure that the implementation agent (#10) can make one small group of changes at at time, testing incrementally between each change to keep the project in a working state.

5. Agent #5 is new, it will be a PRP review agent. It will take the persona of a grizzled veteran graybeard who is highly skeptical of the work of others. He will criticize it thoroughly for one-shot implementation viability. The base-create agent always gives a confidence score of 9 out of 10, so Graybeard's 1-10 ranking needs to begin at the PRP agent's 9. His job will be to manually validate the implementation strategies proposed by the PRP agent. He will write test code to verify that the PRP agent didn't make any assumptions about anything. If he finds anything actionable, the entire PRP is sent back to the PRP agent for editing by resuming that context thread and posing the edits there.

6. Agent #6 gives a json response with a boolean representing whether the project has a testing suite enabled or not. It will do research if the information isn't already in the CLAUDE.md file. It will produce a description of the test suite and testing standards for the next agent.

7. If the project has unit tests, Agent #7 analyzes the original PRD, the new PRP and the unit testing information provided by Agent #6 and creates a core set of unit tests designed to test the core features of the task. Just the important parts like API contracts and types.

8. Agent #8 analyzes all documents created so far and tries to make final feature validation more robust. The PRP execution agent has a tendency to declare victory long before the feature is complete. This agent will ensure that everything is actually working by writing scripts, manual validation plans or other high-effort means of fully verifying all dimensions of a feature work. No shortcuts. If applicable, this agent will write a single test script to do a full validation. It will return an error or success code so our master script will know if it's truly done or not. If the feature absolutely cannot be tested with a script under 300 lines, write clear, direct instructions for doing a full set of manual tests. The agent must take a user's persona and use user tools. This agent will look through the mcp servers available in the project and choose mcp tools for the final agent to use.

9. Agent #9 is the implementation/execution agent. You can find that agent already written here: https://raw.githubusercontent.com/Wirasm/PRPs-agentic-eng/refs/heads/development/.claude/commands/prp-commands/prp-base-execute.md. This agent's prompt will be modified based on features we find, like whether or not we should use unit tests.

10. Agent #10 will be the final validation agent. It will be responsible for running the unit tests created in steps 7 and 9 and the validation script created in step 8, if any of these things exist. If they do not exist, it will be responsible for executing the manual validation strategy created in step 8. If validation fails, Agent #11 will be responsible for doing more PRP-style research based on newfound conclusions, then adding an addendum to the current PRP to clearly indicate the new changes to the existing functionality. This will return us to Step 5, PRP implementation. If Agent #10 determines with perfect confidence that the PRP is fully implemented, we move on to the next task or task group.

All agents from 5 on will need contingencies for "addendum" mode, where the PRP has been executed at least once already and now we're operating on the final block of the readme file so that they don't try to re-implement the entire PRP in a loop.

The main loop should run 2 times. All potentially infinite sub-loops should run a max of 4 times.

Reply "I understand your goals" followed by your honest harsh criticisms of this plan before we proceed.
