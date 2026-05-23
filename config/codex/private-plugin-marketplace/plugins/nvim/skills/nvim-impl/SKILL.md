---
name: nvim-impl
description: Implement a chosen Neovim issue outcome without Codex memory. Use only after Barrett explicitly chooses an implementation direction from a completed plan; never choose the direction yourself.
---

# nvim-impl

Use only after Barrett chooses an implementation outcome.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Do not read Codex memory for this skill.
2. Resolve `.codex/issue-wiki` as a plain key/value pointer file, not a
   directory. If an issue number is given, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` first; do
   not scan worktrees or run `git worktree list` unless that direct path is
   missing. Follow its `wiki=` path and read `index.md`, then linked files as
   needed.
3. Confirm the isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
4. Require the current user prompt to explicitly select an outcome. The issue
   wiki can provide details, but it is not permission to implement its
   recommendation. If selection is missing, stop and ask Barrett to choose from
   `$nvim-plan`.
5. Treat `fix` and `test-or-docs` as implementation-capable outcomes. Treat
   `clarify` as a local-draft action. Refuse `blocked`, `resolved upstream`,
   `no-change`, and `more-repro` as implementation work.
6. State a concise evidence brief before non-trivial edits.
7. Make the smallest coherent patch for the chosen outcome only.
8. Stop after the patch with a concise verification/review handoff. Do not run
   `$nvim-verify` automatically.
9. Hand off expensive build/test loops to `$nvim-verify`; do not run local
   Neovim builds directly.
10. Stop before commits, pushes, PR work, or GitHub mutation. `$nvim-impl` never
   commits.

Read `../../references/impl.md`, `../../references/issue-wiki.md`, and
`../../references/guardrails.md`.
