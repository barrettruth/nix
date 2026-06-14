---
description: Choose realistic evidence-backed Neovim issue outcomes before implementation
argument-hint: [issue-or-worktree]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:plan

Arguments: $ARGUMENTS

Use when Barrett asks to plan, debate, or choose the next step before editing.

1. Read `skills/nvim-plan/SKILL.md`.
2. Do not read Codex memory. Resolve `.codex/issue-wiki` as a plain key/value
   pointer file; for issue numbers, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` before
   scanning worktrees. Follow its `wiki=` path and read `index.md` first.
3. Read linked evidence only as needed.
4. Run the bounded read-only freshness check from `references/plan.md`.
5. Write only `evidence/plan.md`, `index.md`, and `log.md`.
6. Stop before source edits, builds, tests, rbuild verification, commits,
   pushes, PRs, or GitHub mutation.
