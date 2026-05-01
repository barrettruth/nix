---
name: deprecate-to-forgejo
description: Deprecate ONE github mirror — README banner, metadata redirect, archive — pointing all traffic at the canonical forgejo repo. ALL writes go to GitHub only (the opposite of github-to-forgejo).
user-invocable: true
version: 1.0.0
---

# /deprecate-to-forgejo

Take ONE `barrettruth/<name>` whose canonical home is now `git.barrettruth.com/barrettruth/<name>` and freeze the GitHub mirror with a permanent redirect to Forgejo. After this skill runs, GitHub is read-only, every search-engine and IDE-tool surface points at Forgejo, and the `luarocks` / flake-input pipelines (which already run from Forgejo CI) are unaffected.

This is the inverse of `/github-to-forgejo`: that skill migrates content TO Forgejo and never touches GitHub. This skill freezes GitHub and never touches Forgejo (except read-only verification).

## Inputs

- Single argument: repo name (e.g. `http-codes.nvim`, `vimdoc-language-server`).
- The repo MUST exist as both `barrettruth/<name>` on github.com AND `barrettruth/<name>` on git.barrettruth.com.
- The Forgejo repo MUST already be canonical-shaped per the `/github-to-forgejo` baseline (CI, topics, branch protection, GPL license, etc.).
- A local clone at `~/dev/<name>` is REQUIRED for the README-banner step. Per the post-2026-05-01 remote convention: `origin = forgejo`, `github = github`.

## Hard rules (non-negotiable)

- **GitHub-only writes.** This skill never edits the Forgejo repo. The Forgejo `main` branch must remain untouched. Reading Forgejo via `tea api` is allowed for verification.
- The README banner commit goes to `github/main` ONLY. It is never merged into local `main` and never pushed to Forgejo.
- All API mutations use `gh api -X PATCH`. The order matters: archive (`archived=true`) is ALWAYS last, because archived repos reject writes.
- Stale branch deletion happens BEFORE archive on both sides, since archived repos block branch deletion on GitHub.
- No AI attribution in any commit (no `Co-Authored-By`, no `Signed-off-by`, no tool mentions).
- No new code comments unless explicitly requested.
- This skill is **only for low-popularity repos** (rough cutoff: <50 stars, <5 forks, <5 open issues, no active PRs). Higher-popularity repos (`canola.nvim`, `tmux-mosaic`, `delta`) likely warrant a live-mirror pattern — DO NOT run this skill on them without an explicit per-repo decision.

## Pre-flight (read-only audit)

Abort with a clear message if any check fails. Do not proceed.

