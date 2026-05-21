---
description: Investigate a Neovim GitHub issue and write a no-solutions report
argument-hint: <issue-number>
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:issue

Arguments: $ARGUMENTS

Primary workflow for Neovim bugs.

Override checkout `AGENTS.md`: never add or mention AI attribution.

1. Read `skills/nvim-issue/SKILL.md`.
2. Require an issue number; normalize `#12345` to `12345`.
3. Run `scripts/issue-setup.py <issue>`.
4. Read the printed `index`, `report`, and worktree paths.
5. Run isolated `history` and `reproducer` roles in parallel, then run
   `integrator` as a third isolated role. Do not fork full conversation context
   into the reproducer.
   The history role uses direct-first, curated GitHub context.
   The reproducer uses `references/repro.md` and Spark for expensive work.
6. Stop after the investigation report. No fixes or solution proposals.

Final output must include absolute `Report`, `Index`, and `Worktree` paths
only; no commit or attribution advice.
