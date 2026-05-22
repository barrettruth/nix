---
description: Implement the chosen Neovim issue outcome in an isolated worktree
argument-hint: [issue-or-task]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:impl

Arguments: $ARGUMENTS

Use only after Barrett chooses an implementation outcome.

1. Read `skills/nvim-impl/SKILL.md`.
2. Resolve `.codex/issue-wiki`; read `index.md`, then linked files as needed.
3. Confirm isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
4. If no chosen outcome exists, stop for `$nvim-plan`.
5. State evidence brief, then make the smallest coherent patch.
6. Hand off to verification/review. Stop before commits, pushes, or PR work.
