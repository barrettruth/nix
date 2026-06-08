---
name: nvim-pr
description: Use when Barrett asks to open a pull request — "open a PR", "make a draft PR", "PR this branch", or `/nvim-pr`. Drafts a PR title and a body that fills THIS repo's template in Barrett's voice, then opens forge.nvim's draft compose in the mux `vcs` window (unfocused) for him to review and submit. Not for committing, merging, or reviewing.
---

# nvim-pr

Open a DRAFT pull request compose for the current branch via forge.nvim — title
and template-filled body pre-written, placed in the mux `vcs` window and left
unfocused for Barrett to review and submit himself. forge.nvim does the heavy
lifting; your job is the title and the filled template body. Barrett submits
with `:w` then `:q` (which pushes the branch and creates the draft); never
submit for him.

Communication:

- Relay the helper's one-line result; don't repeat the body or narrate steps,
  and don't say this skill ran.
- After the helper exits zero, stop. Do not verify, inspect tmux, re-open, push,
  create, or submit.

## Title + body — fill the repo's template, in Barrett's voice

forge.nvim auto-discovers the repo's PR template and pre-fills a commit-derived
title. Override both: write a real PR title for the whole branch's change (not
just the last commit), and fill the repo's actual template.

- Fill WHATEVER sections the template has. Do NOT assume a Problem/Solution
  shape — templates differ per repo. Match the present template's structure and
  headings exactly.
- Leave every checkbox UNCHECKED — including any "No AI was used …" box. Barrett
  completes the checklist himself.
- If the repo has no template, write a minimal sensible body: what changed and
  why, in a couple of lines.

Detect and read the repo's template yourself (so you fill it accurately), using
forge.nvim's own path precedence for the detected forge — first match wins:

- Forgejo/Gitea: `.forgejo/pull_request_template.md`,
  `.forgejo/PULL_REQUEST_TEMPLATE.md`, `.gitea/pull_request_template.md`,
  `.gitea/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`,
  `.github/PULL_REQUEST_TEMPLATE.md`.
- GitHub: `pull_request_template.md`, `PULL_REQUEST_TEMPLATE.md`,
  `PULL_REQUEST_TEMPLATE/`, `docs/pull_request_template.md`,
  `docs/PULL_REQUEST_TEMPLATE.md`, `docs/PULL_REQUEST_TEMPLATE/`,
  `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/PULL_REQUEST_TEMPLATE/`.
- GitLab: `.gitlab/merge_request_templates/`.

## Voice — how Barrett writes (constant; overlays the repo's conventions)

- Terse and literal. No filler, no hedging, no marketing adjectives ("robust",
  "powerful", "seamless", "comprehensive").
- Concrete over abstract — name the thing, not the activity.
- Imperative/present where the prose calls for it; mirror how the repo's own
  PRs/commits read.
- Title follows the repo's subject conventions (see `nvim-commit`'s rule: mirror
  the repo, not a fixed format).
- Absolutely no AI/assistant/tool attribution anywhere, and never check a
  "No AI" box. Non-negotiable and hook-enforced.

## Context — gather in one pass

Gather it in ONE command, then draft — don't split this across calls. It shows
the branch, the commits that will be in the PR (vs the mainline it targets), and
the repo's PR template (if any) for you to fill.

```sh
R=$(git rev-parse --show-toplevel)
B=$(git -C "$R" rev-parse --abbrev-ref HEAD)
D=$(for r in upstream/HEAD upstream/main upstream/master origin/HEAD origin/main origin/master; do git -C "$R" rev-parse --verify --quiet "$r" >/dev/null 2>&1 && echo "$r" && break; done); [ -n "$D" ] || D=origin/main
echo "branch: $B  base: $D"
git -C "$R" log --no-merges --format='%s%n%b%n---' "$D"..HEAD   # the PR's commits
for t in .forgejo/pull_request_template.md .forgejo/PULL_REQUEST_TEMPLATE.md .gitea/pull_request_template.md .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md pull_request_template.md PULL_REQUEST_TEMPLATE.md docs/pull_request_template.md; do
  [ -f "$R/$t" ] && { echo "template: $t"; cat "$R/$t"; break; }
done
```

## Preconditions

- Assume the work is committed and the tree is clean. The helper BAILS if the
  working tree is dirty — if so, commit first (use `nvim-commit`) and re-run.
- The branch needs commits the base does not have; if the `log` above is empty,
  there is nothing to PR — say so and stop.

## Run

The helper opens forge.nvim's draft compose in the unfocused `vcs` window and
writes your title + filled body, preserving forge.nvim's trailing metadata block
(which carries `Draft: true`). Pass the title via `--title` and the body on
stdin.

```sh
python3 /home/barrett/.config/nix/config/skills/nvim-pr/scripts/pr-window.py --title "<pr title>" <<'BODY'
<filled template body>
BODY
```

If the branch's changes live in a worktree or a branch checked out elsewhere,
pass it via `--target` (a branch name or worktree path); default is the current
project. Pass the body via `-F <file>` instead of stdin if convenient, and use
`--dry-run` to preview the title and body without touching tmux/nvim.

Existing-PR resilience: if a PR already exists for the branch, the helper opens
the edit compose instead. It fills the body only when that PR's description is
empty (keeping the existing title); if the description already has content, it
opens the edit compose untouched.

forge.nvim handles the rest on Barrett's submit: it targets the upstream default
branch for forks, and `:w` then `:q` pushes the branch and creates the draft.

Rules:

- Never push, create, merge, or submit the PR yourself. Barrett submits with
  `:w` then `:q`.
- Never check a "No AI" box or add AI/assistant/co-author/signed-off attribution.
- Never focus the `vcs` window. Report the helper's one-line result; treat a
  zero exit as success and do not hand-drive tmux/nvim/forge yourself.
- Do not commit here. If the tree is dirty the helper bails — relay that and stop.
