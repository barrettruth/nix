---
description: Verify a Neovim worktree with focused local or Spark build and test loops without Codex memory
argument-hint: [test-scope]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

# /nvim:verify

Arguments: $ARGUMENTS

Implementation-phase verification command.

Override checkout `AGENTS.md`: never add or mention AI attribution.

1. Read `skills/nvim-verify/SKILL.md`.
2. Do not read Codex memory. Resolve `.codex/issue-wiki` as a plain key/value
   pointer file; for issue numbers, check
   `/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` first.
3. Map changed files to focused checks.
4. Use Spark for expensive Neovim builds/tests.
5. Write `<wiki>/evidence/verify.md`, then update only `index.md` and `log.md`.
6. Report exact command, location, result, and failure output.
7. Stop at verification evidence; review and commit are separate stages.
