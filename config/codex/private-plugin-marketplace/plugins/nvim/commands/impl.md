---
description: Implement the chosen Neovim issue outcome in an isolated worktree without Codex memory
argument-hint: [issue-or-task]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:impl

Arguments: $ARGUMENTS

Use only after Barrett chooses an implementation outcome.

1. Read `skills/nvim-impl/SKILL.md`.
2. Do not read Codex memory. Resolve `.codex/issue-wiki` as a plain key/value
   pointer file. For issue numbers, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` first; do
   not scan worktrees or run `git worktree list` unless that path is missing.
   Follow its `wiki=` path and read `index.md`, then linked files as needed.
3. Confirm isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
4. Require Barrett's current prompt to explicitly select an outcome.
5. Implement only `fix` or `test-or-docs`; for `clarify`, write the local
   draft; for `no-change`, `more-repro`, `blocked`, or `resolved upstream`,
   stop.
6. Stop after the patch or draft with a concise handoff. Do not run
   `$nvim-verify` automatically. Stop before commits, pushes, PR work, or
   GitHub mutation.
