---
name: nvim-verify
description: Verify Neovim implementation work without Codex memory. Use when running focused local or rbuild build/test loops after code changes, including exact command evidence and cleanup discipline.
---

# nvim-verify

Use this for implementation-phase checks after `$nvim-impl`. Issue reproduction
belongs to `$nvim-repro`, not `$nvim-verify`.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Workflow:

1. Do not read Codex memory for this skill.
2. Resolve `.codex/issue-wiki` as a plain key/value pointer file. If an issue
   number is given, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` first; do
   not scan worktrees or run `git worktree list` unless that direct path is
   missing. Follow its `wiki=` path and read `index.md`.
3. Confirm the isolated worktree under `/home/barrett/dev/neovim/.worktrees`.
4. Inspect the local diff/status and map changed files to focused checks.
5. If there are no implementation changes to verify, stop and report that.
6. Prefer focused checks before broad suites.
7. Use `rbuild nvim build <issue>` for expensive Neovim builds.
8. Use `rbuild nvim test <issue> [test-file]` or
   `rbuild nvim run <issue> -- <command> [args...]` for expensive test loops.
9. Use `-j4` only when Barrett asks or the agent is known to be alone.
10. Do not run expensive local fallback if rbuild fails.
11. Write verification evidence to `<wiki>/evidence/verify.md`, then update
    only `index.md` and `log.md`.
12. Report exact commands, locations, results, and failures.
13. Stop at verification evidence; review and commit are separate stages.

Read `../../references/rbuild.md` and `../../references/guardrails.md`.
