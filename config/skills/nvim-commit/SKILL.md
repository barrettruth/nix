---
name: nvim-commit
description: Use when asked to commit — "commit this", "make/write a commit", "commit these changes", or `/nvim-commit`. Drafts a commit message that mirrors THIS repo's own history and the user's voice, then opens it pre-filled in the mux `vcs` window (fugitive commit buffer, unfocused) for the user to review and `:wq`. Not for PRs, pushes, merges, or code review.
---

# nvim-commit

Draft a commit message into a fugitive commit buffer in the mux `vcs` view,
left unfocused for the user to review and `:wq`. The helper does the nvim work;
your job is the message and which files to stage.

## Message — mirror the repo, not a fixed convention

There is no fixed format — some repos use `type(scope):`, others (e.g. tmux) use
a plain subject. Detect this repo's pattern from its recent history and match it:

- structure: `type(scope):` prefix or plain subject; whether scopes are used,
  and which scope fits the changed paths.
- casing, tense, subject length, trailing punctuation.
- whether bodies appear, and for what kind/size of change.

When the repo is inconsistent, follow its most recent default-branch commits.

## Voice

- Terse, literal, concrete — name the thing, not the activity.
- Imperative present: `add`, `fix`, `remove`, `revamp`.
- Subject as short as the repo runs (often ≤50 chars).
- Body only when the subject can't carry the change and the repo uses bodies:
  explain why, not what; wrap ~72.

## Context — gather in one pass

Run one command, then draft. Read a hunk (`git diff -- <path>`) or
`git config --get commit.template` only when the stat or style is unclear.

```sh
R=$(git rev-parse --show-toplevel)
D=$(git -C "$R" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's@^origin/@@'); [ -n "$D" ] || D=$(git -C "$R" rev-parse --abbrev-ref HEAD)
git -C "$R" status --porcelain=v1                     # staged vs not
git -C "$R" --no-pager diff --stat HEAD               # shape of the change
git -C "$R" log --no-merges -n 20 --format='%s' "$D"  # subject style
git -C "$R" log --no-merges -n 5  "$D"                # body/tone precedent
```

## Run

Send the message on stdin (or `-F <file>`): subject on line 1, then a blank line
and a body if the repo uses one. If something is already staged the helper
commits that; otherwise pass the specific files your message covers via `--stage`
(only those — not unrelated working-tree noise).

```sh
python3 ~/.config/nix/config/skills/nvim-commit/scripts/commit-window.py --stage <path> [<path> ...] <<'MSG'
<subject>

<optional body>
MSG
```

Omit `--stage` when changes are already staged. For changes in a worktree or a
branch checked out elsewhere (e.g. one reviewed via `nvim-review`), add
`--target <branch|worktree-path>`. Use `--dry-run` to preview.

## Rules

- Stage only named paths; never `git add -A` / `git add .`.
- Never push, open/edit PRs, merge, or run `git commit` yourself — the user `:wq`s.
- Never focus the `vcs` window. Report the helper's one-line result and stop on a
  zero exit.
- No AI/assistant/co-author/signed-off attribution, ever (hook-enforced).
