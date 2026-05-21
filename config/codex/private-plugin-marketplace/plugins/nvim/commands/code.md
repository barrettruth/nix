---
description: Implement a focused Neovim code change from an isolated worktree after investigation
argument-hint: [issue-or-task]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:code

Arguments: $ARGUMENTS

Use only after Barrett explicitly asks for implementation.

1. Read `skills/nvim-code/SKILL.md`.
2. Resolve `.codex/issue-wiki`; read `index.md`, then linked files as needed.
3. Confirm isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
4. State evidence brief, then make the smallest coherent patch.
5. Stop before commits, pushes, or PR work. Commit requires literal `commit`
   and is main-thread only.
