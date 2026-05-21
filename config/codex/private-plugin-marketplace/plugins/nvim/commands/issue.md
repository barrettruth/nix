---
description: Investigate a Neovim GitHub issue and write a no-solutions report
argument-hint: <issue-number>
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:issue

Arguments: $ARGUMENTS

Primary workflow for Neovim bugs.

1. Read `skills/nvim-issue/SKILL.md`.
2. Require an issue number; normalize `#12345` to `12345`.
3. Use only `gh`/`gh api` for GitHub context.
4. Fetch `upstream master`; create branch/worktree `12345` from it.
5. Create the issue wiki and ignored `.codex/issue-wiki` pointer.
6. Run `history` and `reproducer` in parallel, then `integrator`.
   Expensive builds/tests use Spark.
7. Stop after the investigation report. No fixes or solution proposals.

Final output must include absolute `Report`, `Index`, and `Worktree` paths.
