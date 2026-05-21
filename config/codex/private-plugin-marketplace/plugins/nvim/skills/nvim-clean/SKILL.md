---
name: nvim-clean
description: Use when Barrett invokes `/nvim:clean 12345` or explicitly asks to remove one specific Neovim issue-number worktree. Performs manual local cleanup only; never auto-detects, batches, uses GitHub, or deletes without y/N confirmation.
---

# nvim-clean

Use only for explicit manual cleanup of one issue-number worktree.

Rules:

- Require exactly one issue number; normalize `#12345` to `12345`.
- Operate only under `/home/barrett/dev/neovim/.worktrees/<issue>`.
- Inspect local git state only. Do not use `gh`, GitHub, or online status.
- Show worktree path, branch, and dirty status before prompting.
- Prompt exactly `Remove worktree <path> and branch <issue>? y/N`.
- Delete only after literal `y`; default is no.
- Use `git worktree remove <path>` and `git branch -d <issue>`.
- Do not use force removal, `branch -D`, `rm -rf`, prune, or batch cleanup unless
  Barrett explicitly asks for force cleanup.

Suggested inspection:

```sh
git -C /home/barrett/dev/neovim worktree list --porcelain
git -C /home/barrett/dev/neovim/.worktrees/12345 status --short
git -C /home/barrett/dev/neovim branch --list 12345
```

Stop and report if the worktree path or branch is missing, dirty, or not the
exact issue number. Do not infer merged/closed status.

Read `../../references/guardrails.md`.
