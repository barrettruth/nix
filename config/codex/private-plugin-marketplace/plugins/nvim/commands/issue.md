---
description: Create a Neovim issue worktree and write a history-only no-solutions report
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
5. Run one isolated `history` role, then one isolated `integrator` role after
   `evidence/history.md` exists. Do not fork full conversation context.
   The history role uses direct-first, curated GitHub context.
6. Stop after the history report. No rbuild, repro files, fixes, or solution
   proposals.

Final output must include absolute `Report`, `Index`, and `Worktree` paths
only; no commit or attribution advice.
