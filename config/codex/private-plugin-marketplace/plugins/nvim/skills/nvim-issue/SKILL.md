---
name: nvim-issue
description: Investigate Neovim GitHub issues before fixes. Use when given a Neovim issue number like `#12345` or `12345`; create a fresh upstream worktree, run parallel history/reproducer roles, write the issue wiki/report, and stop before solutions.
---

# nvim-issue

Use `$nvim-issue` as the primary workflow for Neovim bugs.

Input: one Neovim issue number, with or without `#`.

Output: absolute paths to `report.md`, `index.md`, and the worktree. Stop at
the investigation report; do not propose fixes.

Required flow:

1. Normalize the issue number.
2. Fetch raw issue context with `gh` and save it under `sources/github/`.
3. Fetch `upstream master` in `/home/barrett/dev/neovim`.
4. Create branch/worktree `<issue>` from `upstream/master` under
   `/home/barrett/dev/neovim/.worktrees/<issue>`.
5. Create the issue wiki, raw source folders, append-only log, and ignored
   worktree pointer.
6. Run `history` and `reproducer` in parallel as separate roles; no lightweight
   mode.
7. Run `integrator` after both role outputs exist.
8. Print absolute `report.md`, `index.md`, and worktree paths.

Stop conditions:

- If the branch or worktree already exists, stop and report the exact path.
- If `upstream` or Spark access is missing, stop and report the failing phase.
- If reproduction fails, still write what was tried in detail.

Role contract:

- `history`: GitHub-only broad search with `gh`/`gh api`; write `evidence/history.md`.
- `reproducer`: raw issue context plus worktree path only; may inspect internals to shape repro; use `spark nvim ...` for expensive builds/tests; write `evidence/repro.md` and logs; no fixes.
- `integrator`: write `index.md` as an LLM table of contents and `report.md` as a teaching report; link `report.md`, `sources.md`, every evidence file, Spark/repro logs, and the next file to open; no solutions; one narrow follow-up is allowed for evidence-resolvable contradictions.

The reproducer and integrator may describe what was tried, what failed, and why
the issue is still unreproduced. They must not turn reproduction evidence into
a fix proposal during `$nvim-issue`.

Read `../../references/workflow.md`, `../../references/issue-wiki.md`,
`../../references/github.md`, `../../references/spark.md`, and
`../../references/guardrails.md`. On resume, read `index.md` first and open
only linked files needed for the task.
