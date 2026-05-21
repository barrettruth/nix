---
description: Verify a Neovim worktree with focused local or Spark build and test loops
argument-hint: [test-scope]
allowed-tools: [Read, Glob, Grep, Bash]
---

# /nvim:verify

Arguments: $ARGUMENTS

Implementation-phase verification command.

1. Read `skills/nvim-verify/SKILL.md`.
2. Map changed files to focused checks.
3. Use Spark for expensive Neovim builds/tests.
4. Report exact command, location, result, and failure output.
