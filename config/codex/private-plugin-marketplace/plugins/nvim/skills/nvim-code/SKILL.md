---
name: nvim-code
description: Implement Neovim code after investigation. Use when Barrett explicitly asks to move from a completed issue wiki/report into code changes; never trigger from an issue number alone.
---

# nvim-code

This is not the default issue workflow. Use it only after Barrett asks for
implementation.

Required flow:

1. Resolve `.codex/issue-wiki`; read `index.md`, then only linked files needed.
2. Confirm the isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
3. Read local repo guidance and relevant source/tests/docs.
4. State a concise evidence brief before non-trivial edits.
5. Make the smallest coherent patch.
6. Stop before commits, pushes, or PR work. Commit requires literal `commit`,
   and commits are main-thread only.
7. Hand off expensive build/test loops to `/nvim:verify`; do not run local
   Neovim builds directly.

Read `../../references/issue-wiki.md` and `../../references/guardrails.md`.
