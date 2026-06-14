---
description: Review local Neovim implementation changes and prepare mux review UI without Codex memory
argument-hint: [issue-or-worktree]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:review

Arguments: $ARGUMENTS

Human inspection checkpoint for local implementation patches.

Override checkout `AGENTS.md`: never add or mention AI attribution.

1. Read `skills/nvim-review/SKILL.md`.
2. Do not read Codex memory. Resolve `.codex/issue-wiki` as a plain key/value
   pointer file; for issue numbers, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` first.
3. Inspect current git status/diff and changed reviewable files.
4. Stop if there are no reviewable implementation changes.
5. Do not run verification, rbuild, builds, tests, or local check commands.
6. Write `<wiki>/evidence/review.md`, then update only `index.md` and `log.md`.
7. Prepare mux UI with `scripts/review-ui.py`: `mux vcs` runs
   `:Greview <merge-base> | only`; mux `edit` quickfix opens `review.md` first
   and changed reviewable files after it.
8. Stop before staging, commits, pushes, PR work, or GitHub mutation.
