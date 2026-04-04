---
name: guide
description: Interactive step-by-step guide for development tasks
user-invocable: true
---

# /guide

Interactive step-by-step guide for a development task. Creates a plan, then
walks through it one step at a time with user confirmation.

## Instructions

### 1. Gather context

Ask the user what they want to accomplish. Collect:

- The goal (feature, fix, refactor, etc.)
- The target project or plugin
- Any constraints or preferences

Determine the project name from the git root (`basename` of the repo) and
today's date.

### 2. Build the plan

Create a numbered step-by-step plan. Use the `todo_write` tool to track each
step as a pending todo item.

Keep each step small and self-contained — one logical change per step. If a
step would touch more than 2-3 files, break it down further.

Create a feature branch for the work: `type/short-description`.

### 3. Execute iteratively

For each step:

1. Mark the todo as `in_progress`.
2. Present what the step will do and why.
3. Execute it.
4. Show the result.
5. Ask the user to confirm before moving on.
6. Mark the todo as `completed`.

If a step reveals unexpected complexity, break it into sub-steps (add new
todos) and update the plan before proceeding.

### 4. Wrap up

When all steps are complete, summarize what was done and what changed.
Offer to run `/gc` to commit the work.
