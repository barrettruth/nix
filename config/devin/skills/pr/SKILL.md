---
name: pr
description: Create a PR with background CI and conflict validation — never merges broken code
user-invocable: true
---

# /pr

Create a pull request. CI and upstream conflict checks run in the **background**
from the start. The PR is never created if either fails.

## Guardrails (non-negotiable)

- **No main push.** Never push to `main`/`master` by branch name or refspec.
- **No broken CI.** If `scripts/ci.sh` exists and fails, stop. No PR.
- **No conflicts.** If merge conflicts exist against `origin/main`, stop. No PR.
- **No force-push.**
- **No AI attribution.** No `Co-Authored-By`, `Signed-off-by`, or tool mentions.

## Workflow

### 1. Pre-flight

Gather branch, commit log, and diffstat. Check stop conditions:

- On `main`/`master` -> stop: "Use `/gc` to commit first (it creates a branch),
  then run `/pr`."
- No commits ahead of `main` -> stop: "Nothing to PR."

### 2. Launch background checks (immediately, in parallel)

Start these BEFORE drafting. Use background shell execution.

**CI** — only if `scripts/ci.sh` exists at the git root:

```
bash scripts/ci.sh 2>&1
```

**Conflict detection:**

```
git fetch origin main --quiet 2>/dev/null && \
  git merge-tree "$(git merge-base HEAD origin/main)" HEAD origin/main 2>/dev/null
```

Both run concurrently. Do not wait for them — proceed to step 3.

### 3. Draft PR (while background runs)

Check for `.github/pull_request_template.md`.

**Title:** `type(scope): imperative summary` — max 72 chars.
- Single-commit PRs: reuse the commit message header.
- Multi-commit: write a summary that covers all changes.

**Body:** if a PR template exists, fill it in. Otherwise:

```
## Problem

<1-2 sentences>

## Solution

<1-2 sentences>
```

Concise prose. Backticks for code identifiers and file paths. No bullet walls.

Present the title and body. Ask for approval.

### 4. Gate on background results (blocking)

After approval, **wait for all background checks to complete**. Poll if needed.
Do not proceed until both have finished.

| Result | Action |
|--------|--------|
| CI failed | Show full output. **Stop.** Do not push or create the PR. |
| Conflicts detected | Show conflicting paths. **Stop.** Offer to rebase onto `origin/main`. |
| CI passed + no conflicts | Proceed to step 5. |

This gate is non-negotiable. There is no override. If the user wants to skip
CI, they must push manually — this skill will not do it.

### 5. Push and create

```
git push -u origin HEAD && \
  gh pr create --title "<title>" --body "<body>"
```

If GPG signing fails on push, retry with `--no-gpg-sign`.
Print the PR URL.

### 6. Post-creation checks (background)

After PR creation, run in the background:

```
gh issue list --state open --limit 10
```

If any open issues relate to the PR's changes, mention them and ask whether
to link or close.
