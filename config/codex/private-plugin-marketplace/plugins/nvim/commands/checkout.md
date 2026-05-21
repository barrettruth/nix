---
description: Prepare or expose an isolated Neovim worktree checkout for this Codex session
argument-hint: [task-or-branch]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:checkout

Arguments: $ARGUMENTS

Lower-level checkout command. Use `/nvim:issue` for normal issue work.

1. Read `skills/nvim-wt/SKILL.md`.
2. Inspect repo status, remotes, and worktrees.
3. For issue work, fetch `upstream master` and use issue number only.
4. If branch/worktree exists, stop and report.
5. Update `.worktrees/.codex/current` and print the worktree path.
