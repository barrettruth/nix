---
description: Manually remove one Neovim issue worktree after explicit confirmation
argument-hint: <issue-number>
allowed-tools: [Read, Glob, Grep, Bash]
---

# /nvim:clean

Arguments: $ARGUMENTS

Manual cleanup command for one issue-number worktree.

1. Read `skills/nvim-clean/SKILL.md`.
2. Require exactly one issue number; normalize `#12345` to `12345`.
3. Inspect only local git state. Do not use GitHub or `gh`.
4. Show the exact worktree path, branch, and dirty status.
5. Prompt `Remove worktree <path> and branch <nr>? y/N`.
6. Delete only after literal `y`.
7. Use `git worktree remove <path>` and `git branch -d <nr>`.
8. Do not force remove/delete unless Barrett explicitly asks for force cleanup.
