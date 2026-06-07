---
name: nvim-changes
description: Set up the local nvim/mux diff-review UI for an agent's changes. Trigger ONLY on an explicit editor/mux signal — "pull the changes into nvim", "open the diff in my editor", "set up the mux review for <branch/worktree>", or `/nvim-changes`. Do NOT trigger on a generic "review" request (reviewing a PR, judging code quality, etc.); this only opens the editor UI, it does not analyze code.
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

Base and files (use `git -C <worktree>`; do not `cd` into it):

- Base: `git -C <worktree> merge-base HEAD origin/<default>` (default = origin/HEAD, else main).
- Files: `git -C <worktree> diff --name-only <base>` plus
  `git -C <worktree> ls-files --others --exclude-standard`,
  excluding `.git/ .codex/ .agents/ .worktrees/ build/ .deps/ .cmake/ .tmp/ .direnv/ result`.
- If no reviewable files, say so and stop. Do not open an empty review.

Then run the helper (it owns all live UI — git `:Diff review ++layout=unified
<base> | only`, edit quickfix of the changed files, and switches you to the
review):

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-changes/scripts/review-ui.py \
  --worktree <worktree> --base <base> -- <file>...
```

Resolve the target, base, and files in as few commands as possible; do not
narrate intermediate steps. On success, print exactly one line (worktree/branch
+ base) and stop — do not offer a code review, a follow-up, or any further
action. If the helper exits nonzero, report its error and stop; do not
hand-drive tmux/nvim/mux yourself.