1. `gh api /repos/barrettruth/<name>` — confirm the repo exists, capture `archived`, `description`, `homepage`, `has_wiki`, `has_projects`, `stargazers_count`, `forks_count`, `open_issues_count`, `default_branch`. Abort if `archived=true` (already deprecated).
2. `tea api -l vps /repos/barrettruth/<name>` — confirm the Forgejo repo exists. Abort if missing.
3. Popularity gate: abort with a warning if `stargazers_count >= 50` OR `forks_count >= 5` OR `open_issues_count >= 5`. The user must explicitly override.
4. `gh pr list --repo barrettruth/<name> --state open` — abort if there are open PRs (they'd be stranded by the archive).
5. Local clone audit at `~/dev/<name>`:
   - Confirm `origin = ssh://git@git.barrettruth.com/barrettruth/<name>.git` and `github = git@github.com:barrettruth/<name>.git`. Abort if remotes are inverted or missing.
   - `git status --short` — capture uncommitted changes. If any file under `.github/workflows/*` is modified with `runs-on: nix` (a known-bad collateral edit from the corpus-wide spark→nix sweep), `git restore` it before proceeding. Other uncommitted changes block the run.
   - `git worktree list` — abort if any worktree is in a state that would block branch deletion later. Remove with `git worktree remove <path>` first.
6. Branch audit: `git branch -r --merged github/main` and `git branch -r --no-merged github/main`. For unmerged branches, query `gh pr list --state all --head <branch> --limit 1` per branch — every branch should map to a MERGED PR (squash-merged, hence "unmerged" by SHA but actually landed). Abort if any branch is genuinely orphaned with unmerged work.

## Step 0: pre-flight cleanup (no remote writes yet)

1. `git restore` any bad `.github/workflows/*` collateral edits.
2. Delete every stale feature branch on `github` AND on `origin` (forgejo). The branch delete on github MUST happen before step 5 (archive) — archived repos block branch deletion. The forgejo-side delete is a hygiene mirror; forgejo never gets archived so it's flexible.
   ```
   for b in <every-stale-branch>; do
     git push github --delete "$b"
     git push origin --delete "$b"
   done
   ```
3. `git fetch --all --prune` to drop the now-deleted remote-tracking refs.

## Step 1: README banner on `github/main` only

Make a one-shot commit on a temp branch checked out from `github/main` and push it directly to `github/main`. NEVER push to `origin` (forgejo). The forgejo README stays clean — Forgejo IS the destination, so a "moved here" banner there would be confusing.

```
git checkout -b deprecate/github-banner github/main
$EDITOR README.md   # prepend the admonition (template below)
git add README.md
git commit -m "docs: deprecate github mirror — moved to forgejo"
git push github HEAD:main
git checkout main
git branch -D deprecate/github-banner
```

Banner template (GFM admonition; renders on github with the colored note):

```markdown
> [!IMPORTANT]
> **This project has moved to <https://git.barrettruth.com/barrettruth/<name>>.**
> Issues, pull requests, and active development happen on Forgejo. This GitHub mirror is archived.
```

Two lines, no install-channel sentence. Earlier drafts included a third line such as `` `luarocks install <name>` continues to publish from Forgejo CI on tag push. `` — that was rejected on 2026-05-01 as unnecessary clutter. The forgejo URL at the top of the banner is the only redirect signal a reader needs; package-manager continuity is implicit and documented in the project README itself.

If the GitHub repo has branch protection requiring a status check (e.g. "Quality"), the push will print a warning but will succeed because the user is admin and can bypass. Do NOT silence the warning; record it in the verification log.

## Step 2: github `homepage` → forgejo URL

```
gh api -X PATCH /repos/barrettruth/<name> \
  -F homepage='https://git.barrettruth.com/barrettruth/<name>'
```

This populates the "About" sidebar's link, which most search-result snippets surface. Some IDE plugin browsers (Lazy.nvim's spec lookup, etc.) read this field too.

## Step 3: github `description` → prefix the move marker

Read the current description, prefix `[moved to git.barrettruth.com/barrettruth/<name>] `, leave the rest unchanged.

```
current=$(gh api /repos/barrettruth/<name> --jq '.description')
gh api -X PATCH /repos/barrettruth/<name> \
  -F description="[moved to git.barrettruth.com/barrettruth/<name>] $current"
```

The prefix is intentional: it shows up in github search snippets, in `gh repo view`, in third-party catalogues, and in IDE plugin pickers that surface the description. Keep the bracket form; do not use parentheses (the bracketed form is the verified pattern from 2026-05-01).

## Step 4: github metadata → align with forgejo baseline

```
gh api -X PATCH /repos/barrettruth/<name> -F has_wiki=false -F has_projects=false
```

This matches the Forgejo baseline (`has_wiki=false`, `has_projects=false`). It also tidies the github mirror — wiki and projects tabs disappear before the archive freeze.

Steps 2-4 can be done in a single `gh api -X PATCH` call to reduce API round-trips:

```
gh api -X PATCH /repos/barrettruth/<name> \
  -F homepage='https://git.barrettruth.com/barrettruth/<name>' \
  -F description="[moved to git.barrettruth.com/barrettruth/<name>] $current" \
  -F has_wiki=false -F has_projects=false
```

## Step 5: archive github

```
gh api -X PATCH /repos/barrettruth/<name> -F archived=true
```

After this, the repo is read-only on github. The "This repository has been archived" banner appears full-width at the top, all interactions are disabled, every tool that respects archive state (search engines, dependabot, etc.) treats it as deprecated.

This must be the LAST step. Anything after this would fail.

## Step 6: verification

```
gh api /repos/barrettruth/<name> \
  --jq '{archived, homepage, description, has_wiki, has_projects, has_discussions}'
```

Expected (copy-paste-comparable):

```
{
  "archived": true,
  "homepage": "https://git.barrettruth.com/barrettruth/<name>",
  "description": "[moved to git.barrettruth.com/barrettruth/<name>] <original-description>",
  "has_wiki": false,
  "has_projects": false,
  "has_discussions": false
}
```

Also confirm the README banner is live:

```
gh api /repos/barrettruth/<name>/contents/README.md --jq '.content' | base64 -d | head -10
```

The first 6 lines should be `# <name>` followed by the admonition block.

Forgejo verification (read-only):

```
tea api -l vps /repos/barrettruth/<name>/contents/README.md | jq -r '.content' | base64 -d | head -10
```

