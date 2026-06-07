---
name: nvim-changes
description: Use when Barrett asks to review an agent's local changes or pull up their diff (e.g. "review the agent's changes", "diff review this branch/worktree"). Locates the worktree/branch and populates the mux edit window with the changed files and the mux git window with a unified :Diff review. Review-UI setup only; no edits.
---

# nvim-changes

Set up a local review UI for an agent's working changes. Review-UI setup only:
never edit, stage, commit, push, or mutate remotes; never run builds/tests.

Target:

- If Barrett names a branch, worktree, or PR ref, use it.
- Else auto-discover: `git worktree list --porcelain`; pick the non-current
  worktree that is dirty or ahead of its merge-base. If several qualify, list
  them and ask. If you are already in a linked worktree, review it.

Always review through a worktree; never disturb the main checkout:

- Reuse the target branch's worktree, or create one:
  `git -C <repo> worktree add <repo>/.worktrees/review-<branch> <branch>`
  (fetch first if remote-only). Never `git switch`/`checkout` main or `git stash`.

Base and files (run inside the worktree):

- Base: `git merge-base HEAD origin/<default>` (default = origin/HEAD, else main).
- Files: `git diff --name-only <base>` plus `git ls-files --others --exclude-standard`,
  excluding `.git/ .codex/ .agents/ .worktrees/ build/ .deps/ .cmake/ .tmp/ .direnv/ result`.
- If no reviewable files, say so and stop. Do not open an empty review.

Then run the helper (it owns all live UI — git `:Diff review ++layout=unified
<base> | only`, edit quickfix of the files, foreground restore):

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-changes/scripts/review-ui.py \
  --worktree <worktree> --base <base> -- <file>...
```

Treat zero exit as success; do not inspect tmux unless it fails or Barrett says
the UI is wrong. Keep updates to one line: the worktree/branch and base.
