---
description: Implement the chosen Neovim issue outcome in an isolated worktree
argument-hint: [issue-or-task]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:impl

Arguments: $ARGUMENTS

Use only after Barrett chooses an implementation outcome.

1. Read `skills/nvim-impl/SKILL.md`.
2. Resolve `.codex/issue-wiki`; for issue numbers, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` before
   scanning worktrees. Read `index.md`, then linked files as needed.
3. Confirm isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
4. Require Barrett's current prompt to explicitly select an outcome.
5. Implement only `fix` or `test-or-docs`; for `clarify`, write the local
   draft; for `no-change`, `more-repro`, `blocked`, or `resolved upstream`,
   stop.
6. Stop after the patch or draft with a concise handoff. Do not run
   `$nvim-verify` automatically. Stop before commits, pushes, PR work, or
   GitHub mutation.
