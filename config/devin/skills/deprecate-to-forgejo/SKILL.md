---
name: deprecate-to-forgejo
description: Make the GitHub mirror of ONE repo passively reflect Forgejo via push-mirror with an SSH deploy key. Forgejo becomes canonical; GitHub auto-syncs. No archive, no manual github writes after setup.
user-invocable: true
version: 2.0.0
---

# /deprecate-to-forgejo

Take ONE `barrettruth/<name>` whose canonical home is now `git.barrettruth.com/barrettruth/<name>` and reconfigure the GitHub mirror so it passively reflects Forgejo. After this skill runs, every push to forgejo `main` propagates to github `main` within seconds via Forgejo's `sync_on_commit` push-mirror over SSH; humans never push to github directly. The local clone keeps only `origin = forgejo`.

This is the inverse of `/github-to-forgejo`: that skill migrates content TO Forgejo and never touches GitHub. This skill configures GitHub as a forgejo-driven mirror and never touches Forgejo content (Forgejo metadata is read-only here too).

## Architecture

```
[user] → git push → forgejo (canonical, /repos/.../main)
                       ↓ sync_on_commit=true via SSH deploy key
                    github (passive mirror, /repos/.../main)
```

- Forgejo generates an ed25519 keypair when the push-mirror is created with `use_ssh=true`. The private half stays inside Forgejo's database, encrypted at rest. The public half is registered on GitHub as a per-repo deploy key with `read_only=false` so it can push.
- Forgejo pushes on every commit to `main` (or whichever branch is filtered) plus a 1-hour fallback interval (`MIN_INTERVAL = 10m` per app.ini, `DEFAULT_INTERVAL = 1h`).
- The deploy key is scoped to ONE repo on GitHub. It cannot reach any other repo. If compromised, blast radius is one repo.
- GitHub stays **unarchived**, otherwise the mirror push gets rejected. Branch protection on github main is irrelevant for the mirror because deploy keys with write access bypass branch protection by default; if you want extra safety, leave branch protection off on github (already true for most public-corpus repos).

## Inputs

- Single argument: repo name (e.g. `http-codes.nvim`, `vimdoc-language-server`).
- The repo MUST exist as both `barrettruth/<name>` on github.com AND `barrettruth/<name>` on git.barrettruth.com.
- The Forgejo repo MUST already be canonical-shaped per the `/github-to-forgejo` baseline (CI, topics, branch protection, GPL license, etc.).
- A local clone is REQUIRED for the sync step. Per the post-2026-05-01 inversion convention: `origin = forgejo`, `github = github` (which we will remove at the end).

## Hard rules (non-negotiable)

- **Forgejo content is read-only here.** This skill never edits forgejo branches, never pushes to forgejo, never modifies forgejo's README, description, topics, or branch protection. Reading forgejo via `tea api` (push_mirrors and similar) is allowed.
- **GitHub stays unarchived.** Earlier versions of this skill ended in `archived=true`; that's no longer the recipe. If GitHub is currently archived (legacy v1 deprecation), unarchive it first via `gh api -X PATCH ... -F archived=false`.
- All API mutations on GitHub use `gh api -X PATCH` or `gh api -X POST`. No git pushes to github from a human; only forgejo pushes via the mirror.
- All push-mirror configuration goes through Forgejo's API, not the UI, so the operation is reproducible.
- No AI attribution in any commit or any github metadata field.
- This skill is for low-popularity repos and personal-config repos. Higher-popularity repos (`canola.nvim`, `tmux-mosaic`, `delta`) likely warrant a different pattern (e.g. dual-canonical hosts, or live two-way sync). DO NOT run this skill on those without explicit per-repo decision.

## Sync before mirror (lossless local↔forgejo↔github reconciliation)

Before configuring the mirror, the local clone, forgejo, and github mains must be reconciled. Otherwise the first mirror sync overwrites github with forgejo content and any github-only commits are lost forever.

1. `git remote -v` — confirm what remotes exist. If a `forgejo` remote is missing, add it: `git remote add forgejo ssh://git@git.barrettruth.com/barrettruth/<name>.git`.
2. `git fetch --all --prune`.
3. Compare the three SHAs: local `main`, `github/main` (or `origin/main` depending on remote layout), `forgejo/main`. If they diverge:
   - **forgejo has commits local doesn't** (e.g. private-repo subtree merges): rebase local main onto forgejo (`git rebase forgejo/main`). Different file paths between the two histories usually means a clean rebase with no conflicts.
   - **local has commits no remote has**: those will be replayed on top during the rebase.
   - **github has commits forgejo doesn't** (e.g. an old v1 deprecation banner committed only to github): cherry-pick those onto forgejo OR drop them, depending on whether the content is worth keeping. The github-only banner from v1 is intentionally dropped (the new banner / metadata pattern replaces it).
