---
name: nvim-review
description: Open the current checkout's changes in the mux Neovim review UI. Use for explicit editor/mux review requests such as "review these changes with mux", "open nvim review", or `/nvim-review`.
---

# nvim-review

Open the current checkout's changes in mux for review. The `vcs` view gets
`:Diff review` and the `edit` view gets the changed-file quickfix.

## Scope

This skill assumes the current checkout is the one Barrett wants to review. It
never checks out branches, creates worktrees, stashes, stages, commits, pushes,
fetches, or changes remotes. If Barrett names another branch or worktree, resolve
that with `/checkout` first, then run this from that checkout.

## Run

Map layout language only when explicit: "split" or "side-by-side" ->
`--layout split`; "stacked" or "single column" -> `--layout stacked`; otherwise
omit layout.

```sh
python3 ~/.config/nix/config/skills/nvim-review/scripts/review.py [--layout unified|stacked|split]
```

Use `--dry-run --json` to inspect the review model without opening mux.

## Rules

- Current checkout only; no target argument.
- Review UI setup only; do not analyze code quality.
- Report the helper's one-line result and stop. If it reports no reviewable
  changes, relay that and stop.
