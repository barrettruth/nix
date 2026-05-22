---
name: nvim-issue
description: Investigate Neovim GitHub issues before fixes. Use when given a Neovim issue number like `#12345` or `12345`; create a fresh upstream worktree, gather GitHub/history context, write the issue wiki/report, and stop before reproduction or solutions.
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
4. Run one isolated `history` role; no lightweight mode and no
   conversation-context fork.
5. Run one isolated `integrator` role after `evidence/history.md` exists.
6. Print absolute `report.md`, `index.md`, and worktree paths only; no commit
   or attribution advice.

Stop conditions:

- If the branch or worktree already exists, stop and report the exact path.
- If `upstream` or GitHub access is missing, stop and report the failing phase.
- Do not build, run Spark, create repro files, or write `evidence/repro.md`.

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
- `../../references/issue-wiki.md`

Role contract:

- Give each role a self-contained prompt with only: issue number, worktree path,
  wiki paths, output path, and no-fix guardrails. If isolated roles are not
  possible, stop instead of forking full context.
- While roles run, verify paths/status only; do not synthesize evidence until
  integration.
- `history`: GitHub-only, direct-first context using `github.md`. In the
  history prompt, explicitly require immediate controlled fanout under the
  history agent: direct commit/PR, local source-path context, and
  related/excluded GitHub searches. The parent history agent waits for those
  children, then writes one integrated `evidence/history.md` and curated
  `sources.md`. Do not perform broad search unless direct issue, commit, PR,
  and named-code context are insufficient.
- `integrator`: write `index.md` as a small table of contents and `report.md`
  as a teaching report; link only non-pending history evidence, relevant raw
  sources, and the next file to open; append `log.md`; no solutions and no
  reproduction claims. Run it only after `history.md` exists.

Do not preload all references. Read only what the current step needs:
`../../references/guardrails.md` before role prompts,
`../../references/github.md` for history, and `../../references/issue-wiki.md`
for integration/resume. On resume, read `index.md` first and open only linked
files needed for the task.
