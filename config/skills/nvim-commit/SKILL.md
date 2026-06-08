---
name: nvim-commit
description: Use when Barrett asks to commit — "commit this", "make/write a commit", "commit these changes", or `/nvim-commit`. Drafts a commit message that mirrors THIS repo's own history and Barrett's voice, then opens it pre-filled in the mux `vcs` window (fugitive commit buffer, unfocused) for him to review and `:wq`. Not for PRs, pushes, merges, or code review.
---

# nvim-commit

Draft a commit message and place it, pre-filled, into a fugitive commit buffer
in the mux `vcs` window — left unfocused for Barrett to review and write
himself. The helper does all the tmux/nvim work; your job is the message and
the file selection. Barrett always presses `:wq`; never commit for him.

Communication:

- Relay the helper's one-line result; do not repeat the file list or staging
  detail (it already printed them), and do not narrate precedent/resolver steps
  or that this skill ran.
- After the helper exits zero, stop. Do not verify, inspect tmux, re-open, or
  offer to push/PR/merge.

## Message — mirror the repo, not a fixed convention

There is no house commit format. Detect what THIS repo does from its own
history and match it. Conventional Commits is only one pattern that some repos
use (others — e.g. tmux/tmux — do not). From the context below, infer and
follow the dominant recent pattern:

- structure: a `type(scope):` prefix or a plain subject; whether scopes are
  used at all, and which scope fits the changed paths.
- casing, tense, subject length, trailing punctuation.
- whether bodies appear, and for what kind/size of change.

When the repo is inconsistent, follow the most recent commits on its default
branch. Do not impose structure the repo does not use; do not drop structure it
does.

## Voice — how Barrett writes (constant; overlays the repo's format)

- Terse and literal. Say what changed in as few words as possible. No filler,
  no hedging, no marketing adjectives ("robust", "powerful", "seamless",
  "comprehensive").
- Imperative present tense: `add`, `fix`, `remove`, `revamp` — never
  `added`/`adds`.
- Concrete over abstract — name the thing (`copy-mode incsearch`, `PR diff
  line numbers`), not the activity (`update logic`, `improve handling`).
- Keep the subject short; follow the repo's typical length (often ≤50 chars).
- A body is the exception, not the rule. Add one only when the subject cannot
  carry the change, and only if this repo uses bodies. When you do: explain
  why, not what; wrap ~72.
- Never invent scope or structure the repo does not use; infer scope from the
  changed paths and the repo's scope vocabulary when it does.
- Absolutely no AI/assistant/tool attribution, co-author, or signed-off
  trailers, in any form. Non-negotiable and hook-enforced.

## Context — gather in one pass

Gather it in ONE command, then draft — don't split this across calls. Read
individual hunks (`git diff -- <path>`) only if `--stat` is too coarse to name
the change, and check `git config --get commit.template` only if the subject
style is unclear.

```sh
R=$(git rev-parse --show-toplevel)
D=$(git -C "$R" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's@^origin/@@'); [ -n "$D" ] || D=$(git -C "$R" rev-parse --abbrev-ref HEAD)
git -C "$R" status --porcelain=v1                     # staged vs not (never -A)
git -C "$R" --no-pager diff --stat HEAD               # shape of the change
git -C "$R" log --no-merges -n 20 --format='%s' "$D"  # subject style
git -C "$R" log --no-merges -n 5  "$D"                # body/tone precedent
```

## Staging

- If something is already staged, draft from the staged set and leave staging
  alone.
- If nothing is staged, pass the specific files your message covers via
  `--stage` so the helper stages exactly those. Never stage everything: Barrett
  keeps per-machine, non-ignored files he does not want committed, so excluding
  unrelated working-tree noise is your judgment call.

## Run

Send the message on stdin (or `-F <file>`). Subject on line 1; a blank line then
a body only if the repo warrants one. The helper places it as the first line(s)
of the fugitive commit buffer, keeps one blank line, and leaves git's `#`
comment block beneath — so Barrett reviews and `:wq` as usual.

If nothing is staged, pass the specific files your message covers via `--stage`:

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-commit/scripts/commit-window.py --stage <path> [<path> ...] <<'MSG'
<subject>

<optional body>
MSG
```

If changes are already staged, omit `--stage`:

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-commit/scripts/commit-window.py <<'MSG'
<subject>
MSG
```

If the changes live in a worktree or a branch checked out elsewhere (e.g. one
just reviewed via `nvim-changes`), infer that from context and pass it via
`--target` — a branch name or worktree path — so staging and the commit happen
there. Default is the current project.

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-commit/scripts/commit-window.py --stage <path> ... --target <branch|worktree-path> <<'MSG'
<subject>
MSG
```

Use `--dry-run` to preview the message and staging without touching tmux/nvim.

Rules:

- Never push, open/edit PRs, merge, or run `git commit` yourself. The buffer is
  Barrett's to `:wq`.
- Never `git add -A` / `git add .`. Stage only named paths.
- Never focus the `vcs` window. Report the helper's one-line result; treat a
  zero exit as success and do not hand-drive tmux/nvim yourself.
- No AI/assistant/co-author/signed-off attribution, ever (hook-enforced).