4. After rebase, push the new tip to forgejo (FF if forgejo/main is in main's ancestry; force-push needed otherwise — check protection rules, may need to temporarily DELETE/POST the forgejo branch protection on `main`).
5. Verify `local main = forgejo/main`. The mirror sync in Step 5 below will then update github to match.

Skip this step only if the three SHAs already match (or if local + forgejo match and github will be brought in line by the first mirror sync).

## Pre-flight (read-only audit)

Abort with a clear message if any check fails. Do not proceed.

1. `gh api /repos/barrettruth/<name>` — confirm the repo exists, capture `archived`, `description`, `homepage`, `has_wiki`, `has_projects`, `stargazers_count`, `forks_count`, `open_issues_count`, `default_branch`, `private`. If `archived=true`, plan to unarchive before mirror config.
2. `tea api -l vps /repos/barrettruth/<name>` — confirm the Forgejo repo exists. Abort if missing.
3. `tea api -l vps /repos/barrettruth/<name>/push_mirrors` — capture existing mirrors. If a mirror to github is already configured (`remote_address` matches), skip Steps 5-7 and just verify it's still healthy.
4. Popularity gate (public repos only): abort with a warning if `stargazers_count >= 50` OR `forks_count >= 5` OR `open_issues_count >= 5`. The user must explicitly override.
5. `gh pr list --repo barrettruth/<name> --state open` — abort if there are open PRs (they'd be stranded once humans stop pushing to github).
6. Local clone audit:
   - Confirm origin = forgejo (or rename github → github / forgejo → origin if pre-inversion).
   - `git status --short` — capture uncommitted. Resolve before proceeding.
   - `git worktree list` — abort if any worktree has uncommitted state. Remove with `git worktree remove <path>`.
7. Stale branch audit: `git branch -r` and `git ls-remote --heads github` and `git ls-remote --heads origin`. Compare. Plan deletion of all stale feature branches on both sides BEFORE configuring the mirror — otherwise the first sync force-pushes forgejo's branches over github's, which can include unintended deletions.

## Step 0: pre-flight cleanup (no remote writes yet)

1. `git restore` any bad uncommitted edits (e.g. accidental `runs-on: nix` on `.github/workflows/*`).
2. Delete every stale feature branch on both `github` AND `origin` (forgejo). After this skill runs, the mirror handles branch creation/deletion automatically; doing it once-by-hand now keeps the initial state clean.
   ```
   for b in <every-stale-branch>; do
     git push github --delete "$b"
     git push origin --delete "$b"
   done
   ```
3. `git fetch --all --prune` to drop the now-deleted remote-tracking refs.

## Step 1: unarchive github (if archived from v1 deprecation)

```
gh api -X PATCH /repos/barrettruth/<name> -F archived=false
```

If the repo wasn't archived, skip. If it WAS archived under v1, this is a one-time cleanup.

## Step 2: github-only mirror banner via `.github/README.md`

GitHub renders `.github/README.md` in preference to root `README.md` when both exist. Forgejo always renders root `README.md`. **This is the asymmetric-README mechanism.** The same git tree contains both files; each forge picks the one it prefers.

Build `.github/README.md` as `<title-line>` + banner + full body of root README. Github visitors see banner at top + full project content below (the v1 experience). Forgejo visitors see only root README, no banner — they're already at the canonical URL, the banner would be self-referential.

```
header=$(head -1 README.md)
rest=$(tail -n +2 README.md)
mkdir -p .github
cat > .github/README.md <<EOF
$header

> [!IMPORTANT]
> This is a read-only mirror of <https://git.barrettruth.com/barrettruth/<name>>. Use Forgejo for issues, PRs, and active development.
$rest
EOF
git add .github/README.md
git commit -m "docs(.github): prepend mirror banner + include full readme content"
```

Push to forgejo. Mirror propagates `.github/README.md` to github automatically. Github immediately starts rendering it as the repo README.

### Maintenance contract

`.github/README.md` is **a copy of root `README.md` with a banner prepended**. When root README updates, `.github/README.md` must be regenerated using the same recipe above. Otherwise github's view drifts from the canonical content.

Options for keeping them in sync:

- **Manual** (current default): regenerate by hand whenever root README changes.
- **CI step on forgejo** (recommended for repos with frequent README churn): a job in `.forgejo/workflows/quality.yaml` or a dedicated `sync-mirror-readme.yaml` that on push to main rebuilds `.github/README.md` from root + banner template, commits via the forgejo signing key, pushes to main. Mirror then propagates the regen.
- **Symlink-with-prepend script** in the repo (e.g. `just sync-readme`): captured in justfile so a contributor runs it before commit.

For low-churn repos (`nix`, `http-codes.nvim`, dotfile-style configs), manual is fine. For active projects (`vimdoc-language-server`), CI sync is worth setting up.

### v1 history (for context)

V1 deprecation pushed a "moved to forgejo" banner commit directly to github main. Under v2, the mirror would overwrite github main with forgejo content on first sync, so the v1 banner got dropped automatically.

A 2026-05-01 attempt to add `> [!NOTE] Issues and PRs at <forgejo URL>` banners to forgejo `main` of http-codes.nvim, nix, and vimdoc-language-server was reverted same-day after the user pointed out the banners read as self-referential on forgejo. Subsequent attempt with banner-only `.github/README.md` (no project content) was also rejected — github lost the full project README. Final working pattern (this Step 2): `.github/README.md` = title + banner + full root README content, regenerated as needed. Verified commits: `839d4ed` (http-codes.nvim), `63fd62b` (nix), `3e26b1b` (vimdoc-language-server).

## Step 3: configure forgejo→github push-mirror via SSH

```
tea api -l vps -X POST /repos/barrettruth/<name>/push_mirrors \
  -H "Content-Type: application/json" \
  -d '{
    "remote_address": "ssh://git@github.com/barrettruth/<name>.git",
    "use_ssh": true,
    "sync_on_commit": true,
    "interval": "1h0m0s"
  }'
```

The response includes `public_key` (an `ssh-ed25519 ...` line). **Save it for Step 4.**

Why these settings:
- `use_ssh=true` — Forgejo generates a per-mirror keypair; private key never leaves the server. No PAT to rotate.
- `sync_on_commit=true` — every push to forgejo immediately pushes to github (typical lag: <2s for small commits).
- `interval=1h0m0s` — periodic safety-net sync if `sync_on_commit` ever misses a push (network blip, etc.). `MIN_INTERVAL=10m` per app.ini, `DEFAULT_INTERVAL=1h`.
- No `branch_filter` — all branches mirror. Empty string means "all". Use `"main"` to limit if needed.

## Step 4: register forgejo's public key as a github deploy key

Take the `public_key` from Step 3's response:

```
PUBKEY="<ssh-ed25519 ... line from Step 3>"
gh api -X POST /repos/barrettruth/<name>/keys \
  -F title="forgejo push-mirror (vps)" \
  -F key="$PUBKEY" \
  -F read_only=false
```

`read_only=false` is critical — forgejo needs write access to push. The key is scoped to this single GitHub repo; it cannot reach any other repo on Barrett's account.

## Step 5: trigger immediate sync to verify

```
tea api -l vps -X POST /repos/barrettruth/<name>/push_mirrors-sync
sleep 3
tea api -l vps /repos/barrettruth/<name>/push_mirrors | jq '.[0] | {last_update, last_error}'
```

Expected: `last_error=""` and `last_update` within the last few seconds. If `last_error` is non-empty, debug:
- "Permission denied" — the deploy key wasn't accepted; verify the key was added with `read_only=false`.
- "Updates were rejected because the tip of your current branch is behind" — github main has commits forgejo doesn't (you skipped the sync step above); fix the divergence and retry.
- "remote: error: GH013: Repository was archived" — github is still archived; run Step 1.

Then confirm the SHAs:
```
forgejo: $(tea api -l vps /repos/barrettruth/<name>/branches/main | jq -r '.commit.id')
github:  $(gh api /repos/barrettruth/<name>/git/refs/heads/main --jq '.object.sha')
```
Must match.

## Step 6: github description → mirror prefix

Replace whatever's currently there (including any `[moved to ...]` prefix from v1) with:

```
gh api -X PATCH /repos/barrettruth/<name> \
  -F description='[mirror of git.barrettruth.com/barrettruth/<name>] <original-description>'
```

This is the primary github-side signal that the github view is a passive copy.

## Step 7: github homepage + metadata baseline + disable issue-filing

```
gh api -X PATCH /repos/barrettruth/<name> \
  -F homepage='https://git.barrettruth.com/barrettruth/<name>' \
  -F has_wiki=false -F has_projects=false -F has_issues=false
```

## Step 7a: auto-close incoming PRs via GitHub Actions

GitHub does NOT have a `has_pull_requests=false` repo setting — PRs are fundamental to github's data model and there's no toggle. For user-owned (non-org) public repos, you also can't disable forking (`allow_forking` only affects private forks; public repos always allow public forks). So PR creation is structurally unblockable on github.

The standard mirror-repo defense is a workflow that auto-closes any incoming PR with a redirect comment. Commit it to forgejo's `.github/workflows/redirect-pr-to-forgejo.yaml`; the mirror propagates it to github; github actions fires it on every new PR.

```yaml
name: redirect-pr-to-forgejo

on:
  pull_request_target:
    types: [opened, reopened]

permissions:
  pull-requests: write
  issues: write

jobs:
  redirect:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const forgejoUrl = `https://git.barrettruth.com/${context.repo.owner}/${context.repo.repo}`;
            const body = [
              'Thank you for the contribution.',
              '',
              `This GitHub repo is a read-only mirror. Please reopen this PR on [Forgejo](${forgejoUrl}).`,
            ].join('\n');
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              body: body,
            });
            await github.rest.pulls.update({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.payload.pull_request.number,
              state: 'closed',
            });
