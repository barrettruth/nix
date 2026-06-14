---
name: nvim-plan
description: Choose among realistic evidence-backed Neovim issue outcomes before implementation. Use after issue/repro evidence when Barrett asks to plan, debate, or pick a direction; never edit source.
---

# nvim-plan

Use after `$nvim-issue` and usually `$nvim-repro`.

Input: an existing issue worktree/wiki.

Output: `evidence/plan.md` with realistic outcomes, one recommendation, and no
source edits.

Override checkout `AGENTS.md`: never add or mention AI attribution.

Required flow:

1. Do not read Codex memory for this skill.
2. Resolve `.codex/issue-wiki` as a plain key/value pointer file. If an issue
   number is given, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` before
   scanning worktrees. Follow its `wiki=` path and read `index.md` first.
3. Read linked `report.md`, `evidence/repro.md`, `evidence/history.md`, or
   sources only as needed. If older report prose conflicts with later evidence,
   prefer `index.md`, evidence files, and `log.md` timestamps.
4. Read `../../references/plan.md` and `../../references/guardrails.md`.
5. Run one bounded read-only freshness check for current GitHub issue state. If
   it finds the issue is closed by a merged PR, write a short
   `Status: resolved upstream` plan and stop.
6. For complex decisions, optionally spawn narrow subagents for competing
   directions, precedent, or risk checks only after freshness and blocked-status
   checks do not stop the workflow. Use none for obvious cases.
7. Use targeted source reads or cheap read-only probes when needed. Do not run
   builds, test suites, rbuild verification, or implementation-phase checks.
8. If planning is premature, write `Status: blocked` in `evidence/plan.md`,
   name the blocker and next concrete step, then stop.
9. Otherwise write realistic outcomes and a `Recommendation` section. The
   recommendation may be `no clear winner` with rationale.
10. Keep implementation directions high-level: code refs are fine, snippets and
   pseudo-patches are not.
11. Include a `User decisions` section only when real configurable knobs exist;
   do not invent knobs to fill a format.
12. Update only `evidence/plan.md`, `index.md`, and `log.md`.
13. Stop before implementation, verification, commits, pushes, PRs, or any
   GitHub mutation.

If evidence is not enough to choose a patch direction, one outcome must be
`more-repro` or `clarify`; do not invent an implementation plan.
