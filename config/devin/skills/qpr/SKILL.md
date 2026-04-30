---
name: qpr
description: Quick PR — no approval, same CI/conflict gates as /pr
user-invocable: true
---

# /qpr

Create a pull request immediately with no approval step. Background CI and
conflict checks still run and still block — the only difference from `/pr` is
that the title/body are auto-generated without asking.

## Guardrails

Same as `/pr`. Non-negotiable:

- No main push.
- No broken CI.
- No conflicts.
- No force-push.
- No AI attribution.

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

Gather branch, commit log ahead of `main`, and diffstat.

- On `main`/`master` -> stop.
- No commits ahead -> stop.

### 2. Launch background checks (immediately, in parallel)

**CI** — if CI command detection found a recognized repo entrypoint, launch the
detected command in the background.

**Conflict detection:**

```
git fetch origin main --quiet 2>/dev/null && \
  git merge-tree "$(git merge-base HEAD origin/main)" HEAD origin/main 2>/dev/null
```

### 3. Auto-generate PR (while background runs, no approval)

Check for `.github/pull_request_template.md`.

- **Title:** `type(scope): imperative summary` from the commit(s).
- **Body:** if a PR template exists, fill it in exactly. Otherwise use exactly:

  ```
  ## Problem

  <1 sentence>

  ## Solution

  <1-2 sentences>
  ```

  Do not use `Summary`, `Test Plan`, checklists, or any other invented
  sections. Always pass an explicit PR body to `gh pr create`. Do not rely on
  defaults.

Do NOT present for approval. Proceed directly.

### 4. Gate on background results

Wait for all background checks. Same rules as `/pr`:

- CI failed -> stop, show output.
- Conflicts -> stop, show details, offer rebase.
- All clear -> proceed.

### 5. Push and create

```
git push -u origin HEAD && \
  gh pr create --title "<title>" --body "<body>"
```

GPG fallback: `--no-gpg-sign`. Print the PR URL.

### 6. Post-creation (background)

Check `gh issue list --state open --limit 10` for related issues.
