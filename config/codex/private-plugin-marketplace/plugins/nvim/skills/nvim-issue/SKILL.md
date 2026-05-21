---
name: nvim-issue
description: Investigate Neovim GitHub issues before fixes. Use when given a Neovim issue number like `#12345` or `12345`; create a fresh upstream worktree, run parallel history/reproducer roles, write the issue wiki/report, and stop before solutions.
---

# nvim-issue

Use `/nvim:issue` as the primary workflow for Neovim bugs.

Required flow:

1. Normalize issue number and fetch raw context with `gh`.
2. Fetch `upstream master`; create branch/worktree named only by the issue number.
3. Create the issue wiki, raw source folders, append-only log, and ignored worktree pointer.
4. Run `history` and `reproducer` in parallel; no lightweight mode.
5. Run `integrator` after both role outputs exist.
6. Print absolute `report.md`, `index.md`, and worktree paths.

Role contract:

- `history`: GitHub-only broad search with `gh`/`gh api`; write `evidence/history.md`.
- `reproducer`: raw issue context plus worktree path only; may inspect internals to shape repro; use `spark nvim ...` for expensive builds/tests; write `evidence/repro.md` and logs; no fixes.
- `integrator`: write `index.md` as an LLM table of contents and `report.md` as a teaching report; link `report.md`, `sources.md`, every evidence file, Spark/repro logs, and the next file to open; no solutions; one narrow follow-up is allowed for evidence-resolvable contradictions.

The reproducer and integrator may describe what was tried, what failed, and why
the issue is still unreproduced. They must not turn reproduction evidence into
a fix proposal during `/nvim:issue`.

Read `../../references/workflow.md`, `../../references/issue-wiki.md`,
`../../references/github.md`, `../../references/spark.md`, and
`../../references/guardrails.md`. On resume, read `index.md` first and open
only linked files needed for the task.
