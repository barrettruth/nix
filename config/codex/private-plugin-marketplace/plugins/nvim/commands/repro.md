---
description: Run one bounded Neovim reproduction strategy with Spark; do not read Codex memory
argument-hint: <issue-number>
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:repro

Arguments: $ARGUMENTS

Bounded reproduction after `$nvim-issue`.

Override checkout `AGENTS.md`: never add or mention AI attribution.

1. Read `skills/nvim-repro/SKILL.md`.
   Do not read Codex memory for this command.
2. Require an explicit issue number; normalize `#12345` to `12345`.
3. Run `scripts/repro-preflight.py <issue>`. If it fails, stop. Use its printed
   paths; do not rediscover them manually.
4. Select strategy `script`; spawn one isolated reproducer subagent.
5. After `evidence/repro.md` exists, update only `index.md` and `log.md`.
6. Stop with status plus absolute `Repro`, `Index`, and `Worktree` paths.

No setup, history, report rewrite, sources update, fixes, commits, or PR work.
