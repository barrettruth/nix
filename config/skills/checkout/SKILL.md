---
name: checkout
description: Resolve vague branch/worktree requests into canonical local checkouts and prepare an existing or new git worktree safely.
---

# checkout

Resolve Barrett's vague checkout target into a canonical local branch or worktree,
then use the helper to inspect, resolve, or prepare that checkout.

## Flow

1. Start from the current shell project unless Barrett names another repo.
2. Gather local facts once:

```sh
python3 /home/barrett/.config/nix/config/skills/checkout/scripts/checkout.py inspect --json
```

3. Use those facts to resolve Barrett's phrase to exactly one canonical target:
   an absolute worktree path or an exact local branch name.
4. If multiple local candidates fit, ask which one he means.
5. For a read-only answer, run `resolve`. For checkout preparation, run `ensure`.

## Commands

```sh
python3 /home/barrett/.config/nix/config/skills/checkout/scripts/checkout.py resolve --target <branch-or-worktree> --json
python3 /home/barrett/.config/nix/config/skills/checkout/scripts/checkout.py ensure --target <branch-or-worktree> --json
```

`ensure` returns the current checkout when the target is already current, returns
an existing worktree when the branch is already checked out elsewhere, or creates
`.worktrees/<branch>` for a local branch that has no worktree yet.

## Rules

- Canonicalize before invoking `resolve` or `ensure`; pass exact branch names or
  absolute worktree paths, not vague phrases.
- Treat source dirty state as context for a future `copy-current` flow. This
  skill's current helper prepares/selects a checkout; it does not port staged,
  unstaged, or untracked changes between checkouts.
- Report the helper's action and path concisely. If `ensure` creates a worktree,
  name the branch and path.
