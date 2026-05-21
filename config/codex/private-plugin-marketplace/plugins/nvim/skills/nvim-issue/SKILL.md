---
name: nvim-issue
description: Investigate Neovim GitHub issues before fixes. Use when given a Neovim issue number like `#12345` or `12345`; create a fresh upstream worktree, run parallel history/reproducer roles, write the issue wiki/report, and stop before solutions.
---

# nvim-issue

Use `$nvim-issue` as the primary workflow for Neovim bugs.

Input: one Neovim issue number, with or without `#`.

Output: absolute paths to `report.md`, `index.md`, and the worktree. Stop at
the investigation report; do not propose fixes or commit advice.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Normalize the issue number.
2. Run `../../scripts/issue-setup.py <issue>`.
3. Read the printed `index`, `report`, and worktree paths.
4. Run isolated `history` and `reproducer` roles in parallel; no lightweight
   mode and no conversation-context fork.
5. Run `integrator` as a third isolated role after both role outputs exist.
6. Print absolute `report.md`, `index.md`, and worktree paths only; no commit
   or attribution advice.

Stop conditions:

- If the branch or worktree already exists, stop and report the exact path.
- If `upstream` or Spark access is missing, stop and report the failing phase.
- If reproduction fails, still write what was tried in detail.

Setup script contract:

- Fetches issue context with `gh` into `sources/github/`.
- Fetches `upstream master`.
- Creates branch/worktree `<issue>` under `.worktrees/<issue>`.
- Keeps `.worktrees/` out of main-checkout status with local git excludes.
- Creates the issue wiki and ignored `.codex/issue-wiki` pointer.
- Stops if the branch or worktree already exists.

Reference paths are relative to this file:

- `../../references/guardrails.md`
- `../../references/github.md`
- `../../references/spark.md`
- `../../references/repro.md`
- `../../references/issue-wiki.md`

Role contract:

- Give each role a self-contained prompt with only: issue number, worktree path,
  wiki paths, output path, and no-fix guardrails. If isolated roles are not
  possible, stop instead of forking full context.
- While roles run, verify paths/status only; do not synthesize evidence until
  integration.
- `history`: GitHub-only, direct-first context using `github.md`; write
  `evidence/history.md`. Do not perform broad search unless direct issue,
  commit, PR, and named-code context are insufficient. Read broadly when needed,
  but keep saved sources and `sources.md` curated.
- `reproducer`: raw issue context plus worktree path only; do not read
  `history.md`, `report.md`, or main-agent conclusions before writing
  `evidence/repro.md`; may inspect internals to shape repro; use
  `repro.md` and `spark.md` for exact artifact paths and Spark commands; no
  fixes.
- After the first credible reproduced failure plus a relevant control, the
  reproducer must stop experiments and write `evidence/repro.md`; further
  exploration needs a bounded question from the coordinator or Barrett.
- `integrator`: write `index.md` as a small table of contents and `report.md`
  as a teaching report; link only non-pending evidence, relevant raw sources,
  Spark/repro logs, and the next file to open; append `log.md`; no solutions.
  Run it only after `history.md` and `repro.md` exist. One narrow follow-up is
  allowed for evidence-resolvable contradictions.

The reproducer and integrator may describe what was tried, what failed, and why
the issue is still unreproduced. They must not turn reproduction evidence into
a fix proposal during `$nvim-issue`.

Do not preload all references. Read only what the current step needs:
`../../references/guardrails.md` before role prompts,
`../../references/github.md` for history, `../../references/spark.md` for
reproduction, `../../references/repro.md` for the reproducer contract, and
`../../references/issue-wiki.md` for integration/resume. On resume, read
`index.md` first and open only linked files needed for the task.