```

Why these settings:
- `pull_request_target` (not `pull_request`) — runs against the BASE repo's workflow (not the fork's), so it has access to the `GITHUB_TOKEN` needed to comment + close. `pull_request` from a fork cannot mutate the base.
- `runs-on: ubuntu-latest` — github-hosted runner. Not `nix` (forgejo runner label, doesn't exist on github).
- `permissions: pull-requests: write, issues: write` — minimum needed to comment + close.
- `actions/github-script@v7` — pinned major version, no need for a custom action.

Forgejo runners don't read `.github/workflows/*` so this workflow is github-only by construction. The `.forgejo/workflows/*` workflows continue to handle CI on forgejo.

## Step 7b: add `mirror` topic on github

GitHub doesn't expose a native "Mirror of X" badge for our setup (the `mirror_url` field is read-only via PATCH; it's only set by github's own Import flow which is destructive to use on existing repos). The `mirror` topic is the closest non-destructive replacement — a chip that shows on the repo card and makes the repo findable via topic search.

```
existing=$(gh api /repos/barrettruth/<name>/topics --jq '.names | map(.) + ["mirror"] | unique')
gh api -X PUT /repos/barrettruth/<name>/topics --input - <<JSON
{"names": $existing}
JSON
```

Do NOT add the `mirror` topic to forgejo's topics — forgejo topics describe what the project IS (e.g. `neovim-plugin`, `lsp-server`). The github side is the only place where the github↔forgejo mirror relationship is meaningful enough to topic-tag.

`has_issues=false` is the durable fix that prevents new issues from being filed on github (where they'd be orphaned from forgejo, since the mirror is git-only). Existing issues stay readable in the historical record but the "New Issue" button disappears and the issues tab hides. Forgejo has all the issues from the original `/github-to-forgejo` migration plus any filed on forgejo since; new filings from anyone hitting the github URL get redirected by the description prefix and homepage link.

Steps 6-7 can be batched into a single PATCH call.

### Why issues don't auto-sync (and why has_issues=false is the right fix)

Two distinct Forgejo features get conflated here. The original `/github-to-forgejo` skill used Forgejo's **"Migrate from URL"** feature, which does a one-shot bulk import via the github issues API: it pulls issues, PRs, releases, labels, comments, milestones into forgejo's database at repo-creation time. That's how every forgejo repo got its existing issue history.

This skill (push-mirror) is implemented as `git push --all` over SSH. **Issues live in forgejo's database, not in git refs**, so `git push` cannot move them. There is no equivalent of "Migrate from URL" going the other direction — github has no inbound issue-import API that takes a forgejo URL, and Forgejo has no outbound "create-github-issues-from-my-issues" feature.

Practical consequence: existing pre-mirror issues already exist on both forges (they were copied at the original migration). Newly-filed issues on github after this skill runs would be orphaned. `has_issues=false` blocks that scenario at the source.

## Step 8: remove `github` remote from the local clone

After the mirror is verified, remove the `github` remote from the local clone so accidental `git push github main` from muscle memory is impossible:

```
cd ~/dev/<name>   # or appropriate path
git remote remove github
git remote -v   # should show only origin = forgejo
```

This is the "old github remote" that we explicitly retire under v2. Forgejo is the only place humans push to. Github auto-syncs.

## Verification (post-setup)

```
gh api /repos/barrettruth/<name> \
  --jq '{archived, homepage, description, has_wiki, has_projects}'
```

Expected:
```
{
  "archived": false,
  "homepage": "https://git.barrettruth.com/barrettruth/<name>",
  "description": "[mirror of git.barrettruth.com/barrettruth/<name>] <original-description>",
  "has_wiki": false,
  "has_projects": false
}
```

Plus the SHA check from Step 5 plus:
```
gh api /repos/barrettruth/<name>/keys --jq '.[] | {title, read_only, verified}'
```
Should include the `forgejo push-mirror (vps)` deploy key with `read_only=false, verified=true`.

End-to-end smoke test: make a trivial commit on forgejo (e.g. via `tea api` or via local clone push to origin), wait <5s, check github main updated.

## Private repo shortcut

If `gh api /repos/barrettruth/<name> --jq .private` returns `true`, the metadata steps are mostly moot but the mirror plumbing still applies:

1. Pre-flight + sync.
2. Skip Step 2 (no banner — nobody's reading).
3. Run Step 3 (push-mirror).
4. Run Step 4 (deploy key).
5. Run Step 5 (verify sync).
6. Skip Step 6 (description prefix optional, useful only as a self-reminder).
7. **Run Step 7 anyway** — set `has_issues=false has_wiki=false has_projects=false` even on private repos. The defenses are still useful: nobody (including future-you on a different machine) can accidentally file a github issue. Skip homepage if you don't care.
8. Run Step 8 (remove `github` remote).

The simplest private flow: pre-flight, sync, mirror, deploy key, sync, disable github features, remove remote. Done.

## Reversal (if anything goes wrong)

To restore the v1 "archived" pattern:
```
gh api /repos/barrettruth/<name>/keys --jq '.[] | select(.title | startswith("forgejo push-mirror")) | .id' \
  | xargs -I{} gh api -X DELETE /repos/barrettruth/<name>/keys/{}
tea api -l vps /repos/barrettruth/<name>/push_mirrors --jq '.[].remote_name' \
  | xargs -I{} tea api -l vps -X DELETE /repos/barrettruth/<name>/push_mirrors/{}
gh api -X PATCH /repos/barrettruth/<name> -F archived=true
```

To restore content (e.g. broken sync wiped a commit you cared about): `git reflog` on forgejo's database (only forgejo admin can read these), or push from a local clone that still has the commit.

## AGENTS.md update

After a successful run, append to `~/.config/nix/AGENTS.md` recording:
- repo name + mirror config date
- push-mirror `remote_name` (forgejo's internal handle, e.g. `remote_mirror_DwJDEvtH49W`)
- deploy key `id` on github
- any deviations from the standard recipe

## Verified prototype: `http-codes.nvim` (2026-05-01, v2.0.0)

The first run of this skill on the new mirror pattern was on `barrettruth/http-codes.nvim` on 2026-05-01.

- Pre-state: github `archived=true` (from v1 deprecation), local `origin = forgejo`, banner commit `4fedf88` on github main only.
- v1 → v2 upgrade: unarchive github, mirror config replaces archive.
- Push-mirror created: `remote_name=remote_mirror_DwJDEvtH49W`, `sync_on_commit=true`, `interval=1h`.
- Deploy key on github: `id=150229527`, title=`forgejo push-mirror (vps)`, `read_only=false`, `verified=true`.
- First sync: `last_error=""`, github main went from `4fedf88` (banner commit) to `5764d7f` (forgejo HEAD). Banner dropped.
- github description: `[mirror of git.barrettruth.com/barrettruth/http-codes.nvim] HTTP status code viewer for neovim`.
- github homepage: `https://git.barrettruth.com/barrettruth/http-codes.nvim`.
- Local clone `~/dev/http-codes.nvim`: `github` remote removed, only `origin = forgejo` remains.
- Final github metadata: `archived=false, has_wiki=false, has_projects=false, homepage=<forgejo>, description=[mirror of ...]`.

## Out of scope

- Issue-template `contact_links` redirect — moot when github is unarchived but read-only-by-convention. Description prefix + homepage do the job.
- Two-way sync (forgejo↔github both writable) — explicitly NOT this skill. Forgejo is canonical; github is passive.
- Deleting the github repo — NEVER. The mirror keeps it useful for inbound links, search-engine cache, and people who already have it bookmarked.
- Higher-popularity repos — out of scope. Use a separate runbook that handles a more involved mirror+sync pattern.
