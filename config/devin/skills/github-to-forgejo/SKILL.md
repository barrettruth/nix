---
name: github-to-forgejo
description: Prep ONE forgejo repo to a tmux-mosaic-shaped baseline — migration completeness check, metadata, topics, license verify, heatmap backfill, .forgejo workflow, branch protection. ALL writes go to Forgejo only.
user-invocable: true
version: 5.2.0
---

# /github-to-forgejo

Bring ONE Forgejo repo at `git.barrettruth.com/barrettruth/<name>` up to the canonical tmux-mosaic-shaped baseline. **All writes go to Forgejo. The skill never opens GitHub PRs, never edits GitHub repos.** GitHub may be read as a fallback data source (e.g. for description/website seeding), but is never mutated.

The previous "github-to-forgejo" framing implied bidirectional sync. The migration is now a one-way pull: Forgejo is canonical, GitHub is a passive mirror that we no longer maintain through this skill.

## Inputs

- Single argument: repo name (e.g. `delta`, `cp.nvim`, `midnight.nvim`).
- Repo MUST already exist on Forgejo as `barrettruth/<reponame>` (was migrated previously by Forgejo's "migrate from URL" flow).
- A local clone at `~/dev/<reponame>` is OPTIONAL — only Phase 1 and Phase 4 use it. If it's missing the skill skips those phases.

## Hard rules (non-negotiable)

- **Forgejo-only writes.** This skill never opens GitHub PRs. It never edits the GitHub repo (no LICENSE writes, no topic edits, no description edits, no branch protection edits). Reading GitHub data via `gh api` is allowed as a seed for Forgejo writes.
- All Forgejo writes that go through the API are server-signed by `F09FD58E4737029E` because `[repository.signing] CRUD_ACTIONS = always` is set in app.ini.
- All git commits the skill creates locally are signed (`git commit -S`). The ssh+gpg signing setup is already wired in the user's `~/.gitconfig`.
- No AI attribution in any commit (no `Co-Authored-By`, no `Signed-off-by`, no tool mentions).
- No new code comments unless explicitly requested by the user.
- Private Forgejo repos are out of scope (per `~/.config/nix/AGENTS.md`'s "Forgejo private repo policy"). Skill aborts if asked to run on one.
- Forgejo's LICENSE is canonical. The skill VERIFIES Forgejo has GPLv3 and aborts otherwise; it does NOT compare against GitHub.

## Learned porting conventions (2026-05-04)

These are the cross-repo lessons that must be preserved before another public
repo is moved to `git.barrettruth.com`:

- **Do not trust local remotes until verified.** A local clone can still have
  `origin = github` even when the Forgejo repo is already correct. Before any
  local audit, run `git remote -v`, confirm Forgejo is the remote being read, and
  fetch explicitly. If the task is to inspect Forgejo state, prefer `tea api` or
  a confirmed Forgejo `origin/main`; do not report GitHub-only stale files as
  Forgejo findings.
- **Use `.yaml` for new Forgejo and GitHub workflow files.** Existing `.yml`
  files can be ported as part of a deliberate cleanup, but new files should use
  `.yaml`.
- **Workflow top-level `name:` is part of the public check contract.** Forgejo
  renders status contexts as `<workflow-name> / <job-display-name> (<event>)`.
  Removing top-level `name:` produces contexts like `/ Format`, which is worse.
  Branch protection contexts must be exact literal strings with the event suffix.
- **Mixed check prefixes require split workflow files.** `needs:` only orders
  jobs inside one workflow, and one workflow has one prefix. To get
  `quality / Format` and `deploy / LuaRocks` on the same commit, use separate
  workflow files with top-level names `quality` and `deploy`.
- **Do not hide statuses with job-level `if`.** Forgejo creates job statuses
  before job-level conditions are evaluated. A skipped stable deploy job can
  still show as a waiting/skipped status on a main-push nightly run. Split the
  trigger files instead.
- **Do not add visible gate jobs for deploy waits.** If a deploy/nightly workflow
  must wait for quality while keeping the `deploy / ...` prefix, poll Forgejo
  commit statuses inside the publish job before the publish step. A visible
  `Quality Gate` job is not wanted.
- **Production deploys are manual-only unless explicitly requested.** Main-push
  nightly releases are fine when the repo expects them, but production website
  deploys should not run on every merge unless the user asks for that behavior.
- **`.github` is not Forgejo scaffolding.** Port reusable GitHub templates to
  `.forgejo` and generate `.forgejo/workflows/quality.yaml`; then remove GitHub
  CI/template leftovers from the Forgejo-facing scaffold. The only deliberate
  `.github` files in a Forgejo-canonical repo are GitHub-only mirror UX files
  created by `/deprecate-to-forgejo`: `.github/README.md` and, for approved
  low/no-popularity mirrors, `.github/workflows/redirect-pr-to-forgejo.yaml`.
- **Ported templates must not point users back to GitHub.** When creating
  `.forgejo/issue_template/*` or `.forgejo/pull_request_template.md`, rewrite
  Barrett-owned owner/repo links like
  `https://github.com/barrettruth/<repo>/issues`,
  `https://github.com/barrettruth/<repo>/discussions`, and quoted
  `barrettruth/<repo>` examples to the corresponding Forgejo URLs. Do not
  rewrite unrelated upstream GitHub links.
- **Release fixes happen before version tags.** Open PRs for workflow/release
  repairs first, merge them, pull `main`, verify local CI plus live Forgejo push
  CI, then tag. Keep the repo's existing tag style; if previous release tags are
  lightweight, create the next tag as lightweight too.
- **URL/vimdoc work is separate.** Do not mix install-source URL rewrites into
  this migration baseline unless the user asked for that repo. Use the
  `/forgejo-install-docs` skill for README, vimdoc, rockspec, package metadata,
  and generated-site link cleanup.

## Pre-flight

1. `tea api -l vps /repos/barrettruth/<name>` returns 200 and `private=false` and `archived=false`. ABORT otherwise.
2. The repo HAS a LICENSE on Forgejo and it classifies as GPLv3 (Phase 3 verifies content; this is just an existence check).
3. Save the current branch protection state on `main`, then DELETE it:
   ```
   tea api -l vps "/repos/barrettruth/<name>/branch_protections/main" > /tmp/<name>-protection.json
   tea api -l vps -X DELETE "/repos/barrettruth/<name>/branch_protections/main"
   ```
   The DELETE is required because Phase 4's force-push is gated by Forgejo on a code path that is independent of `enable_push` — even `enable_push=true` returns `branch main is protected from force push` and `pre-receive hook declined`. Only the absence of a protection rule allows the force-push. Phase 6 re-creates the canonical schema at the end. If no protection rule exists (404 from the GET), this step is a no-op; record that fact for Phase 6 (it will use POST instead of an idempotent re-create).
4. If a local clone exists at `~/dev/<name>` (or `~/.config/nix` for the special-case `nix` repo), AUTO-REPAIR any non-canonical state. The clone may have drifted from the `~/dev/CLAUDE.md` "Local `~/dev` repo remote policy" (`origin = github`, `forgejo = forgejo`); pre-v4.2 the skill aborted on drift, but in practice every drifted clone has the same recoverable shape, so the skill now repairs it idempotently. Repair sub-steps, in order:

   **4a. Remote layout repair.** Three canonical URLs:
   - `expected_gh = git@github.com:barrettruth/<name>.git`
   - `expected_fj_ssh = ssh://git@git.barrettruth.com/barrettruth/<name>.git`
   - `expected_fj_short = git@git.barrettruth.com:barrettruth/<name>.git`

   ```
   origin_url=$(git remote get-url origin 2>/dev/null || true)
   forgejo_url=$(git remote get-url forgejo 2>/dev/null || true)

   # case A: origin already canonical github URL → nothing to do for origin
   # case B: origin points at forgejo (either URL form) and no separate `forgejo` remote exists
   #         → rename origin → forgejo, then add github as origin
   if [ "$origin_url" = "$expected_fj_ssh" ] || [ "$origin_url" = "$expected_fj_short" ]; then
     if [ -z "$forgejo_url" ]; then
       # capture the list of branches that currently track "origin" (which means forgejo here);
       # we re-track them to "forgejo" after the rename so the user's PR/feature workflow keeps working
       mapfile -t origin_tracked < <(git for-each-ref --format='%(refname:short)|%(upstream:short)' refs/heads/ \
         | awk -F'|' '$2 ~ /^origin\// {print $1}')
       git remote rename origin forgejo
       git remote add origin "$expected_gh"
       for b in "${origin_tracked[@]}"; do
         [ "$b" = "main" ] && continue   # main re-tracks origin (github); see step 4d
         git config branch."$b".remote forgejo
       done
     else
       # both `origin` AND `forgejo` exist with forgejo URLs — pathological; abort
       ABORT "both origin and forgejo remotes point at forgejo URLs; resolve manually"
     fi
   elif [ "$origin_url" != "$expected_gh" ]; then
     ABORT "origin URL is neither github nor forgejo (got: $origin_url)"
   fi

   # ensure forgejo remote exists pointing at the canonical SSH URL
   if [ -z "$(git remote get-url forgejo 2>/dev/null)" ]; then
     git remote add forgejo "$expected_fj_ssh"
   fi

   git fetch origin 2>&1 | tail -3
   ```

   **4b. Save and stash any dirty edits.** The user may have intentional in-progress work in the worktree (mid-edit feature branches, runs-on tweaks, etc.). Stash with a clearly labeled message so Phase 8 can find and pop it precisely:

   ```
   stash_marker="github-to-forgejo skill v$(awk '/^version:/ {print $2}' SKILL.md) pre-flight stash"
   if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
     git stash push -u -m "$stash_marker"
     stashed=true
   else
     stashed=false
   fi
   ```

   **4c. originalBranch capture + checkout main.**

   ```
   originalBranch=$(git rev-parse --abbrev-ref HEAD)
   [ "$originalBranch" = "main" ] || git checkout main
   ```

   **4d. Local main may carry a stale forgejo-only LICENSE switch.** This happens when a previous run pulled main from a remote that pointed at forgejo (so local main inherited the forgejo-only LICENSE commit) and the remote was then re-pointed at github (where that commit doesn't exist). Detect by counting commits ahead of `origin/main` (now github). Save the GPL blob first so Phase 0 can re-apply it after remigrate, then `git reset --hard origin/main`:

   ```
   git fetch origin main:refs/remotes/origin/main
   ahead=$(git rev-list --count refs/remotes/origin/main..HEAD)
   if [ "$ahead" -gt 0 ]; then
     mkdir -p /tmp/<name>
     if [ -f LICENSE ] && head -3 LICENSE | grep -q 'GENERAL PUBLIC LICENSE'; then
       base64 -w0 LICENSE > /tmp/<name>/LICENSE.gpl.b64
     fi
     git reset --hard refs/remotes/origin/main
   fi
   ```

   **4e. Final FF.** Now that everything is canonical, the FF pull should be a no-op — but verify:

   ```
   git pull --ff-only origin main
   ```
   If this fails, ABORT (genuine non-FF history requires a human).

   **If the clone is missing entirely** (no `~/dev/<name>` directory): skip Phase 1 and Phase 4 — only API-only phases run.

If any pre-flight fails, abort with the exact reason.

5. **GPG agent warm-up (only if a local clone exists).** Phase 4 may run `git rebase --gpg-sign`, which fails mid-rebase with "No passphrase given" if the gpg-agent has no cached passphrase and pinentry can't reach the user. Trigger one signing operation up-front so the agent caches the passphrase for the rest of the run:
   ```
   echo warmup | gpg --status-fd 1 --clearsign >/dev/null
   ```
   If this errors, ask the user to unlock the key (or provide an alternative path) before continuing. Do NOT silently fall back to `--no-gpg-sign` here — Forgejo's `require_signed_commits=true` ruleset will reject unsigned commits at push time anyway.

Special path note: `nix` is at `~/.config/nix`, not `~/dev/nix`. If asked to run on `nix`, run from `~/.config/nix` instead. Do not auto-clone any repo — if a clone is missing, just skip the local-clone-dependent phases.

## Phase ordering rationale

The skill writes to forgejo `main` in three ways:

- Phase 0 may DELETE the entire repo and re-do "migrate from URL" if the original migration left issues/PRs/labels/milestones/releases unmigrated. This is the most destructive phase, but it is fully recoverable from GitHub.
- Phase 4 does a `git push --force-with-lease forgejo forgejo:main` over SSH (after rebasing forgejo's unique commits onto `origin/main`). This requires that NO branch protection rule exists on `main` — `enable_push=true` is NOT enough; Forgejo blocks force-pushes via a separate code path that ignores `enable_push`.
- Phase 5 does an API content write (`POST/PUT /repos/.../contents/.forgejo/workflows/quality.yaml`). This requires the protection rule to either not exist or have `enable_push=true`.

Therefore:

1. Pre-flight saves the protection state and (if it exists) **DELETES the protection rule entirely**. Relaxing `enable_push=false→true` is insufficient for Phase 4's force-push; only deletion clears all blockers.
2. Phase 0 runs first if the repo's migration is incomplete. It will itself delete the repo, so the protection rule is implicitly gone afterwards too.
3. Phases 1–5 do their work. Phase 4 always runs before Phase 5 so that the workflow commit Phase 5 writes ends up on top of the reconciled history (not stranded behind a forgejo-unique LICENSE commit).
4. Phase 6 re-creates the full canonical protection schema at the end via `POST /branch_protections`.

Note: this is a **delete-and-recreate** pattern, not a temp-disable-and-restore pattern. The v3 skill described it as "relax then restore"; that wording was inaccurate because Forgejo's force-push gate is independent of `enable_push`.

## Phase 0 — Migration completeness check + remigrate (Forgejo only; possibly destructive)

Forgejo's "migrate from URL" flow only imports issues, PRs, labels, milestones, and releases when the corresponding flags (`issues=true`, `pull_requests=true`, `labels=true`, `milestones=true`, `releases=true`) are set. Many existing `barrettruth/*` Forgejo repos were migrated WITHOUT those flags (the original sweep set only the bare minimum), so they ended up with the git history but with zero issues/PRs/labels/milestones. Phase 0 detects this state and re-does the migration with full flags.

### Step 0.1: count comparison

For each of (issues, pulls, labels, milestones, releases), compare GitHub vs Forgejo. The skill considers Forgejo's migration "incomplete" if Forgejo has STRICTLY FEWER than GitHub on any of these counts:

```
gh_issues=$(gh api --paginate "repos/barrettruth/<name>/issues?state=all&per_page=100" --jq 'map(select(.pull_request | not)) | length' | awk '{s+=$1} END {print s+0}')
gh_pulls=$(gh api --paginate "repos/barrettruth/<name>/pulls?state=all&per_page=100" --jq 'length' | awk '{s+=$1} END {print s+0}')
gh_labels=$(gh api "repos/barrettruth/<name>/labels?per_page=100" --jq 'length')
gh_milestones=$(gh api "repos/barrettruth/<name>/milestones?state=all&per_page=100" --jq 'length')
gh_releases=$(gh api "repos/barrettruth/<name>/releases?per_page=100" --jq 'length')

fj_issues=$(tea api -l vps "/repos/barrettruth/<name>/issues?state=all&type=issues&limit=1&page=1" -i 2>&1 | awk '/^X-Total-Count/ {print $2+0}')
fj_pulls=$(tea api -l vps "/repos/barrettruth/<name>/issues?state=all&type=pulls&limit=1&page=1" -i 2>&1 | awk '/^X-Total-Count/ {print $2+0}')
fj_labels=$(tea api -l vps "/repos/barrettruth/<name>/labels" | jq 'length')
fj_milestones=$(tea api -l vps "/repos/barrettruth/<name>/milestones?state=all" | jq 'length')
fj_releases=$(tea api -l vps "/repos/barrettruth/<name>/releases" | jq 'length')
```

If `fj_issues < gh_issues` OR `fj_pulls < gh_pulls` OR `fj_labels < gh_labels` OR `fj_milestones < gh_milestones` OR `fj_releases < gh_releases` → **incomplete**. Skip the rest of Phase 0 if all are equal-or-greater.

A small PR shortfall is acceptable and EXPECTED — Forgejo cannot represent some external-fork PRs (dependabot, contributors who deleted their fork's source branch). Empirically this is ~25% of PRs for active repos. Treat `fj_pulls / gh_pulls >= 0.7` as "complete enough" to avoid pointless remigrations. Issues, labels, milestones, and releases must match exactly though.

### Step 0.2: remigrate (only if incomplete)

The only practical path to fix an incomplete migration is to delete the repo and re-do `POST /repos/migrate` with all flags. Forgejo's migrate API does NOT support adopting issues/PRs into an existing repo.

What gets destroyed and what survives:

| Survives | Destroyed |
|----------|-----------|
| GitHub-side history (re-cloned from `origin`) | Any forgejo-unique commits (LICENSE switch, prior workflow file) — must be re-applied after |
| GitHub-side tags, branches | Forgejo branch protection rules (Phase 6 re-creates) |
| GitHub-side labels, milestones, issues, PRs (now properly migrated this time) | Forgejo heatmap action rows (re-emitted at lower count after migration) |
| Topics (Forgejo migrate copies them) | Repo settings (Phase 2 re-applies) |

Sequence:

```
# capture the current GPL LICENSE blob BEFORE delete so step 0.3 can re-apply it.
# pre-flight Phase 3 already verified Forgejo's LICENSE is GPLv3, so this is always the right blob.
mkdir -p /tmp/<name>
tea api -l vps "/repos/barrettruth/<name>/contents/LICENSE" \
  | jq -r .content | tr -d '\n' > /tmp/<name>/LICENSE.gpl.b64

# pre-flight already deleted the protection rule, so no further blocker
tea api -l vps -X DELETE "/repos/barrettruth/<name>"

# remigrate with all data flags
GH_TOKEN=$(gh auth token)
jq -n --arg t "$GH_TOKEN" --arg n "<name>" --arg d "<description>" '{
  service: "github",
  clone_addr: ("https://github.com/barrettruth/" + $n),
  repo_owner: "barrettruth",
  repo_name: $n,
  description: $d,
  private: false,
  mirror: false,
  wiki: false,
  labels: true,
  issues: true,
  pull_requests: true,
  milestones: true,
  releases: true,
  lfs: false,
  auth_token: $t
}' | tea api -l vps -X POST "/repos/migrate" -d @-
```

The `description` should be carried over from the pre-flight read of the existing Forgejo repo. The `auth_token` is single-use, never written to disk by the skill.

The migrate API call can take 30–120 seconds for active repos (gha-ratelimit-bound on the GitHub side). Forgejo returns 200 once the git clone is done; issue/PR migration continues asynchronously for another minute or two. Re-poll `X-Total-Count` on `/issues?type=pulls` until it stops growing OR matches GitHub:

```
prev=-1; while true; do
  cur=$(tea api -l vps "/repos/barrettruth/<name>/issues?state=all&type=pulls&limit=1&page=1" -i 2>&1 | awk '/^X-Total-Count/ {print $2+0}')
  echo "fj pulls so far: $cur"
  [ "$cur" = "$prev" ] && [ "$cur" -gt 0 ] && break
  prev=$cur
  sleep 15
done
```

### Step 0.3: re-apply LICENSE switch

Remigration restores GitHub's LICENSE on Forgejo. Since GitHub LICENSEs are still mostly MIT (per `~/.config/nix/AGENTS.md`'s "GitHub LICENSE drift is acknowledged technical debt; OUT OF SCOPE"), Forgejo's LICENSE will revert to MIT after remigration.

The skill MUST re-apply the GPL switch via API (server-signed by `F09FD58E4737029E`).

**Source of the GPL blob.** The skill stores the GPL blob at `/tmp/<name>/LICENSE.gpl.b64` (single line, no newline). It gets there via one of two paths, in priority order:

1. **From the existing forgejo repo, BEFORE the delete.** Step 0.2 above ALWAYS captures the current LICENSE blob into `/tmp/<name>/LICENSE.gpl.b64` immediately before `tea api -X DELETE`, regardless of whether the LICENSE happens to be GPL or something else (Phase 3 verified GPL during pre-flight, so it always is).
2. **From the local clone, captured by pre-flight step 4d.** If pre-flight detected a stale forgejo-only LICENSE switch on local main (`ahead > 0`), it saved the GPL blob from `LICENSE` on disk to the same path before the `git reset --hard`.

Both paths write to the SAME file, so step 0.3 is agnostic to which one ran. If neither ran (e.g. clone-less repo with a previous Phase 0 that didn't capture), fall back to pulling from a known-good Forgejo repo:

```
if [ ! -s /tmp/<name>/LICENSE.gpl.b64 ]; then
  tea api -l vps "/repos/barrettruth/tmux-mosaic/contents/LICENSE" \
    | jq -r .content | tr -d '\n' > /tmp/<name>/LICENSE.gpl.b64
fi
```

`tmux-mosaic` is the canonical reference because it's frozen as the baseline (see "Canonical baseline (frozen 2026-04-30)" below). If `tmux-mosaic` is itself the target of the current run, both paths above will have populated the file already from its pre-delete state, so the fallback never fires.

Apply:

```
gpl_b64=$(tr -d '\n' < /tmp/<name>/LICENSE.gpl.b64)
sha=$(tea api -l vps "/repos/barrettruth/<name>/contents/LICENSE" | jq -r .sha)

jq -n --arg c "$gpl_b64" --arg s "$sha" '{
  message: "chore: switch license to GPL",
  content: $c,
  sha: $s,
  branch: "main"
}' | tea api -l vps -X PUT "/repos/barrettruth/<name>/contents/LICENSE" -d @-
```

The resulting LICENSE commit becomes the only forgejo-unique commit until Phase 5 adds the workflow on top. Phase 4's case-3 path ("forgejo ahead only") will handle it as a no-op-push (forgejo already has all of `origin/main`).

### Step 0.4: re-fetch local refs (only if local clone)

Local `refs/remotes/forgejo/main` is now stale (the remote has been deleted+recreated, so fetch will reject as non-fast-forward). Force-update:

```
git fetch -f forgejo main:refs/remotes/forgejo/main
git branch -f forgejo refs/remotes/forgejo/main
```

After Phase 0, the rest of the skill proceeds normally. Phase 1 sees a clean `forgejo` branch tracking the freshly-migrated `forgejo/main`.

## Phase 1 — Local clone setup (local clone only)

Skip if no local clone exists.

The skill maintains TWO local branches with disjoint roles:

- `main` tracks `origin/main` (GitHub mirror). Never modified by the skill except for the fast-forward pull in pre-flight.
- `forgejo` tracks `forgejo/main` (Forgejo canonical). This is the branch the skill rebases and pushes from in Phase 4.

This split exists because Forgejo has its own history (server-signed LICENSE switches, API-written `.forgejo/workflows/quality.yaml`, future API CRUD commits) that is NOT on GitHub. Conflating the two roles into a single `main` branch (which the v2 skill did) means a Phase-4 force-push of `main:main` destroys forgejo's unique history. The dedicated `forgejo` branch makes "what we push to forgejo" an explicit ref that we can rebase, inspect, and force-push without ambiguity.

```
git remote get-url forgejo 2>/dev/null \
  || git remote add forgejo ssh://git@git.barrettruth.com/barrettruth/<name>.git
git config branch.main.remote origin
git config branch.main.merge refs/heads/main

git fetch forgejo main:refs/remotes/forgejo/main
git branch -f forgejo refs/remotes/forgejo/main
git config branch.forgejo.remote forgejo
git config branch.forgejo.merge refs/heads/main
```

`origin` (GitHub) stays as `main`'s tracking remote per `~/dev/CLAUDE.md`'s "Local `~/dev` repo remote policy". The skill never pushes to `origin`. The local `forgejo` branch is solely for the skill's bookkeeping; the user's day-to-day workflow on `main` is unaffected.

## Phase 2 — Forgejo metadata + repo settings (API; Forgejo writes only)

Read GitHub's metadata as a seed (READ ONLY) via `gh api repos/barrettruth/<name>` and apply to Forgejo. For TEXT-typed fields (description, website) only set them where Forgejo's value is empty AND GitHub has something useful — never blank existing Forgejo values. For BOOLEAN/ENUM canonical fields, **always overwrite** — the canonical baseline values must be applied unconditionally.

Apply via `tea api -l vps -X PATCH /repos/barrettruth/<name>` with these fields:

| Field | Value | Always send? |
|-------|-------|--------------|
| `description` | GitHub's `description` if Forgejo's is empty | only when changing |
| `website` | GitHub's `homepage` if Forgejo's is empty | only when changing |
| `has_wiki` | `false` | **always** |
| `has_projects` | `false` | **always** |
| `default_branch` | `main` | **always** |
| `allow_merge_commits` | `false` | **always** |
| `allow_squash_merge` | `true` | **always** |
| `allow_rebase` | `true` | **always** |
| `allow_rebase_explicit` | `true` | **always** |
| `allow_fast_forward_only_merge` | `false` | **always** |
| `default_merge_style` | `"squash"` | **always** |
| `default_delete_branch_after_merge` | `true` | **always** |

**Why "always send" for booleans/enums.** Forgejo's "migrate from URL" flow re-defaults each of `has_wiki`, `has_projects`, `allow_merge_commits`, `allow_fast_forward_only_merge`, `default_merge_style`, `default_delete_branch_after_merge` (and possibly more) on every fresh import. If Phase 2's PATCH only re-sends fields the pre-flight read showed as wrong, freshly-remigrated repos can leak a non-canonical bool through (e.g. `has_projects=true` after migrate even though pre-flight read it as `false` from the pre-delete state). Always-send is cheap (one API call, idempotent) and guarantees the canonical baseline.

Concrete payload:

```
tea api -l vps -X PATCH "/repos/barrettruth/<name>" -d '{
  "has_wiki": false,
  "has_projects": false,
  "default_branch": "main",
  "allow_merge_commits": false,
  "allow_squash_merge": true,
  "allow_rebase": true,
  "allow_rebase_explicit": true,
  "allow_fast_forward_only_merge": false,
  "default_merge_style": "squash",
  "default_delete_branch_after_merge": true
}'
```

`description` and `website` get patched separately, only when they need to change (the skill's diff-mindedness still applies to text fields where the user might be deliberate).

The skill never PATCHes the GitHub repo. If GitHub's metadata is also stale, that is out of scope for this skill.

### Topic tags

Topics live on a separate endpoint and aren't part of the `EditRepoOption` body. Forgejo-only:

1. Read Forgejo's topics: `tea api -l vps /repos/barrettruth/<name>/topics | jq -r .topics`.
2. If non-empty → no action.
3. If empty AND a per-repo recommended set exists in the table at the bottom of this skill → write that set to Forgejo: `tea api -l vps -X PUT /repos/barrettruth/<name>/topics -d '{"topics": [...]}'`.
4. If empty AND no recommended set exists → fall back to GitHub's topics (`gh api repos/barrettruth/<name> --jq .topics`) if non-empty; otherwise skip.

Topic constraints: lowercase ASCII, digits, single hyphens; ≤35 chars; no leading/trailing hyphens. Normalize before pushing (lowercase, replace whitespace with `-`).

The skill never PUSHes topics to GitHub. As of 2026-04-30 all 24 public repos already have aligned, non-empty topics on both sides (one-time backfill via this skill plus a manual pass), so future runs will report "topics already populated".

Source-of-truth for the non-topic settings above is the live tmux-mosaic state (see "Canonical baseline" below).

## Phase 3 — License verify (Forgejo only)

Read Forgejo's LICENSE: `tea api -l vps "/repos/barrettruth/<name>/contents/LICENSE" | jq -r .content | base64 -d` (try `LICENSE`, `LICENSE.md`, `LICENSE.txt` in order).

Classify:
- `GPL` if it contains `GNU GENERAL PUBLIC LICENSE`.
- Anything else → ABORT with the actual first line and a pointer to AGENTS.md's `License cleanup pass on Forgejo` note. The license cleanup pass is supposed to leave every public Forgejo repo on GPLv3; if this repo isn't, fix it manually and rerun the skill.

The skill does NOT read or write GitHub's LICENSE. It does NOT modify the local clone's LICENSE. GitHub's LICENSE drift is acknowledged technical debt, but resolving it is out of scope here.

As of 2026-04-30: all 24 public Forgejo repos are GPLv3, so this phase passes for every public target.

## Phase 4 — Reconcile forgejo with origin/main + heatmap backfill

Skip if no local clone.

This phase has two jobs:

1. **Propagate genuine GitHub commits to Forgejo.** When GitHub merges a PR (e.g. `fix: ... (#225)`), forgejo doesn't see it automatically — the original "migrate from URL" import was a one-shot. Forgejo MUST receive these commits, otherwise forgejo's `main` lags GitHub indefinitely. **HIGH PRIORITY: forgejo needs those changes.**
2. **Backfill Forgejo's contribution heatmap.** Forgejo emits `action` table rows at push time; pushing GitHub's history through the local clone re-emits those rows.

The previous v2 design tried to do both with a single `git push --force forgejo main:main`, which destroyed forgejo-unique commits (LICENSE switches, API workflow commits). v3 does it with a rebase: take forgejo's unique commits and replay them on top of `origin/main`, then force-push the result.

### Step 1: refresh both refs

```
git fetch origin main:refs/remotes/origin/main
git fetch forgejo main:refs/remotes/forgejo/main
git branch -f forgejo refs/remotes/forgejo/main
```

### Step 2: classify the divergence

```
forgejo_unique=$(git rev-list refs/remotes/forgejo/main ^refs/remotes/origin/main)
origin_unique=$(git rev-list refs/remotes/origin/main ^refs/remotes/forgejo/main)
```

Four cases. The skill picks one and acts:

| `origin_unique` | `forgejo_unique` | Action |
|----------------|------------------|--------|
| empty          | empty            | **No-op.** forgejo == origin/main; nothing to backfill. |
| non-empty      | empty            | **Fast-forward.** `git push forgejo refs/remotes/origin/main:main`. Tags push next. |
| empty          | non-empty        | **No-op (forgejo ahead).** forgejo has API commits but no GitHub-side updates to propagate. Tags push only. |
| non-empty      | non-empty        | **Rebase + force-push.** See Step 3 below. |

### Step 3: rebase forgejo's unique commits onto origin/main (case 4 only)

```
git checkout forgejo
git rebase --gpg-sign refs/remotes/origin/main
```

This replays each commit in `forgejo_unique` on top of `refs/remotes/origin/main`. The replay re-signs every replayed commit with the user's local signing key (per the user's `commit.gpgsign = true` and `gpg.format` in `~/.gitconfig`). The original commit SHAs change.

**Loss-of-server-signature is acceptable.** The originals were server-signed by `F09FD58E4737029E` because they were API writes. After rebase the same commits are LOCALLY signed by the user. Forgejo's UI still shows them as verified, just attributed to the user's key instead of the server signing key. This is the price of merging the histories cleanly. The skill notes the SHA churn in Phase 8.

If the rebase hits a conflict, ABORT:

```
git rebase --abort
echo "ABORT: forgejo<->origin rebase conflict; resolve manually then rerun phase 4"
exit 1
```

The skill does NOT attempt automated conflict resolution. Conflicts mean the same path was edited differently on each side and a human has to choose.

### Step 4: push the reconciled forgejo branch

```
git fetch --tags --force origin
git push --force-with-lease=main forgejo forgejo:main
git push --tags forgejo
```

`--force-with-lease=main` (without an explicit `<expect>`) defaults to the value of `refs/remotes/forgejo/main` from the fetch in Step 1. The push aborts if forgejo/main has moved since (concurrent admin write); avoid plain `--force` to keep this race-safe.

The `git fetch --tags --force origin` prelude is required because moving/rolling tags (e.g. `nightly`, `latest`, `stable`) on the local clone may be stale relative to GitHub. `git push --tags` is all-or-nothing: a single rejected tag (`! [rejected] nightly -> nightly (already exists)`) aborts the entire batch. Realigning the local tags with GitHub first guarantees that all tags either match or fast-forward on the forgejo side, since Phase 0's remigrate (or the original migration) brought GitHub's tags onto Forgejo. If you skip this step, expect tag-push failures whenever the user's local clone has older snapshots of moving tags.

Tags push naturally; no need to explicitly migrate releases — Forgejo creates basic tag/release entries on push.

### Heatmap delta

- Before: `tea api -l vps "/users/barrettruth/heatmap" | jq 'map(.contributions) | add'`
- After: same, expect a higher number (or unchanged if forgejo already had the commits).

### Branch-protection interaction

Step 4's push is a real git push to `main`. The pre-flight already DELETED any pre-existing protection rule (see "Phase ordering rationale"). Phase 6 re-creates the canonical schema after Phase 5. Do NOT attempt to relax-then-restore: Forgejo's force-push gate ignores `enable_push=true` and rejects the push with `branch main is protected from force push` and `pre-receive hook declined`. Only the absence of a protection rule allows the force-push.

## Phase 5 — `.github/` port + cleanup + `.forgejo/workflows/quality.yaml`

Phase 5 has three sub-phases, all writing to forgejo via the **batch contents endpoint** (`POST /repos/{owner}/{repo}/contents` with `ChangeFilesOptions{files: [{operation, path, content, sha}, ...], message, branch}`). The skill collapses sub-phases 5a, 5b, and 5c into a SINGLE atomic commit when possible — multiple file operations land as one commit, server-signed by `F09FD58E4737029E`.

The order matters logically:

- **5a — Port `.github/` artifacts to `.forgejo/`/repo-root.** Issue/PR templates, FUNDING, CODEOWNERS, CONTRIBUTING, SECURITY.
- **5b — Generate `.forgejo/workflows/quality.yaml` from justfile.** (formerly Phase 5; unchanged below.)
- **5c — Delete `.github/` entirely from forgejo.** Aggressive cleanup. Forgejo becomes a clean repo with NO `.github/` vestiges.

The aggressive 5c is intentional per the user's "fucking irrelevant about github" stance: forgejo is canonical. `.github/` only confuses forgejo users who would otherwise see CI workflows that never run there, dependabot configs that don't apply, etc. After 5c, forgejo's repo surface is `.forgejo/` + repo-root, with zero github-specific files.

Github keeps its `.github/` intact — the skill never writes to github. This means github keeps github-CI, github-templates, github-dependabot, etc. as-is.

### Sub-phase 5a — Port `.github/` artifacts

Walk the local clone's `.github/` tree (or, if no clone, GitHub via `gh api repos/.../contents/.github`). Classify each file:

| GitHub path | Forgejo destination | Class |
|---|---|---|
| `.github/ISSUE_TEMPLATE/*.{yaml,yml,md}` | `.forgejo/issue_template/<basename>` | known-portable, port 1:1 |
| `.github/pull_request_template.md` | `.forgejo/pull_request_template.md` | known-portable, port 1:1 |
| `.github/PULL_REQUEST_TEMPLATE/*.md` | `.forgejo/pull_request_template/<basename>` | known-portable, port 1:1 (multi-template) |
| `.github/FUNDING.yml` | `.forgejo/FUNDING.yml` | known-portable, port 1:1 |
| `.github/CODEOWNERS` | `.forgejo/CODEOWNERS` | known-portable, port 1:1 |
| `.github/CONTRIBUTING.md` | repo-root `CONTRIBUTING.md` | known-portable, port to root |
| `.github/SECURITY.md` | repo-root `SECURITY.md` | known-portable, port to root |
| `.github/DISCUSSION_TEMPLATE/*` | (drop) | Forgejo's API has no `has_discussions` field — Discussions feature isn't programmatically enableable on this instance. See AGENTS "Forgejo capability gaps". |
| `.github/dependabot.yml` | (drop) | Forgejo has no dependabot. Renovate is the alternative if needed; deploy separately. |
| `.github/release.yml` | (drop) | github-only release-notes config. Forgejo has its own release-creation flow. |
| `.github/workflows/*.yaml` (quality/test/format/lint) | (drop) | Covered by sub-phase 5b's generated `.forgejo/workflows/quality.yaml`. |
| `.github/workflows/*.yaml` (luarocks, automation_*, release_*, etc.) | (drop, FLAG in report) | Non-canonical CI requires per-workflow research before forgejo equivalent exists. Until then, github keeps these workflows; forgejo has none. Tracked separately from this skill — see AGENTS "Non-quality workflow port backlog". |
| anything else (e.g. `pre-commit`, `pre-push`, `scripts/`, `RELEASE_PROCESS.md`, `*.png` assets) | (drop, FLAG in report) | Unknown class; per-repo human review required. The skill does not auto-decide where these belong (root `hooks/`? `.git/hooks/`? `scripts/`?). |

When porting text templates, normalize Barrett-owned repository links for the
new host. A GitHub issue-template copied byte-for-byte often contains
`https://github.com/barrettruth/<repo>/issues`,
`https://github.com/barrettruth/<repo>/discussions`, or lazy.nvim examples like
`'barrettruth/<repo>'`. Those are wrong in Forgejo-facing templates. Rewrite
Barrett-owned links to `https://git.barrettruth.com/barrettruth/<repo>/...` or
full Forgejo plugin URLs. Preserve third-party upstream GitHub links.

### Concrete batch builder (5a + 5c combined)

The skill's reference implementation for Phase 5a (port) + Phase 5c (delete `.github/`) is a single Python script that:

1. Enumerates local `.github/` (or falls back to GitHub if no local clone).
2. Pulls Forgejo's current `.github/` tree (with blob shas, needed for the deletes).
3. Classifies each path against the table above.
4. Reads source content for `create`/`update` ops from the local clone.
5. Emits a JSON `ChangeFilesOptions` body to stdout, plus diagnostic counts and the `flagged_unknowns` list to stderr for the Phase 8 report.

Run it from the local clone's root (or with `--no-clone` to read sources from GitHub via `gh api`). The skill validated this implementation against `diffs.nvim`, `tmux-mosaic`, `http-codes.nvim`, `midnight.nvim`, and `blink-cmp-tmux` on 2026-04-30 — every backfill landed as a single signed commit.

```python
#!/usr/bin/env python3
# usage: build_phase5_batch.py <repo-name> > batch-payload.json
# stderr emits report fields: ports=N drops_no_eq=N drops_review=N flagged_unknowns=[...]

import base64, json, os, re, subprocess, sys

repo = sys.argv[1]
fj_owner = "barrettruth"
fj_path = f"/repos/{fj_owner}/{repo}"

# port whitelist: .github/<src> -> dst on forgejo
PORT_RULES = [
    (lambda p: p.startswith(".github/ISSUE_TEMPLATE/"),
       lambda p: f".forgejo/issue_template/{os.path.basename(p)}"),
    (lambda p: p == ".github/pull_request_template.md",
       lambda p: ".forgejo/pull_request_template.md"),
    (lambda p: p.startswith(".github/PULL_REQUEST_TEMPLATE/") and p.endswith(".md"),
       lambda p: f".forgejo/pull_request_template/{os.path.basename(p)}"),
    (lambda p: p == ".github/FUNDING.yml",
       lambda p: ".forgejo/FUNDING.yml"),
    (lambda p: p == ".github/CODEOWNERS",
       lambda p: ".forgejo/CODEOWNERS"),
    (lambda p: p == ".github/CONTRIBUTING.md",
       lambda p: "CONTRIBUTING.md"),
    (lambda p: p == ".github/SECURITY.md",
       lambda p: "SECURITY.md"),
]

# known-droppable (no forgejo equivalent or covered by 5b)
DROP_NO_FJ_EQ = [
    lambda p: p.startswith(".github/DISCUSSION_TEMPLATE/"),
    lambda p: p == ".github/dependabot.yml",
    lambda p: p == ".github/release.yml",
    # quality workflow covered by 5b's generated .forgejo/workflows/quality.yaml
    lambda p: p in (".github/workflows/quality.yaml", ".github/workflows/quality.yml",
                    ".github/workflows/format.yaml", ".github/workflows/format.yml",
                    ".github/workflows/lint.yaml", ".github/workflows/lint.yml",
                    ".github/workflows/test.yaml",  ".github/workflows/test.yml"),
]

# known-droppable but FLAG: non-quality workflows that need future per-workflow research
def is_non_quality_workflow(p):
    return p.startswith(".github/workflows/") and p.endswith((".yml", ".yaml")) and \
        not any(rule(p) for rule in DROP_NO_FJ_EQ)

def classify(path):
    for matches, dst_fn in PORT_RULES:
        if matches(path):
            return ("port", dst_fn(path))
    if any(rule(path) for rule in DROP_NO_FJ_EQ):
        return ("drop_no_eq", None)
    if is_non_quality_workflow(path):
        return ("drop_flag_workflow", None)
    return ("drop_flag_review", None)

def normalize_forgejo_text(path, raw):
    try:
        text = raw.decode()
    except UnicodeDecodeError:
        return raw
    if not (path.endswith((".md", ".yaml", ".yml", ".txt"))):
        return raw
    text = re.sub(
        rf"https://github\.com/{fj_owner}/([A-Za-z0-9._-]+)",
        rf"https://git.barrettruth.com/{fj_owner}/\1",
        text,
    )
    text = re.sub(
        rf"git@github\.com:{fj_owner}/([A-Za-z0-9._-]+)\.git",
        rf"ssh://git@git.barrettruth.com/{fj_owner}/\1.git",
        text,
    )
    text = re.sub(
        rf"(['\"`]){fj_owner}/([A-Za-z0-9._-]+)\1",
        rf"\1https://git.barrettruth.com/{fj_owner}/\2\1",
        text,
    )
    return text.encode()

# 1. enumerate local .github/ (preferred) or fall back to github
if os.path.isdir(".github"):
    local_files = []
    for root, _, names in os.walk(".github"):
        for n in names:
            local_files.append(os.path.join(root, n))
    local_files.sort()
else:
    out = subprocess.check_output(
        ["gh", "api", f"repos/{fj_owner}/{repo}/git/trees/HEAD?recursive=1",
         "--jq", '.tree[] | select(.type == "blob" and (.path | startswith(".github/"))) | .path'],
        text=True)
    local_files = sorted(out.strip().splitlines())

# 2. forgejo's current .github/ tree (with blob shas for the delete ops)
fj_tree = json.loads(subprocess.check_output(
    ["tea", "api", "-l", "vps", f"{fj_path}/git/trees/main?recursive=true"], text=True))
fj_dotgithub = {n["path"]: n["sha"] for n in fj_tree["tree"]
                if n["type"] == "blob" and n["path"].startswith(".github/")}

# 3. classify + build files[]
files = []
report = {"ports": [], "drops_no_eq": [], "drops_flag_workflow": [], "drops_flag_review": []}

# port phase: each portable local file
for src in local_files:
    cls, dst = classify(src)
    if cls == "port":
        with open(src, "rb") as f:
            content_b64 = base64.b64encode(normalize_forgejo_text(src, f.read())).decode()
        # check if dst already exists on forgejo (use "update" + sha)
        try:
            existing = json.loads(subprocess.check_output(
                ["tea", "api", "-l", "vps", f"{fj_path}/contents/{dst}"], text=True,
                stderr=subprocess.DEVNULL))
            op = "update"; entry = {"operation": op, "path": dst, "content": content_b64, "sha": existing["sha"]}
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError):
            op = "create"; entry = {"operation": op, "path": dst, "content": content_b64}
        files.append(entry)
        report["ports"].append(f"{src} -> {dst}")
    elif cls == "drop_no_eq":
        report["drops_no_eq"].append(src)
    elif cls == "drop_flag_workflow":
        report["drops_flag_workflow"].append(src)
    elif cls == "drop_flag_review":
        report["drops_flag_review"].append(src)

# delete phase: every file currently under .github/ on forgejo
for path, sha in sorted(fj_dotgithub.items()):
    files.append({"operation": "delete", "path": path, "sha": sha})

# 4. emit batch payload to stdout
payload = {
    "message": "ci(forgejo): port .github/ to .forgejo/ + drop .github/",
    "branch": "main",
    "files": files,
}
json.dump(payload, sys.stdout, indent=2)

# 5. emit report fields to stderr
print(f"\nports: {len(report['ports'])}", file=sys.stderr)
for p in report["ports"]: print(f"  + {p}", file=sys.stderr)
print(f"drops (no fj eq): {len(report['drops_no_eq'])}", file=sys.stderr)
for p in report["drops_no_eq"]: print(f"  - {p}", file=sys.stderr)
print(f"drops (FLAG: non-quality workflow): {len(report['drops_flag_workflow'])}", file=sys.stderr)
for p in report["drops_flag_workflow"]: print(f"  - {p} (see AGENTS 'Non-quality workflow port backlog')", file=sys.stderr)
print(f"drops (FLAG: manual review): {len(report['drops_flag_review'])}", file=sys.stderr)
for p in report["drops_flag_review"]: print(f"  - {p} (skill cannot auto-decide destination)", file=sys.stderr)
print(f"deletes from .github/: {len(fj_dotgithub)}", file=sys.stderr)
```

Save this as `~/.config/devin/skills/github-to-forgejo/build_phase5_batch.py`. Each backfill / new run invokes it like:

```
cd ~/dev/<name>
python3 ~/.config/devin/skills/github-to-forgejo/build_phase5_batch.py <name> > /tmp/<name>/batch-payload.json 2>/tmp/<name>/batch-report.txt
tea api -l vps -X POST "/repos/barrettruth/<name>/contents" -d @/tmp/<name>/batch-payload.json | jq '{commit_sha: .commit.sha, verified: .verification.verified, signer: .verification.reason}'
cat /tmp/<name>/batch-report.txt   # source for Phase 8 report fields
```

The script reads from local `.github/` for source content (so it picks up any local edits the user has made vs. what's on github), but enumerates forgejo's `.github/` separately for the deletes (since forgejo's tree may diverge from local — e.g., if a previous batch already partially-cleaned).

If 5b is also writing a workflow file, append the `.forgejo/workflows/quality.yaml` create/update entry to the same `files` array before POSTing — single atomic commit covering 5a + 5b + 5c.

### Sub-phase 5b — `.forgejo/workflows/quality.yaml`

(Content unchanged from Phase 5 in v4.x. Detect just recipes from forgejo's `justfile`, build the workflow YAML, add to the same batch ChangeFilesOptions payload as 5a.)

Detect just recipes by reading `<name>/justfile` from Forgejo via API (NOT the local clone — keeps this phase functional even without a clone):

```
tea api -l vps "/repos/barrettruth/<name>/contents/justfile" 2>/dev/null \
  | jq -r '.content // empty' \
  | base64 -d \
  | grep -Eo '^(format|lint|test)( [a-z-]+)?:' \
  | cut -d: -f1 \
  | cut -d' ' -f1 \
  | sort -u
```

If NONE detected, skip phase 5 entirely (note in report).

### Sub-step 5.0a — GitHub-CI-gap detection (when Phase 5 skips)

Before skipping silently, check whether GitHub has CI for this repo. If it does, the user almost certainly cares about CI on Forgejo too, and a silent skip is misleading.

```
fj_workflow_count=$(tea api -l vps "/repos/barrettruth/<name>/contents/.forgejo/workflows" 2>/dev/null \
  | jq 'if type=="array" then [.[] | select(.name | endswith(".yaml") or endswith(".yml"))] | length else 0 end')
gh_workflow_count=$(gh api "repos/barrettruth/<name>/actions/workflows" --jq '.total_count // 0')
```

If `gh_workflow_count > 0` AND Phase 5 is about to skip (no justfile recipes detected), surface this in the Phase 8 report as `forgejo workflow: SKIPPED (no justfile recipes; github has <N> workflows — see "Non-canonical CI" below)` instead of the bare `SKIPPED`. Do NOT auto-port; just flag.

The skill's recommended remediation for this state is **option A: add a justfile + `.#ci` devShell** (NOT verbatim-port from `.github/workflows/`). Rationale:

- Justfile-as-source-of-truth keeps the per-repo `quality.yaml` generated by Phase 5 instead of hand-maintained in two places.
- `.#ci` devShell makes the same `nix develop .#ci --command just <recipe>` runnable locally, in github CI (if the user keeps github CI), and in forgejo CI.
- Verbatim-port of `.github/workflows/` would carry over `runs-on: ubuntu-latest`/`runs-on: nix`, third-party actions of unknown forgejo `act` compatibility, paths-filter logic, and matrix expansions that aren't in the canonical baseline. This skill does NOT auto-port github workflows — that's a separate, opt-in operation outside the canonical flow.

Pattern for adding a justfile + `.#ci` to a repo that has direct `nix develop --command <tool>` invocations in `.github/workflows/`:

**Canonical rule for tool scope: let the tool's config drive what gets checked, not the command line.**

- `biome format` → use `biome format .` (lets `biome.json`'s `formatter.includes` / `useIgnoreFile` drive scope), NOT `biome format <file1> <file2>` (cmdline shortcut from github workflows that bypasses biome.json).
- `stylua --check` → use `stylua --check .` (lets `stylua.toml` drive scope), NOT a hand-picked file list.
- `selene` → use `git ls-files '*.lua' | xargs selene ...` (`selene.toml` + ignore-file driven), NOT a directory walk that re-implements ignore logic.
- `shfmt` → use `shfmt -i 2 -d <explicit-paths>` for shell repos where shell files live in known dirs (e.g. `mosaic.tmux scripts tests`); shfmt has no project config file analog.

**Canonical rule for the formatter itself: biome ONLY, never prettier.**

- Prettier is forbidden in this project's repos. Do NOT introduce `.prettierrc`, `.prettierrc.{json,yaml,yml,js,cjs,mjs}`, `prettier.config.*`, `.prettierignore`, or `prettier` invocations in justfiles or workflows.
- If a repo lands on prettier (legacy or imported from upstream), the migration target is biome with an equivalent configuration:
  - `proseWrap: "always"` → biome doesn't have a direct equivalent; biome's markdown formatter follows the configured `lineWidth` and respects markdown semantics. Use `lineWidth` to approximate.
  - `printWidth` → `formatter.lineWidth`
  - `tabWidth` → `formatter.indentWidth`
  - `useTabs: false` → `formatter.indentStyle: "space"`
  - `trailingComma: "none"` → `javascript.formatter.trailingCommas: "none"`
  - `semi: false` → `javascript.formatter.semicolons: "asNeeded"`
  - `singleQuote: true` → `javascript.formatter.quoteStyle: "single"`
- Always set `vcs: { enabled: true, clientKind: "git", useIgnoreFile: true }` and `files: { ignoreUnknown: false }` on `biome.json` so `biome format .` respects `.gitignore` and only formats file types biome understands.
- Always set `formatter.includes: ["**", "!**/node_modules/"]` so the includes pattern is explicit. Add other paths to the negation list as needed (e.g., `"!**/.direnv/"` if `.direnv` isn't in `.gitignore`).
- The justfile recipe should call `biome format .`, never `prettier --check .`.

Known prettier-using repos in the corpus (audited 2026-05-01): `canola.nvim` only. All 23 other public repos are prettier-free. Migration of `canola.nvim` is deferred until the skill is run on it (or a separate cleanup pass is requested).

Github workflows often use cmdline-args-as-scope as a perf shortcut on push events (dorny/paths-filter and explicit file lists). Do not propagate that shortcut into the canonical justfile — the justfile's `format`/`lint`/`test` recipes should mean "check everything the tool is configured for". If a contributor wants a faster local check, they can use the tool's CLI directly with whatever scope they want.

Steps:

1. Read the existing `.github/workflows/quality.yaml` (or equivalent) to enumerate the actual commands. Map each `nix develop --command <tool> <args>` line into a `just <recipe>` body.
2. Group commands into the canonical `format` / `lint` / `test` recipes per the user's separation of concerns. If the github workflow has a separate `quality.yaml` and `test.yaml`, the natural mapping is `quality → format + lint`, `test → test`.
3. Edit `flake.nix` to extract the existing `default` devShell's packages into a `commonPackages` let-binding, then add a `ci = pkgs.mkShell { packages = commonPackages ++ [ pkgs.neovim ]; }` if `busted`/`nvim`-based tests need a real `nvim` (most lua plugins do). If the existing `default` already has everything, `ci` can equal `default`.
4. Verify each recipe runs locally inside the new `.#ci`: `nix develop .#ci --command just format && nix develop .#ci --command just lint && nix develop .#ci --command just test`. ALL three must pass before pushing.
5. Commit signed and push to forgejo (this skill's pre-flight + Phase 4 pattern handles it).
6. Re-run `github-to-forgejo` from the start. Phase 5 now picks up the justfile and writes `.forgejo/workflows/quality.yaml`. Phase 6's `status_check_contexts` is whatever Phase 5's per-recipe detection produced.

If the github workflow has logic that genuinely doesn't fit the justfile pattern (e.g. matrix-strategy testing across multiple nvim versions, third-party actions like `nvim-busted-action`, paths-filter to skip jobs based on file changes), there's a tradeoff: either drop those features when porting (matrix → single version, third-party actions → just shell out, paths-filter → always run), or accept that this repo can't have canonical forgejo CI and document why in the per-repo override table.

Detect `.#ci` flake shell from Forgejo's `flake.nix`:

```
tea api -l vps "/repos/barrettruth/<name>/contents/flake.nix" 2>/dev/null \
  | jq -r '.content // empty' \
  | base64 -d \
  | grep -Eq '(^|[[:space:].])ci[[:space:]]*=[[:space:]]*pkgs\.mkShell|devShells\.[^.]+\.ci\b' \
  && echo has-ci
```

If `flake.nix` is missing OR doesn't expose a `.#ci` shell, the workflow falls back to running `just <recipe>` directly without `nix develop`.

Build the workflow YAML in-memory with ONLY the detected jobs:

```yaml
name: quality

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  format:
    name: Format
    runs-on: nix
    steps:
      - uses: actions/checkout@v4
      - name: Format
        run: nix develop .#ci --command just format
  lint:
    name: Lint
    runs-on: nix
    steps:
      - uses: actions/checkout@v4
      - name: Lint
        run: nix develop .#ci --command just lint
  test:
    name: Test
    runs-on: nix
    steps:
      - uses: actions/checkout@v4
      - name: Test
        run: nix develop .#ci --command just test
```

Drop any jobs whose recipe wasn't detected. The Job `name:` (e.g. `Format`) is what becomes the status check context name — keep these capitalized to match Phase 6.

If `.#ci` detection said "no", strip `nix develop .#ci --command ` from each `run:` line.

### Write the file via Forgejo API

Check if `.forgejo/workflows/quality.yaml` already exists on Forgejo:

```
existing=$(tea api -l vps "/repos/barrettruth/<name>/contents/.forgejo/workflows/quality.yaml" 2>/dev/null)
sha=$(echo "$existing" | jq -r '.sha // empty')
existing_content=$(echo "$existing" | jq -r '.content // empty' | base64 -d 2>/dev/null)
```

- If existing content matches the to-be-written content byte-for-byte → no action.
- If the file does NOT exist (no `sha`): `POST /repos/barrettruth/<name>/contents/.forgejo/workflows/quality.yaml` with body:
  ```json
  {
    "message": "ci(forgejo): add quality workflow",
    "content": "<base64 of yaml>",
    "branch": "main"
  }
  ```
- If the file exists with a different content (`sha` present): `PUT /repos/barrettruth/<name>/contents/.forgejo/workflows/quality.yaml` with the SAME body PLUS `"sha": "<existing sha>"`. PUT without a `sha` returns `[SHA]: Required` and fails. POST is for create only and rejects when the file already exists.

The commit will be server-signed by `F09FD58E4737029E` (CRUD_ACTIONS = always). The branch protection on `main` MUST already be deleted (handled in pre-flight + Phase 0; re-created in Phase 6).

The skill does NOT write the workflow file to the local clone. It does NOT push to forgejo via git. It does NOT open a GitHub PR.

Phase 4 ran BEFORE Phase 5, so by the time this commit lands on forgejo, forgejo's `main` has already been reconciled with `origin/main`. The workflow commit ends up as the only forgejo-unique commit ahead of origin/main until the next GitHub PR merge.

### Sub-phase 5c — Delete `.github/` entirely from forgejo

After 5a has captured everything portable from `.github/` and 5b has generated the canonical workflow, the entire `.github/` tree on forgejo becomes redundant. Delete it.

**EXCEPTION — spec/test fixture protection.** Some repos use `.github/` files as TEST FIXTURES (forge.nvim's `spec/yaml_spec.lua` reads `.github/ISSUE_TEMPLATE/bug_report.yaml` as an example template to parse, since the plugin's job IS parsing github-style issue templates). Deleting these breaks the test suite. Before queuing the 5c deletes, grep the local clone's spec/test directories for `.github/` path references:

```
git grep -nE "\.github/(ISSUE_TEMPLATE|DISCUSSION_TEMPLATE|workflows|pull_request_template)" spec/ test/ tests/ 2>/dev/null
```

If any matches reference the file as a fixture (path-relative load via `vim.uv.fs_open`/`fs.readFile`/etc.), DO NOT delete that file in 5c. Keep it on forgejo as a fixture. Note in the per-repo override row that both `.github/<file>` (test fixture) and `.forgejo/<file>` (canonical) coexist deliberately.

Discovered via forge.nvim 2026-05-01 Phase 7 first-attempt RED — `spec/yaml_spec.lua` and `spec/template_spec.lua` opened `.github/ISSUE_TEMPLATE/*.yaml` and `.github/pull_request_template.md` directly. Restoring them as a separate batch commit (`2dbc895b`) recovered green CI.

Iterate every file under `.github/` on forgejo's `main` and add a `delete` operation for each to the same batch payload:

```
gh_tree=$(tea api -l vps "/repos/barrettruth/<name>/git/trees/main?recursive=true")
mapfile -t fj_dotgithub_files < <(
  echo "$gh_tree" \
    | jq -r '.tree[] | select(.type == "blob" and (.path | startswith(".github/"))) | .path'
)

for path in "${fj_dotgithub_files[@]}"; do
  blob_sha=$(echo "$gh_tree" | jq -r --arg p "$path" '.tree[] | select(.path == $p) | .sha')
  files_payload=$(jq --argjson c "$files_payload" \
    --arg op "delete" --arg path "$path" --arg sha "$blob_sha" \
    '$c + [{operation: $op, path: $path, sha: $sha}]' \
    < /dev/null)
done
```

Forgejo's batch contents endpoint accepts `operation: "delete"` entries with `path` and `sha` (the blob sha, not commit sha; sourced from the recursive tree listing).

### POST the batch (5a + 5b + 5c in one commit)

```
jq -n --argjson f "$files_payload" --arg msg "ci(forgejo): port .github/ to .forgejo/, generate quality workflow, drop .github/" '{
  files: $f,
  message: $msg,
  branch: "main"
}' | tea api -l vps -X POST "/repos/barrettruth/<name>/contents" -d @-
```

The single commit:

- creates `.forgejo/issue_template/*`, `.forgejo/pull_request_template.md`, etc. (5a)
- creates/updates `.forgejo/workflows/quality.yaml` (5b)
- deletes every `.github/*` file (5c)

All as one atomic commit, server-signed by `F09FD58E4737029E`.

### Multi-branch port pattern (when a repo has multiple branches that need the same canonical state)

Some repos have more than one canonical-state branch (e.g. `canola.nvim` has `main` = v1.0 frozen drop-in oil.nvim replacement AND `canola` = v1.1+ active development per its CLAUDE.md two-track architecture). When the user explicitly asks for "both branches must be ported", the skill runs Phase 5 once per branch, each producing its own atomic batch commit. Key adaptations vs single-branch:

1. **Source-content reading is per-branch.** The local clone has only one branch checked out at a time; reading `.github/<file>` from the local working tree gives that ONE branch's content. For multi-branch port, source content for each branch's `.github/*` ports must come from forgejo's tree at `?ref=<branch>` via the contents API, NOT from the local clone. (Different branches commonly diverge on `.github/ISSUE_TEMPLATE/*` — e.g. canola.nvim's main has `bug_report_canola.yaml` + `feature_request_canola.yaml` variants that don't exist on canola branch.)

2. **Workflow YAML's `on.{push,pull_request}.branches:` filter must match the branch.** Forgejo Actions runs the workflow file FROM the branch being pushed. If the workflow on `canola` says `on.push.branches: [main]`, push to canola won't trigger CI. Generate ONE workflow file per branch with the matching filter:
   - main's workflow: `on: { push: { branches: [main] }, pull_request: { branches: [main] } }`
   - canola's workflow: `on: { push: { branches: [canola] }, pull_request: { branches: [canola] } }`

3. **Per-branch ChangeFilesOptions batch.** Each batch sets `branch: "<name>"` in its body. Run them sequentially (POST main first, wait for CI, then POST canola, wait for CI) so each branch's CI runs against its own batch commit independently. Don't combine into a single batch — `ChangeFilesOptions` has only one `branch` field.

4. **File classification differs per branch.**
   - **Common files (biome.json, justfile, flake.nix, LICENSE)**: same source content, but `operation` is `create` vs `update` per-branch based on whether that branch already has the file. Example from canola.nvim: justfile is `create` on main (main doesn't have one in its frozen v1.0 structure) but `update` on canola (canola already has one with prettier).
   - **Per-branch `.github/*` lists**: enumerate each branch's tree separately (`git/trees/{branch}?recursive=true`); blob shas for delete ops differ per branch.

5. **Phase 6 protection per branch.** Each branch gets its own protection rule via `POST /branch_protections` with `branch_name: "<name>"` and `rule_name: "<name>"`. Same canonical schema. If a branch's CI is currently failing (e.g. canola.nvim's main on the `oil.txt` vimdoc-LS issue), apply protection anyway with the full required-checks list — future PRs to that branch will need to fix the failures, which is correct gating behavior.

6. **CI failure handling**: poll each branch's commit status independently. A failure on one branch doesn't block proceeding on the other (if they're being processed sequentially).

7. **Local clone is on `main` for the duration**, with the original branch saved/restored in Phase 8. The per-branch source content for `.github/*` ports comes from the API, so no per-branch checkout needed. Avoid `git checkout` mid-run unless the local clone's untracked files have been fully accounted for — leftover untracked files (e.g. validation files I `cp`'d during testing) will block checkout with "would be overwritten by checkout".

8. **Same `originalBranch` restore**: at Phase 8, checkout `originalBranch` (whatever branch the user was on at pre-flight). Pop the pre-flight stash. The user's working state is unaffected by the multi-branch operations on forgejo.

This pattern's reference implementation is `build_canola_batch.py` (one-off for canola.nvim, kept under `/tmp/canola.nvim/build_canola_batch.py` during the run; not generalized into the skill's standard tooling because most repos are single-branch). Future multi-branch repos can adapt the canola.nvim script directly.

### Phase 8 report fields

Each sub-phase contributes:

- `port` line: count of files ported via 5a, with their forgejo destinations
- `workflow` line: same as before (added/unchanged/skipped)
- `dropped from .github/ (manual review needed)` line: list of `flagged_unknowns` files that the user must decide on (where do `pre-commit`, `scripts/upstream_digest.py`, etc. belong?)
- `dropped from .github/ (no forgejo equivalent)` line: list of files dropped per the known-droppable rules (DISCUSSION_TEMPLATE, dependabot.yml, release.yml, non-quality workflows). Includes a sub-flag for non-quality workflows that need future research per "Non-quality workflow port backlog".

## Phase 6 — Branch protection (ruleset) on `main`

This is the LAST mutating phase. Pre-flight (and Phase 0 if it ran) already DELETED any pre-existing protection rule, so this phase always uses `POST /repos/barrettruth/<name>/branch_protections` to create the canonical schema fresh. PATCH is not used here — the v3 skill suggested PATCH-when-pre-existing, but combined with pre-flight's unconditional DELETE, the correct verb is always POST:

```json
{
  "branch_name": "main",
  "rule_name": "main",
  "enable_push": false,
  "enable_status_check": true,
  "status_check_contexts": ["quality / Format (pull_request)", "quality / Lint (pull_request)", "quality / Test (pull_request)"],
  "required_approvals": 1,
  "block_on_rejected_reviews": true,
  "block_on_official_review_requests": true,
  "block_on_outdated_branch": true,
  "dismiss_stale_approvals": true,
  "ignore_stale_approvals": true,
  "require_signed_commits": true,
  "apply_to_admins": false
}
```

**Critical: `status_check_contexts` must use exact-match strings of the form `<workflow-name> / <job-display-name> (<event>)`.** Forgejo's protection rule does literal-match against context strings (NOT pattern/glob/substring). The contexts that actually appear on PRs are emitted by Forgejo Actions as `<workflow-name> / <job.name> (pull_request)` — for the canonical Phase 5b workflow (named `quality`) with jobs `Format`/`Lint`/`Test`, these are exactly:

- `quality / Format (pull_request)`
- `quality / Lint (pull_request)`
- `quality / Test (pull_request)`

A bare-name list like `["Format","Lint","Test"]` does NOT match and produces the merge-blocking error `not allowed to merge [reason: Not all required status checks successful]` even when all checks ARE green. **This was a systemic bug in skills v5.0 through v5.0.x that affected the first 8 repos processed; all of them needed a corrective sweep on 2026-05-01 to update their `status_check_contexts`. Skill v5.1+ uses the corrected pattern from the start.**

For repos with different workflow names or different jobs, derive the context strings from the actual workflow file. If the workflow is named `ci`, the contexts become `ci / Format (pull_request)` etc. If a job has `name: Lua Format Check`, the context is `<workflow> / Lua Format Check (pull_request)` (job display name is what's shown, not the YAML key).

`(pull_request)` is the event suffix for PR-targeted CI runs — this is what gates merges. The same workflow also emits `(push)` contexts when the merge commit lands on `main`, but `enable_push=false` blocks direct pushes so the `(push)` contexts don't need to be in the protection list.

`status_check_contexts` MUST be filtered to only the contexts whose corresponding job exists in the workflow file the skill just wrote (or detected as already-present). If the workflow was skipped entirely in Phase 5, `status_check_contexts: []` and the protection rule still applies (no required checks).

For repos with a `build` recipe (e.g. Astro/Node sites: `philipmruth.com`, possibly `barrettruth.com`, `live-server.nvim`), include `quality / Build (pull_request)` in the list to gate on build success too. The skill's `build_phase5_batch.py` doesn't currently auto-detect a `build` recipe (only `format`/`lint`/`test`); for those repos, the workflow YAML and protection contexts both need manual adjustment.

`apply_to_admins=false` is intentional: avoids the self-approval deadlock when the admin (you) ships solo green PRs. See `~/.config/nix/AGENTS.md`'s "Forgejo repo-wide follow-ups" note about not deadlocking solo-author PRs.

## Phase 7 — Wait for Forgejo Actions CI

If Phase 5 wrote a workflow file (new or updated), the commit will trigger a Forgejo Actions run.

Poll for completion:

```
commit_sha=$(tea api -l vps "/repos/barrettruth/<name>/commits?limit=1" | jq -r '.[0].sha')
while true; do
  status=$(tea api -l vps "/repos/barrettruth/<name>/commits/$commit_sha/status" | jq -r '.state')
  case "$status" in
    success) break ;;
    failure|error) echo "CI failed"; break ;;
    pending|"") sleep 10 ;;
  esac
done
```

Block until all checks complete. If any fail, STOP and report (no auto-rebase, no auto-fix).

If Phase 5 was skipped (no workflow change), this phase is a no-op.

## Phase 8 — Report and restore

Restore the user's working state FIRST, in this order:

1. **Restore originalBranch.** Pre-flight saved `originalBranch`; if the local clone exists and `originalBranch != main`:

   ```
   git checkout "$originalBranch"
   ```

2. **Pop the pre-flight stash.** If pre-flight step 4b set `stashed=true`, find the stash by its labeled marker and pop it. Search by message rather than `stash@{0}` so the right entry is popped even if other stashes appeared during the run:

   ```
   stash_marker_regex='github-to-forgejo skill v[^ ]+ pre-flight stash'
   stash_idx=$(git stash list --format='%gd %gs' | grep -m1 -E "$stash_marker_regex" | awk '{print $1}')
   if [ -n "$stash_idx" ]; then
     if ! git stash pop "$stash_idx" 2>&1; then
       echo "WARNING: stash pop conflicted; the stash is preserved at $stash_idx"
       echo "Resolve manually with: git stash show -p $stash_idx; git stash pop $stash_idx"
       stash_pop_status="conflict (preserved at $stash_idx)"
     else
       stash_pop_status="popped cleanly"
     fi
   else
     stash_pop_status="n/a (nothing was stashed)"
   fi
   ```

   If the pop conflicts, do NOT abort — just leave the stash in place and surface the warning in the Phase 8 report. The user's pre-existing in-progress diff is more valuable than a clean working tree, so we'd rather fail loudly than blast their work.

This leaves the user's working clone as close to their entry state as possible. The remote/branch-tracking changes from pre-flight step 4a are kept (those were the right state going forward per `~/dev/CLAUDE.md`'s remote policy); only the dirty diff and current branch are rolled back.

Then print a structured summary:

```
repo:                <name>
migration:           complete (gh issues=<N> pulls=<N> labels=<N> milestones=<N> releases=<N>; fj matches) |
                     remigrated (deleted+recloned with all data flags; LICENSE re-applied as <sha>) |
                     pulls undermigrated by <pct>% (kept; below remigrate threshold)
clone auto-repair:   none (clone already canonical) |
                     remote-renamed (origin->forgejo, github added as new origin; <N> branches retracked to forgejo: <list>) |
                     local-main reset (dropped <sha> stale forgejo-only commit; GPL blob saved to /tmp/<name>/LICENSE.gpl.b64) |
                     n/a (no clone)
forgejo remote:      added | already present | n/a (no clone)
local branches:      main = <sha> (origin/main); forgejo = <sha> (forgejo/main) | n/a (no clone)
restored branch:     <originalBranch> | n/a (was already on main) | n/a (no clone)
restored stash:      popped cleanly | conflict (preserved at <stash_idx>) | n/a (nothing was stashed) | n/a (no clone)
metadata patched:    <list of fields that changed>
topics:              applied (<count> tags) | already populated (<count> tags) | empty (no override)
license:             ok (GPL)
reconcile:           no-op | fast-forwarded (<N> commits from origin) | rebased (<N> forgejo-unique commits replayed; SHAs changed: <list of old->new>) | forgejo ahead-only (<N> commits) | conflict (aborted)
backfill:            forgejo heatmap contributions: <before> -> <after> | skipped (no clone) | n/a (no push performed)
github port:         <N> files ported (<list of fj destinations>) | none (no .github/ on this repo) | n/a (no clone or no .github/)
forgejo workflow:    added (jobs: <list>, commit <sha>) | unchanged | skipped (no justfile recipes)
github cleanup:      <N> files deleted from forgejo .github/ | already empty | n/a
dropped (no fj eq):  <list of files: DISCUSSION_TEMPLATE/*, dependabot.yml, release.yml, non-quality workflows>
dropped (review):    <list of files needing manual decision: pre-commit, scripts/*, etc.> | none
ruleset:             applied (POST after pre-flight DELETE); required checks = <list>;
                     apply_to_admins=false; require_signed_commits=true
forgejo CI:          passed | failed (<list of failed checks>) | n/a (no workflow change)
```

`clone auto-repair` may report multiple actions on the same line (semicolon-separated) if more than one applied — e.g. both a remote rename AND a local-main reset.

`dropped (review)` is a HARD-STOP signal for the user: each file listed there needs a decision about where it should live going forward (root `hooks/`? husky? lefthook? `scripts/`? `.git/hooks/` per-clone?). The skill doesn't choose. Future skill runs will keep dropping them until the user moves them to a non-`.github/` location on github (which then flows to forgejo via Phase 4).

STOP. Do not push to forgejo a second time. Do not touch other repos. Do not touch GitHub.

## Canonical baseline (frozen 2026-04-30)

Source of truth is the live `barrettruth/tmux-mosaic` Forgejo state. If the baseline drifts, refresh the values in this skill from:

```
tea api -l vps /repos/barrettruth/tmux-mosaic
tea api -l vps /repos/barrettruth/tmux-mosaic/branch_protections/main
```

### Repo settings (tmux-mosaic, frozen)

```
description:                          'pane tiling layouts for tmux'  (per-repo)
website:                              ''                              (per-repo)
private:                              false
archived:                             false
has_wiki:                             false
has_projects:                         false
has_releases:                         true   (default; not changed by skill)
has_actions:                          true   (default; not changed by skill)
default_branch:                       main
allow_merge_commits:                  false
allow_rebase:                         true
allow_squash_merge:                   true
allow_rebase_explicit:                true
allow_fast_forward_only_merge:        false
default_merge_style:                  squash
default_delete_branch_after_merge:    true
```

### Branch protection (tmux-mosaic main, frozen)

```
branch_name:                main
enable_push:                false
enable_push_whitelist:      false
enable_merge_whitelist:     false
enable_status_check:        true
status_check_contexts:      ["quality / Format (pull_request)", "quality / Lint (pull_request)", "quality / Test (pull_request)"]   (filtered to detected recipes; see Phase 6 for derivation rule)
required_approvals:         1
block_on_rejected_reviews:  true
block_on_official_review_requests: true
block_on_outdated_branch:   true
dismiss_stale_approvals:    true
ignore_stale_approvals:     true
require_signed_commits:     true
apply_to_admins:            false
```

### Forgejo capability gaps vs GitHub rulesets

These GitHub rule attributes have NO Forgejo equivalent (per `~/.config/nix/AGENTS.md` "Verified Forgejo capability notes"); the skill cannot mirror them and shouldn't pretend to:

- `require_last_push_approval`
- `required_review_thread_resolution`
- `required_signatures` (handled at repo level via `require_signed_commits`)
- GitHub's bypass-actor mechanism (Forgejo uses `apply_to_admins=false` for similar effect)

Forgejo also doesn't expose `allow_auto_merge` as a repo setting; auto-merge IS available as a UI/PR action but isn't a per-repo toggle.

## Per-repo overrides

Verified on 2026-04-30. Skill calls these out before Phase 1 if any apply, then proceeds with the relevant adjustments.

Hard-skip (out of scope):

| Repo | Action | Reason |
|------|--------|--------|
| Anything with `private=true` on Forgejo | ABORT | Forgejo private repo policy. Includes `uvm-bench` as of 2026-04-30. |

Repos with no local clone — Phase 1 + Phase 4 skipped, all other phases run via API:

| Repo | Notes |
|------|-------|
| `barrettruth.github.io` | Skill v5.1 backfilled 2026-05-01: legacy github-pages redirect site (4 files: `.gitignore`, `README.md`, `index.css`, `index.html`). 0 issues + 0 PRs + 0 labels matched between forgejo and github — **Phase 0 SKIPPED** (no remigrate needed). LICENSE already GPL pre-skill (sha `f288702d` matches canonical). Topics intentionally empty per AGENTS "topics backfill" note (left blank because the page is a legacy redirect). Phase 5 SKIPPED (nothing to port). Phase 6 protection has `enable_status_check: false` and empty contexts. Description left empty (matches github). |
| `nix` | Skill v5.1 backfilled 2026-05-01: lives at `~/.config/nix` (not `~/dev/nix`). Active session repo (devin skill files at `~/.config/devin/skills/` are symlinked to `~/.config/nix/config/devin/skills/`). Phase 0 remigrated 6 issues + 9 PRs + 9 labels. LICENSE already GPL on both sides (no PUT needed). Phase 5 batch `2ae60e54` (1 create + 1 delete = 2 ops): port quality.yaml. Local main retracked from `forgejo/main` → `origin/main` per AGENTS canonical-host policy. **Phase 7 first attempt RED on Format+Lint** with 3 underlying issues — surfaced by spark runner being aarch64-linux while flake's `systems = [ "x86_64-linux" ]` was x86_64-only. **Inline-fix sequence**: (1) commit `eb09ceac` — added aarch64-linux to systems list (single-line edit, formatter wanted multi-line; failed Format check). (2) commit `f3eda76c` — re-formatted flake.nix to multi-line systems list per `nix fmt`, removed pre-existing statix W08 useless-parens at `pkgs/forgejo-cm6-langs/default.nix:154` (`overrideModAttrs = (_: {…});` → `overrideModAttrs = _: {…};`), and ran `stylua` on `config/nvim/plugin/completion.lua` to wrap long lines per stylua version skew. Phase 7 RE-poll: both Format+Lint green. **CRITICAL FINDING — `git stash -u` foot-gun**: don't `git stash -u` in `~/.config/nix` because `~/.config/nix/config/devin/skills/<name>/` is the source of truth for the active devin skill — `-u` will stash the entire skill directory mid-run, breaking the skill's own execution. Workaround: `git stash` (without `-u`) so untracked files stay in-place. Documented at "Forgejo skill caveats" below. |
| `whitepapers` | Skill v5.1 backfilled 2026-05-01: content-only repo (12 files: `notes.md`, `readme.md`, `papers/` subtree). 0 issues + 0 PRs + 0 labels matched between forgejo and github — **Phase 0 SKIPPED**. LICENSE already GPL on forgejo (sha `f288702d` matches canonical); github has no LICENSE (intentional drift, ack'd in AGENTS LICENSE-pass note). Topics already canonical (`papers,research,whitepapers`). Description empty on both sides — left empty. Phase 5 SKIPPED (no `.github/` directory anywhere). Phase 6 protection has `enable_status_check: false` (no CI to require). |

Repos with no `justfile` (Phase 5 skipped, `status_check_contexts: []` in Phase 6):

| Repo | Notes |
|------|-------|
| `blink-cmp-ssh` | Skill v5.1 backfilled 2026-05-01: **add-justfile remediation applied** (mirrors blink-cmp-tmux pattern). github CI was non-canonical (paths-filter + per-language conditional jobs); forgejo CI now uses canonical Format+Lint+Test via just-recipe wrappers. Templates copied from blink-cmp-tmux: justfile (format=stylua+biome / lint=selene+lua-LS / test=busted) + flake.nix devShells.{default,ci} (ci adds `pkgs.neovim`). Pre-existing real test setup (`spec/ssh_spec.lua` + `.busted` config using `nvim -l`) ran clean. **Clone auto-repair**: local was missing `forgejo` remote; skill added it. Phase 0 remigrated 2 issues + 5 PRs + 9 labels. LICENSE switched MIT→GPL via PUT (commit `e37cb2db`). Phase 5 batch `a162cf58` (1 create-justfile + 1 update-flake + 5 create-forgejo + 8 delete = 15 ops, the most complex single batch yet). All 3 jobs green on first poll. |
| `cp` | Skill v5.1 backfilled 2026-05-01: **competitive-programming notebook** (per-platform directory tree: `algorithms/`, `atcoder/`, `codeforces/`, `cses/`, `kattis/`, `usaco/` with `.cc` source + `.in`/`.out` test fixtures). No flake, no justfile, no `.github/` directory either side — purely a personal CP notebook. **No add-justfile remediation applied** (would be ceremonial — there's no shared toolchain to unify). **Clone auto-repair**: local was missing `forgejo` remote; skill added it. Active local WIP detected (codeforces/1076/{a,b,c,d}.cc with `.in`/`.out` fixtures); stashed with `-u` for untracked, restored cleanly post-Phase-8. Phase 0 remigrated 1 issue + 0 PRs + 9 labels. Description applied (was empty on both sides — chose "competitive programming notebook"). LICENSE applied via POST (commit `dec4edfc`) since github has no LICENSE either. Phase 5 SKIPPED (nothing to port or delete). Phase 6 protection has `enable_status_check: false` and `status_check_contexts: []` (sioyek-dev pattern). |
| `sioyek-dev` | Skill v5.1 backfilled 2026-05-01: **AUR package repo** — only contains `PKGBUILD` + `README.md` (no source code, no tests). Standalone, NOT a sioyek upstream fork (the earlier "fork" topic is misleading; the README clarifies it's a packaging repo for sioyek that "just works" on Arch). github had ONE workflow `.github/workflows/aur.yml` that pushes to AUR via `secrets.AUR_SSH_KEY` — github-only, no forgejo equivalent. **No add-justfile remediation applied** because there's no code to lint/format/test; would just be ceremonial. Phase 0 remigrated 0 issues + 3 PRs + 9 labels. LICENSE applied via POST (commit `292fcf6f`) since github has no LICENSE either. Phase 5 batch `2f83e2d5` (0 create + 1 delete = 1 op, smallest possible non-empty batch): drop `.github/workflows/aur.yml`. Phase 6 protection has `enable_status_check: false` and empty `status_check_contexts: []` — no CI on forgejo means no contexts to require. |

Repos that USED to have no justfile but now do (skill processed them via the sub-step 5.0a add-justfile remediation, recorded here for posterity):

| Repo | Notes |
|------|-------|
| `blink-cmp-tmux` | Justfile + `.#ci` added 2026-04-30 (commit `e7a6001`); now standard path. Recipes: `format` (stylua + `biome format .`), `lint` (selene + lua-language-server), `test` (busted). Status check contexts on forgejo: `["Format","Lint","Test"]`. Skill v5.0 backfilled 2026-04-30: `.github/` ported+deleted in batch commit `b5fdbb5` (4 ports + 8 deletes incl. DISCUSSION_TEMPLATE/q-a.yaml, 3 workflows). Biome scope hardened 2026-05-01 (commit `aaec1bc`): swapped `biome format biome.json .luarc.json` → `biome format .` so biome.json's `formatter.includes` drives scope (no shortcuts). |
| `blink-cmp-ghostty` | Justfile + `.#ci` added 2026-04-30 via skill v5.0 run (commit `b913466` cherry-picked onto forgejo branch as `b61dfc1`). Recipes: `format` (stylua + `biome format .`), `lint` (selene + lua-language-server), `test` (busted). Skill v5.0 single-batch: `.github/` ported+deleted + workflow YAML written in commit `bbb9e15` (4 ports + 8 deletes + 1 workflow create = 13 ops). |

Repos with `justfile` but no `test` recipe (Phase 6 status checks = `["Format","Lint"]`, Phase 5 omits the `test` job):

| Repo | Notes |
|------|-------|
| `barrettruth.com` | Skill v5.1 backfilled 2026-05-01: Next.js portfolio site (justfile install/run/build/format/lint/ci=format+lint+build, no Test recipe). github CI was a single `ci.yaml` with 3 jobs (Format+Lint+Build) — forgejo workflow mirrors exactly. **Clone auto-repair**: local was missing `forgejo` remote; skill added it. Phase 0 remigrated 5 issues + 67 PRs + 9 labels. LICENSE applied via POST (commit `d3fb4478`) since github has no LICENSE either. Phase 5 batch `f44a05ac` (1 create + 1 delete = 2 ops, smallest yet) — only one workflow file existed on github. All 3 jobs green on first poll. Topics already canonical (`nextjs,personal-website,portfolio`). Branch protection uses Format+Lint+Build contexts. |
| `http-codes.nvim` | Skill v5.0 backfilled 2026-04-30: `.github/` ported+deleted in batch commit `9a8bbcc` (3 issue templates ported; luarocks+quality workflows deleted). |
| `import-cost.nvim` | Skill v5.1 backfilled 2026-05-01: Lua plugin (justfile format/lint/ci=format+lint, no Test recipe). Format combines `nix fmt -- --ci` + `stylua --check .` + `prettier --check .`; lint combines `selene` + `lua-language-server --check` + `vimdoc-language-server check doc/`. Uses **prettier** (not biome). **Clone auto-repair**: local clone had `origin = forgejo` (non-canonical); skill renamed `origin → forgejo` and added github as new `origin`, then fixed branch tracking from `forgejo/main` → `origin/main` post-Phase-8. Phase 0 remigrated 12 issues + 22 PRs + 9 labels. LICENSE switched MIT→GPL via PUT (commit `939a923e`). Phase 5 batch `a8090752` (4 create + 5 delete = 9 ops): port 3 issue templates + quality.yaml; deleted luarocks (non-quality) + quality. Both checks green on first poll (instant). |
| `live-server.nvim` | Skill v5.1 backfilled 2026-05-01: Lua plugin (justfile format/lint/ci=format+lint). Standard-path Lua repo; biome+stylua+selene. **Clone auto-repair**: local was missing `forgejo` remote; skill added it. Phase 0 remigrated 17 issues + 32 PRs + 9 labels. LICENSE switched MIT→GPL via PUT (commit `343e844b`). Phase 5 batch `85baa364` (5 create + 6 delete = 11 ops): port 3 issue templates + pull_request_template + quality.yaml; deleted luarocks (non-quality) + quality. Both checks green on first poll. |
| `midnight.nvim` | Skill v5.0 backfilled 2026-04-30: format-fix (`.luarc.json` 2-space) at `d889ae0` (2026-04-30); `.github/` ported+deleted in batch commit `ac9f184` (3 issue templates ported; luarocks+quality workflows deleted). |
| `nonicons.nvim` | Skill v5.0 backfilled 2026-05-01: clone had origin pointing at forgejo (rename→forgejo + add github as origin; 9 feature branches retracked). Already biome-canonical on main pre-run (no prettier remediation). LICENSE re-applied at `c43a188`; batch commit `986fc77` (5 create + 8 delete = 13 ops; 4 issue/PR template ports + workflow YAML create + 8 .github deletes). DISCUSSION_TEMPLATE/q-a.yaml dropped (no fj eq). Non-quality workflows dropped: `luarocks.yaml`, `sync.yaml` (upstream-sync). Both Format+Lint green 1st poll. |
| `philipmruth.com` | Skill v5.0 backfilled 2026-05-01: Node.js/pnpm-based static site (Astro), already biome-canonical via `pnpm exec biome format .` in justfile. Per-repo override: justfile has `format`, `lint`, AND `build` recipes (not test) — workflow YAML manually expanded with the Build job, status_check_contexts uses 3 contexts. **Used corrected `(pull_request)` context names per the canola.nvim discovery** — first repo to use the fixed pattern from the start. github has NO LICENSE file (one of the 7 LICENSE-drift repos per AGENTS); after Phase 0 remigrate the LICENSE was added via POST (not PUT — the file didn't exist). LICENSE create commit `df41844`; batch commit `10555bf` (1 create + 1 delete = 2 ops; .github/workflows/ci.yaml dropped, .forgejo/workflows/quality.yaml created). All 3 checks (Format, Lint, Build) green 1st poll. |

Standard path (justfile + format + lint + test + flake + `.#ci`; all phases run unmodified):

| Repo | Note |
|------|------|
| `canola-collection` | Skill v5.1 backfilled 2026-05-01: Phase 0 remigrated 13 issues + 42 PRs + 9 labels (stable on first poll). LICENSE re-applied. Phase 5 batch commit `00a05b6a` (4 create + 8 delete = 13 ops): 4 ports, dropped DISCUSSION_TEMPLATE + non-quality workflows (`luarocks.yaml` flagged in backlog). **Phase 7 first attempt RED on Test job**: tests `require('canola.config')` from sibling canola.nvim repo via the justfile's `_canola` lookup; CI runner had no such directory. **Fix applied at commit `1a3f898`**: extended forgejo `quality.yaml` Lint+Test jobs with second `actions/checkout@v4` step that pulls `barrettruth/canola.nvim` ref `canola` into `_canola/` (mirrors the github workflow's pattern, sans nvim-version matrix). All 3 checks green on first re-poll. Topics fix: removed bogus `colorscheme` (was an inherited backfill error from a sister-repo template) — now `neovim,neovim-plugin,canola` on Forgejo only (github untouched per skill's Forgejo-only-writes directive). |
| `canola.nvim` | Skill v5.0 backfilled 2026-05-01 with **two-branch port** (main + canola). Phase 0 remigrated 69 issues + 269 PRs + 12 labels (largest migration in corpus). Per-branch batches: main `e3c6cc8` (27 ops: 2 update + 9 create + 16 delete) + canola `31a0b8c` (25 ops: 3 update + 6 create + 16 delete). Each batch contained: GPL LICENSE switch + .prettierrc delete + biome.json create (with vcs.useIgnoreFile + formatter.includes) + justfile create-on-main/update-on-canola (drops prettier→biome, drops `stylua --check lua spec` scope shortcut → `stylua --check .`) + flake.nix update (replaces `pkgs.prettier` → `pkgs.biome`) + `.forgejo/workflows/quality.yaml` create with **per-branch trigger** (main's workflow filters on `main`, canola's on `canola`) + 4-6 .github/ ports + 16 .github/ deletes. CI: canola **3/3 green**; main **Lint fails** on pre-existing `oil.txt` vimdoc-LS errors (`\|vim.keymap.set\|` line 711 + `\|nvim_create_autocmd\|` line 1451 — external nvim help refs that vimdoc-LS can't resolve). User-agreed accepted state: red CI on main migration commit; oil.txt fixes are a separate canola.nvim issue per its CLAUDE.md workflow. Both branches protected with full canonical schema (Format, Lint, Test). Flagged for manual review (per skill 5a unknown-class rule, NOT auto-ported): `.github/pre-commit`, `.github/pre-push`, `.github/scripts/upstream_digest.py` — the user decides where these belong (root `hooks/`? lefthook? `scripts/`?). Non-quality workflows dropped (`luarocks.yaml`, `automation_remove_question_label_on_comment.yml`, `automation_request_review.yml`, `upstream-digest.yaml`) — tracked in AGENTS "Non-quality workflow port backlog". |
| `cp.nvim` | Skill v5.1 backfilled 2026-05-01: flake.nix already has `.#ci` (per-repo override note from earlier was stale). Polyglot toolchain (Lua + Python): justfile recipes invoke stylua/biome/selene/lua-LS/vimdoc-LS for Lua + ruff/ty/pytest for Python. flake's `mkToolingShell` covers both. LICENSE re-applied at `8e3aefa`; batch commit `9bcee7c` (4 create + 6 delete = 10 ops). 3 issue templates ported, 3 workflows dropped (luarocks non-quality + quality + test). PR async-import was slow (took ~90s after migrate to settle from 98 → 257 PRs). All 3 checks (Format, Lint, Test) green 1st poll using corrected v5.1 `(pull_request)` contexts. |
| `delta` | Skill v5.1 backfilled 2026-05-01: full-stack TS web app (Next.js + Drizzle + SQLite + biome + pnpm). Phase 0 remigrated 156 issues + 105 PRs + 17 labels (largest non-canola corpus). LICENSE re-applied at `30980a8c` (github has no LICENSE either). github CI structure was 4 jobs (Lint+Test+Build+Deploy) with no separate Format job (lint covers it via `biome check`); forgejo workflow mirrors **3 jobs only** (Lint+Test+Build) — Deploy job was github-only with VPS_HOST/USERNAME/SSH_KEY secrets, dropped per "non-quality workflow port backlog" rule. Phase 5 batch commit `8eb1d7a8` (1 create + 4 delete = 5 ops): port `quality.yaml` only, dropped `nightly.yaml`/`release.yaml`/`release-cli.yaml`. **Phase 7 RED on Test job**: 1/611 tests failed in `tests/core/encryption.test.ts:92` (`fails to decrypt tampered auth tag`) — pre-existing **flaky test**: tampers last 2 hex chars of auth tag with `"ff"`, no-op (~1/256) when original byte was already `0xff`. Lint passed; Build skipped (depends on Test). User-agreed accepted state per canola.nvim pattern: red CI on migration commit; flaky test fix is a separate delta PR. Branch protection still uses canonical Lint+Test+Build contexts. Topics already canonical (`todo,productivity,nextjs,sqlite,self-hosted`). |
| `diffs.nvim` | Skill v5.0 backfilled 2026-04-30: LICENSE re-applied at `bbe2cd86e0`; `.github/` ported+deleted in single batch commit `6bc8ffc` (4 ports → `.forgejo/issue_template/*` + `.forgejo/pull_request_template.md`; 8 deletes incl. DISCUSSION_TEMPLATE/q-a.yaml, 3 workflows). Phase 0 now reports "complete" on re-runs. |
| `forge.nvim` | Skill v5.1 backfilled 2026-05-01: forge-agnostic git workflow plugin; standard-path Lua repo (justfile format/lint/test/ci, flake `.#ci`, biome+stylua+selene+luarc). Phase 0 remigrated 240 issues + 316 PRs + 11 labels. LICENSE switched MIT→GPL via PUT (not POST) since gh has MIT and remigrate brought it over (commit `12634c6b`). Phase 5 batch `ab2fc0cd` (5 create + 8 delete = 13 ops): port issue templates + pull_request_template + quality.yaml; deleted DISCUSSION_TEMPLATE/q-a.yaml + 3 workflows. **Phase 7 first attempt RED on Test job**: forge.nvim's `spec/yaml_spec.lua` and `spec/template_spec.lua` use `.github/ISSUE_TEMPLATE/*.yaml` and `.github/pull_request_template.md` AS TEST FIXTURES (the plugin parses github-style issue templates as a feature, so its tests need example yaml files; those examples happen to be the repo's own issue templates). Phase 5's deletion broke the tests. **Fix applied at commit `2dbc895b`**: re-create the 4 .github/ files as test fixtures (bug_report.yaml, config.yaml, feature_request.yaml, pull_request_template.md). Now both `.github/` (test fixtures) and `.forgejo/issue_template/` (canonical forgejo issue templates) coexist. All 3 jobs green on first re-poll. **Pattern flagged**: when porting `.github/` → `.forgejo/`, check if any spec files reference `.github/` paths as fixtures BEFORE deleting; if so, restore the github copies post-port. |
| `preview.nvim` | Skill v5.1 backfilled 2026-05-01: standard-path Lua repo (justfile format/lint/test/ci, flake `.#ci`, biome+stylua+selene+luarc). **Clone auto-repair**: local `~/dev/preview.nvim` was missing `forgejo` remote entirely (only had `origin = github`); skill added it: `git remote add forgejo ssh://git@git.barrettruth.com/...`. Phase 0 remigrated 28 issues + 86 PRs + 9 labels (stable on first poll). LICENSE switched MIT→GPL via PUT (commit `7cfd7877`). Phase 5 batch `8f19196b` (6 create + 8 delete = 14 ops): port 4 issue templates + pull_request_template + quality.yaml; deleted 3 workflows (luarocks non-quality + quality + test). Spec-fixture pre-check found nothing — safe to delete `.github/`. All 3 jobs green on first poll. |
| `tmux-mosaic` | Canonical baseline. Skill v5.0 backfilled 2026-04-30: LICENSE re-applied at `f63226d`; `.github/` ported+deleted in batch commit `88f4709` (4 ports + 13 deletes incl. RELEASE_PROCESS.md, release.yml, 6 non-quality workflows: automation_release_metadata, automation_remove_question_label_on_comment, automation_request_review, release_nightly, release_prepare, release_publish). CI flaked once on test.bats #41 + #143 (timing-sensitive tmux IPC) on the initial migration commit; retried green via empty signed commit `d1e747e`. Flaked AGAIN 2026-05-01 on test.bats #122 ("new-pane fast paths: grid 2 -> 3 keeps the new pane in the bottom tail before relayout"; `_mosaic_pane_left "$pane"` != `_mosaic_pane_left "$old_tail"`) after the runs-on `spark`→`nix` rename push (commit `f3897554`); retried green via empty unsigned commit `9c780c9` (GPG signing timed out so used `--no-gpg-sign` per session rule). The recurring flake pattern across #41/#122/#143 strongly suggests a real timing race in the tmux IPC layer, not just CI noise — should land a bats-test stabilizer (e.g., `wait_for_pane_count` polling helper in lieu of fixed sleeps) as a follow-up tmux-mosaic PR. Non-quality workflows are tracked in AGENTS "Non-quality workflow port backlog" for future per-workflow port. Biome scope hardened 2026-05-01 (commit `2b7962a`): biome.json gained `vcs.useIgnoreFile:true`, `files.ignoreUnknown:false`, `formatter.includes:["**","!**/node_modules/"]`; justfile swapped `biome format biome.json README.md .forgejo .github` → `biome format .`. Local `biome format .` now scans 5 files (down from 52,296 due to the missing `vcs.useIgnoreFile`). |
| `vimdoc-language-server` | Skill v5.1 backfilled 2026-05-01: polyglot Rust+pnpm-site-build repo (justfile recipes wrap `cargo fmt`/`clippy`/`test`/`build` for rust + `prettier --check .` for markdown + `cd site && pnpm` for the docs site). Uses **prettier** (not biome) for markdown — that's fine since `nix develop .#ci` provides `pkgs.prettier`. Phase 0 remigrated 42 issues + 94 PRs + 9 labels (stable on first poll). LICENSE switched MIT→GPL via PUT (commit `1816c556`). github CI was 5 separate workflow files (format/lint/test/release/nightly) — forgejo workflow consolidates **3 jobs only** (Format+Lint+Test) into one quality.yaml; release/nightly dropped per non-quality backlog. Phase 5 batch `461dc14c` (5 create + 10 delete = 15 ops): largest .github/ delete count seen (5 separate workflow files + DISCUSSION_TEMPLATE + 4 templates). All 3 jobs green on first poll. Local clone had a WIP flake.nix diff (cargoToml-as-source-of-truth refactor for pname/version) — stashed during pre-flight, restored in Phase 8. |

When a repo isn't listed above, run all phases unmodified. Any forgejo-unique commit (LICENSE switch, prior `.forgejo/workflows/quality.yaml` write, etc.) is handled by Phase 4's rebase logic — no per-repo annotation required.

### Recommended topic tags (applied 2026-04-30)

Used by Phase 2 if Forgejo's topics are empty. Already pushed to all 24 public repos in the 2026-04-30 sweep, so future skill runs should report "topics already populated".

| Repo | Topics |
|------|--------|
| `barrettruth.com` | `personal-website,portfolio,nextjs` |
| `barrettruth.github.io` | (intentionally empty — github-pages legacy redirect) |
| `blink-cmp-ghostty` | `blink-cmp,neovim,neovim-plugin,ghostty,completion` |
| `blink-cmp-ssh` | `blink-cmp,neovim,neovim-plugin,ssh,completion` |
| `blink-cmp-tmux` | `blink-cmp,neovim,neovim-plugin,tmux,completion` |
| `canola-collection` | `neovim,neovim-plugin,canola` |
| `canola.nvim` | `neovim,neovim-plugin,file-explorer,oil` |
| `cp` | `competitive-programming,algorithms` |
| `cp.nvim` | `competitive-programming,neovim,neovim-plugin` |
| `delta` | `todo,productivity,nextjs,sqlite,self-hosted` |
| `diffs.nvim` | `neovim,neovim-plugin,treesitter,vim` |
| `forge.nvim` | `fzf-lua,neovim,neovim-plugin` |
| `http-codes.nvim` | `fzf-lua,neovim,neovim-plugin,telescope-extension` |
| `import-cost.nvim` | `import-cost,neovim,neovim-plugin` |
| `live-server.nvim` | `live-server,neovim,neovim-plugin` |
| `midnight.nvim` | `neovim,neovim-colorscheme,neovim-plugin` |
| `nix` | `nixos,nixos-configuration,dotfiles,flake` |
| `nonicons.nvim` | `neovim,neovim-plugin,icons,nonicons` |
| `philipmruth.com` | `personal-website,portfolio,nextjs` |
| `preview.nvim` | `neovim,neovim-plugin,preview,markdown` |
| `sioyek-dev` | `sioyek,pdf-viewer,fork` |
| `tmux-mosaic` | `tmux,tmux-plugin,tiling,layouts` |
| `vimdoc-language-server` | `language-server-protocol,lsp,lsp-server,neovim,vim` |
| `whitepapers` | `whitepapers,research,papers` |

## Migration target list (refresh on demand)

Live, derive at run-time. NOTE: `/users/barrettruth/repos` filters out some repos and paginates at 50; use `/repos/search` and walk pages:

```
tea api -l vps "/repos/search?owner=barrettruth&private=false&limit=100" \
  | jq -r '.data[] | .name' \
  | sort
```

As of 2026-04-30 the 24 public targets are (alphabetically):

```
barrettruth.com         barrettruth.github.io   blink-cmp-ghostty
blink-cmp-ssh           blink-cmp-tmux          canola-collection
canola.nvim             cp                      cp.nvim
delta                   diffs.nvim              forge.nvim
http-codes.nvim         import-cost.nvim        live-server.nvim
midnight.nvim           nix                     nonicons.nvim
philipmruth.com         preview.nvim            sioyek-dev
tmux-mosaic             vimdoc-language-server  whitepapers
```

`tree-sitter-diff` was hard-deleted and `uvm-bench` was made private during the license cleanup pass, so neither appears here.
