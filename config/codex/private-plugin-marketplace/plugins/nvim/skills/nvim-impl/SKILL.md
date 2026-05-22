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
3. Require the current user prompt to explicitly select an implementation-capable
   outcome. The issue wiki can provide details, but it is not permission to
   implement its recommendation. If selection is missing, stop and ask Barrett
   to choose from `$nvim-plan`.
4. Refuse `blocked`, `resolved upstream`, `no-change`, `clarify`, and
   `more-repro` outcomes unless Barrett gives a new concrete implementation
   instruction for that case.
5. State a concise evidence brief before non-trivial edits.
6. Make the smallest coherent patch for the chosen outcome only.
7. Hand off to `$nvim-verify` and review. Stop before commits, pushes, or PR
   work. Commit requires literal `commit`, and commits are main-thread only.
8. Hand off expensive build/test loops to `$nvim-verify`; do not run local
   Neovim builds directly.

Read `../../references/impl.md`, `../../references/issue-wiki.md`, and
`../../references/guardrails.md`.
