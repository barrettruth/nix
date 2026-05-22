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

1. Resolve `.codex/issue-wiki`; read `index.md` first.
2. Read linked `report.md`, `evidence/repro.md`, `evidence/history.md`, or
   sources only as needed.
3. Read `../../references/plan.md` and `../../references/guardrails.md`.
4. Write `evidence/plan.md` with realistic outcomes and one recommendation.
5. Stop before implementation, verification, commits, pushes, PRs, or GitHub
   comments.

If evidence is not enough to choose a patch direction, one outcome must be
`more-repro` or `clarify`; do not invent an implementation plan.
