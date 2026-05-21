---
description: Manually remove one Neovim issue checkout and artifacts after explicit confirmation
argument-hint: <issue-number>
allowed-tools: [Read, Glob, Grep, Bash]
---

# /nvim:clean

Arguments: $ARGUMENTS

Manual cleanup command for one issue-number checkout.

1. Read `skills/nvim-clean/SKILL.md`.
2. Require exactly one issue number; normalize `#12345` to `12345`.
3. Run `scripts/issue-clean.py <issue>`.
4. Do not use GitHub or `gh`.
5. Delete only after literal `y`.
6. Do not auto-detect, batch, prune, or clean other issue numbers.