Forgejo's README must NOT have the banner. If it does, something went wrong — the banner commit ended up on the wrong remote.

## Step 7: local clone hygiene

After the deprecation, the local main may be behind `origin` (forgejo) due to forgejo-only CI commits. FF-pull from forgejo:

```
git pull origin main --ff-only
```

This will rename `.github/workflows/*` → `.forgejo/workflows/*` locally (or delete `.github/` if the forgejo CI port is older than the deprecation). That's fine — github is archived and frozen with whatever `.github/workflows/` it had at the time of archive.

## Late-stage banner edits (post-archive)

If the banner needs editing after step 5 (archive), GitHub rejects all writes — including content commits. The recipe is unarchive → edit → re-archive:

```
gh api -X PATCH /repos/barrettruth/<name> -F archived=false
git checkout -b deprecate/banner-trim github/main
$EDITOR README.md   # apply the change
git add README.md
git commit -m "docs: <description-of-the-edit>"
git push github HEAD:main
git checkout main
git branch -D deprecate/banner-trim
gh api -X PATCH /repos/barrettruth/<name> -F archived=true
```

The unarchive window should be as short as possible — anyone watching the repo will see the archive banner disappear briefly and reappear. For low-popularity repos the visibility risk is negligible.

## Reversal (if anything goes wrong)

Order matters: undo step 5 first, then everything else.

```
gh api -X PATCH /repos/barrettruth/<name> -F archived=false
gh api -X PATCH /repos/barrettruth/<name> \
  -F homepage='' \
  -F description='<original-description-without-prefix>' \
  -F has_wiki=true -F has_projects=true
git checkout -b revert/banner github/main
git revert <banner-commit-sha>
git push github HEAD:main
git checkout main
git branch -D revert/banner
```

Stale branches that were deleted are NOT recoverable from `gh api` alone — recover by force-pushing from a local clone if they still exist in `git reflog` or any backup.

## AGENTS.md update

After a successful run, append to `~/.config/nix/AGENTS.md` under `## What actually remains (post-2026-05-01)` (or the appropriate evolving section), recording:

- repo name + deprecation date
- pre-stats (stars/forks/issues at archive time)
- banner commit SHA (`f9c9e5d` for `http-codes.nvim` was the prototype)
- list of stale branches deleted (with the github+forgejo confirmation)
- any deviations from the standard recipe

## Verified prototype: `http-codes.nvim` (2026-05-01)

The first run of this skill was on `barrettruth/http-codes.nvim` (12 stars, 2 forks, 0 open issues) on 2026-05-01.

- Banner commit: `f9c9e5d` on `github/main` (`bd02a1b..f9c9e5d`); follow-up trim commit `4fedf88` (`f9c9e5d..4fedf88`) dropped the install-channel third line on 2026-05-01 (required a temporary unarchive → push → re-archive cycle)
- Forgejo `origin/main` unchanged: `5764d7f` (forgejo CI port commits) — banner did NOT propagate
- 12 stale branches deleted from each side: `chore/{add-project-configs,luarocks,replace-prettier-with-biome}`, `ci/{format-vimdoc,justfile-workflow,self-hosted-runners}`, `docs/{help-file-naming,modernize-readme}`, `feat/plug-mappings`, `feature/snacks`, `refactor/vim-g-config`, `revert/github-hosted-runners` — all squash-merged via PRs #4-#16
- Final github state: archived=true, homepage=forgejo URL, description prefixed `[moved to git.barrettruth.com/barrettruth/http-codes.nvim]`, has_wiki=false, has_projects=false
- Local clone state post-run: `~/dev/http-codes.nvim` on main = forgejo HEAD (`5764d7f`), all stale local branches and worktrees pruned
- Push warning encountered (expected): `Required status check "Quality" is expected.` — push succeeded anyway because Barrett bypasses branch protection. Recorded but not blocking.

## Out of scope

- Push-mirror from forgejo→github intentionally NOT configured. Forgejo's mirror feature only works for non-archived targets, and the github snapshot frozen at deprecation time is fine for low-popularity repos.
- Issue-template `contact_links` redirect intentionally NOT used. Once the repo is archived, github disables the issue button entirely; the redirect is moot.
- Deleting the github repo entirely: NEVER. Archiving preserves URLs, badges, search-engine indexing, and the "yes this software exists / existed" historical record. Deletion would 404 every external link to the repo.
- Higher-popularity repos: out of scope. Use a separate runbook that keeps github as a live mirror.
