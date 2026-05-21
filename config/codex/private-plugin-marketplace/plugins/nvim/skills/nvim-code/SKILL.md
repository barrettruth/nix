---
name: nvim-code
description: Implement Neovim code after investigation. Use when Barrett explicitly asks to move from a completed issue wiki/report into code changes; never trigger from an issue number alone.
---

# nvim-code

This is not the default issue workflow. Use it only after Barrett asks for
implementation.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Resolve `.codex/issue-wiki`; read `index.md`, then only linked files needed.
2. Confirm the isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
3. Read local repo guidance and relevant source/tests/docs.
4. If the implementation direction is not already chosen, stop for the future
   design/debate stage instead of inventing a plan while editing.
5. State a concise evidence brief before non-trivial edits.
6. Make the smallest coherent patch.
7. Hand off to verification and review. Stop before commits, pushes, or PR
   work. Commit requires literal `commit`,
   and commits are main-thread only.
8. Hand off expensive build/test loops to `$nvim-verify`; do not run local
   Neovim builds directly.

Read `../../references/issue-wiki.md` and `../../references/guardrails.md`.
