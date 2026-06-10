---
name: nvim-changes
description: Set up the local nvim/mux diff-review UI for an agent's changes. Trigger ONLY on an explicit editor/mux signal — "review these changes with mux", "pull the changes into nvim", "open the diff in my editor", "set up the mux review for <branch/worktree>", or `/nvim-changes`. Do NOT trigger on a generic "review" request (reviewing a PR, judging code quality, etc.); this only opens the editor UI, it does not analyze code.
---

# nvim-changes

Open an agent's changes for review in mux — the `vcs` window gets a
`:Diff review` (unified by default; `--layout` chooses otherwise), the `edit`
window gets a quickfix of the changed files, in the session you're attached to.
Review-UI setup only: never edit, stage, commit, push, mutate remotes, or run
builds/tests.

The helper does all the work: resolves the target to a worktree (reuses it if
the branch is already checked out so uncommitted work is included; creates
`.worktrees/review-<branch>` only for a bare branch; never switches/stashes the
main checkout), computes the base (merge-base with the default branch), collects
changed + untracked files, and builds the live windows. Run it **once**:

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-changes/scripts/review-ui.py [--repo <repo-root>] [--layout unified|stacked|split] [<branch|worktree-path>]
```

Turn the request into the args, then run that single command:

- "review these changes" / no specific target → run with **no args** (reviews
  the worktree of the project you're attached to).
- a named branch → `--repo <repo-root> <branch>`.
- a worktree (or a PR you can resolve to one) → pass its path.
- layout → `--layout` (default `unified`). Map the request: "split" /
  "side-by-side" → `--layout split`; "stacked" / "single column" →
  `--layout stacked`; otherwise omit it.

Report the helper's one-line result and stop. Do not narrate intermediate
steps, and do not offer a code review or any follow-up. If it prints "no
reviewable changes", relay that and stop. If it exits nonzero, report the error
and stop — do not hand-drive nvim/mux yourself.
