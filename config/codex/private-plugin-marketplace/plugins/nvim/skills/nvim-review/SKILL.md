---
name: nvim-review
description: Review local Neovim implementation changes without Codex memory. Use after implementation work exists and before any commit workflow; writes review evidence and prepares mux git/edit UI.
---

# nvim-review

Use this as a human inspection checkpoint for local implementation patches.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Do not read Codex memory for this skill.
2. Resolve `.codex/issue-wiki` as a plain key/value pointer file. If an issue
   number is given, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` first; do
   not scan worktrees or run `git worktree list` unless that direct path is
   missing. Follow its `wiki=` path and read `index.md`.
3. Confirm the isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
4. Read `../../references/review.md` and `../../references/guardrails.md`.
5. Inspect current git status/diff and identify reviewable changed files.
6. If no reviewable implementation changes exist, stop. Do not create artifact
   reviews for blocked, resolved-upstream, clarify, more-repro, or no-change
   states, and do not write `evidence/review.md` for them.
7. Do not run verification, Spark, builds, tests, or local check commands.
8. Write `<wiki>/evidence/review.md`, then update only `index.md` and `log.md`.
9. Call `../../scripts/review-ui.py` with the worktree, merge-base, and
   quickfix files. Put `review.md` first, then changed reviewable files.
10. Do not focus away from the foreground Codex session after UI setup.
11. Stop before staging, commits, pushes, PR work, or GitHub mutation.
