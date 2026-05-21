---
name: nvim-wt
description: Coordinate Neovim worktrees and checkout pointers. Use when creating, claiming, naming, or exposing isolated `/home/barrett/dev/neovim/.worktrees` checkouts.
---

# nvim-wt

Use `/home/barrett/dev/neovim` as the canonical repo and put agent worktrees
under `.worktrees`.

Issue worktree rules:

- fetch `upstream master` first
- branch and worktree name is issue number only, e.g. `12345`
- if branch/worktree exists, stop and report
- do not create `12345-2`

Record the active inspection pointer under `.worktrees/.codex/current` and
print the exact worktree path for Barrett.

Do not move, replace, prune, or clean the main checkout. Do not delete another
session's worktree or lock.

Read `../../references/workflow.md` and `../../references/guardrails.md`.
