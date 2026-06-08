---
name: nvim-pr
description: Use when Barrett asks to open a pull request — "open a PR", "make a draft PR", "PR this branch", or `/nvim-pr`. Drafts a PR title and a body filling THIS repo's template in Barrett's voice, then opens forge.nvim's draft compose in the mux `vcs` window for him to review and submit. Not for committing, merging, or reviewing.
---

# nvim-pr

Draft a PR title and body into forge.nvim's draft compose in the mux `vcs`
window, left unfocused. forge.nvim discovers and loads the repo's template, and
on Barrett's `:w` then `:q` pushes the branch and creates the draft. Your job is
the title and body; Barrett submits.

## Title and body

Write a title for the whole branch's change (not just the last commit), and fill
the template the Context shows, matching its sections and headings.

- Describe what the change does, grounded in the diff (`git diff <base>..HEAD`),
  the commits, and the work you actually did. Use numbers or issue/PR references
  only when they come from that work.
- Match the template's length; with no template, a line or two — what changed and
  why.
- Leave the template's checkboxes for Barrett.

## Voice

Same as `nvim-commit` — terse, literal, concrete; no AI/assistant attribution
anywhere in the title or body.

## Context — gather in one pass

```sh
R=$(git rev-parse --show-toplevel)
B=$(git -C "$R" rev-parse --abbrev-ref HEAD)
D=$(for r in upstream/HEAD upstream/main upstream/master origin/HEAD origin/main origin/master; do git -C "$R" rev-parse --verify --quiet "$r" >/dev/null 2>&1 && echo "$r" && break; done); [ -n "$D" ] || D=origin/main
echo "branch: $B  base: $D"
git -C "$R" log --no-merges --format='%s%n%b%n---' "$D"..HEAD
for t in .forgejo/pull_request_template.md .forgejo/PULL_REQUEST_TEMPLATE.md .gitea/pull_request_template.md .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md pull_request_template.md PULL_REQUEST_TEMPLATE.md docs/pull_request_template.md; do
  [ -f "$R/$t" ] && { echo "template: $t"; cat "$R/$t"; break; }
done
```

Read the diff (`git diff "$D"..HEAD`) when the log isn't enough to describe the
change accurately.

## Run

Pass the title via `--title` and the body on stdin. The branch must be committed
and the tree clean — the helper exits otherwise (commit first with `nvim-commit`).
An empty `log` means there is nothing to PR.

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-pr/scripts/pr-window.py --title "<pr title>" <<'BODY'
<filled template body>
BODY
```

Options: `--target <branch|worktree-path>` for changes checked out elsewhere,
`-F <file>` for the body, `--dry-run` to preview. If a PR already exists for the
branch the helper opens its edit compose, filling the body only when the PR's
description is empty.

## Rules

- Barrett submits (`:w` then `:q`); never push, create, or submit yourself.
- Never focus the `vcs` window. Report the helper's one-line result and stop on a
  zero exit.
