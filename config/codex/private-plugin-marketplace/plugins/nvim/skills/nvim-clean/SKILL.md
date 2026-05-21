---
name: nvim-clean
description: Use when Barrett invokes `$nvim-clean 12345` or explicitly asks to remove one specific Neovim issue-number checkout. Performs manual full cleanup for that issue only; never auto-detects, batches, uses GitHub, or deletes without y/N confirmation.
---

# nvim-clean

Use only for explicit manual cleanup of one issue-number checkout.

Rules:

- Require exactly one issue number; normalize `#12345` to `12345`.
- Run `../../scripts/issue-clean.py <issue>`.
- Do not use `gh`, GitHub, or online status.
- Show the script's cleanup plan before prompting.
- Prompt `Hard remove all Neovim issue <issue> cleanup targets? y/N`.
- Delete only after literal `y`; default is no.
- Hard cleanup removes the local worktree, local branch, issue wiki, local Spark
  logs, Spark mirror, and current pointer when it points at the issue.
- Do not auto-detect, batch, prune, or clean other issue numbers.

Script-owned targets:

```text
/home/barrett/dev/neovim/.worktrees/<issue>
/home/barrett/.local/state/codex-nvim/issues/<issue>
/home/barrett/.local/state/spark/nvim/<issue>
spark:/home/barrett/dev/neovim/.worktrees/<issue>
/home/barrett/dev/neovim/.worktrees/.codex/current
```

Read `../../references/guardrails.md`.
