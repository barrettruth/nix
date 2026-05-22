---
name: nvim-impl
description: Implement a chosen Neovim issue outcome. Use only after Barrett explicitly chooses an implementation direction from a completed plan; never choose the direction yourself.
---

# nvim-impl

Use only after Barrett chooses an implementation outcome.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Resolve `.codex/issue-wiki`; read `index.md`, then linked files as needed.
2. Confirm the isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
3. Confirm the chosen outcome in the current prompt or issue wiki. If missing,
   stop and ask for `$nvim-plan`.
4. State a concise evidence brief before non-trivial edits.
5. Make the smallest coherent patch for the chosen outcome only.
6. Hand off to `$nvim-verify` and review. Stop before commits, pushes, or PR
   work. Commit requires literal `commit`, and commits are main-thread only.
7. Hand off expensive build/test loops to `$nvim-verify`; do not run local
   Neovim builds directly.

Read `../../references/issue-wiki.md` and `../../references/guardrails.md`.
