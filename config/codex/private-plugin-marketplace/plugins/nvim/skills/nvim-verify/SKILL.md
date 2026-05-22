---
name: nvim-verify
description: Verify Neovim implementation work. Use when running focused local or Spark build/test loops after code changes, including exact command evidence and cleanup discipline.
---

# nvim-verify

Use this for implementation-phase checks. Issue reproduction belongs to
`$nvim-repro`, not `$nvim-verify`.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Workflow:

1. Map changed files to focused checks.
2. Prefer focused checks before broad suites.
3. Use `spark nvim build <issue>` for expensive Neovim builds.
4. Use `spark nvim test <issue> [test-file]` or
   `spark nvim run <issue> -- <command> [args...]` for expensive test loops.
5. Use `-j4` only when Barrett asks or the agent is known to be alone.
6. Do not run expensive local fallback if Spark fails.
7. Report exact commands, locations, results, and failures.
8. Stop at verification evidence; review and commit are separate stages.

Read `../../references/spark.md` and `../../references/guardrails.md`.
