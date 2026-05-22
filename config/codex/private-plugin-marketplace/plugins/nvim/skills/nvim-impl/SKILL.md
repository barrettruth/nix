---
name: nvim-impl
description: Implement a chosen Neovim issue outcome. Use only after Barrett explicitly chooses an implementation direction from a completed plan; never choose the direction yourself.
---

# nvim-impl

Use only after Barrett chooses an implementation outcome.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Resolve `.codex/issue-wiki`; if an issue number is given, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` before
   scanning worktrees. Read `index.md`, then linked files as needed.
2. Confirm the isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
3. Require the current user prompt to explicitly select an outcome. The issue
   wiki can provide details, but it is not permission to implement its
   recommendation. If selection is missing, stop and ask Barrett to choose from
   `$nvim-plan`.
4. Treat `fix` and `test-or-docs` as implementation-capable outcomes. Treat
   `clarify` as a local-draft action. Refuse `blocked`, `resolved upstream`,
   `no-change`, and `more-repro` as implementation work.
5. State a concise evidence brief before non-trivial edits.
6. Make the smallest coherent patch for the chosen outcome only.
7. Stop after the patch with a concise verification/review handoff. Do not run
   `$nvim-verify` automatically.
8. Hand off expensive build/test loops to `$nvim-verify`; do not run local
   Neovim builds directly.
9. Stop before commits, pushes, PR work, or GitHub mutation. `$nvim-impl` never
   commits.

Read `../../references/impl.md`, `../../references/issue-wiki.md`, and
`../../references/guardrails.md`.
