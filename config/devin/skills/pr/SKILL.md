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
- **No broken CI.** If the repo defines a recognized CI entrypoint and it
  fails, stop. No PR.
- **No conflicts.** If merge conflicts exist against `origin/main`, stop. No PR.
- **No force-push.**
- **No AI attribution.** No `Co-Authored-By`, `Signed-off-by`, or tool mentions.

## CI command detection

Determine the repo CI command at the git root in this order:

1. If the repo has `justfile` / `Justfile` and `just --summary` includes `ci`:
   - if the repo also has `flake.nix`, use:

     ```
     nix develop .#ci --command just ci 2>&1
     ```

   - otherwise use:

     ```
     just ci 2>&1
     ```

2. Otherwise, if `scripts/ci.sh` exists, use:

   ```
   bash scripts/ci.sh 2>&1
   ```

3. Otherwise, there is no recognized repo CI entrypoint.

## Workflow

### 1. Pre-flight

Gather branch, commit log, and diffstat. Check stop conditions:

- On `main`/`master` -> stop: "Use `/gc` to commit first (it creates a branch),
  then run `/pr`."
- No commits ahead of `main` -> stop: "Nothing to PR."

### 2. Launch background checks (immediately, in parallel)

Start these BEFORE drafting. Use background shell execution.

**CI** — only if CI command detection found a recognized repo entrypoint.
Launch the detected command in the background.

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

**Body:** if a PR template exists, fill it in exactly. Otherwise use exactly:

```
## Problem

<1 sentence>

## Solution

<1-2 sentences>
```

Concise prose. Backticks for code identifiers and file paths. No bullet walls.
Do not use `Summary`, `Test Plan`, checklists, or any other invented sections.
Always pass an explicit PR body to `gh pr create`. Do not rely on defaults.

Present the title and body. Ask for approval.

### 4. Gate on background results (blocking)

After approval, **wait for all background checks to complete**. Poll if needed.
Do not proceed until both have finished.

| Result                   | Action                                                                |
| ------------------------ | --------------------------------------------------------------------- |
| CI failed                | Show full output. **Stop.** Do not push or create the PR.             |
| Conflicts detected       | Show conflicting paths. **Stop.** Offer to rebase onto `origin/main`. |
| CI passed + no conflicts | Proceed to step 5.                                                    |

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
