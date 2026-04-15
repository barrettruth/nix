---
name: gc
description: Create a conventional commit with strict guardrails
user-invocable: true
---

# /gc

Create a single conventional commit from current changes.

## Guardrails (non-negotiable)

These rules are absolute. Do not proceed if any would be violated.

- **No main commits.** If on `main` or `master`, create a feature branch first.
- **No AI attribution.** Never add `Co-Authored-By`, `Signed-off-by`, or any
  AI/tool attribution in commits.
- **No AI config files.** Exclude from staging: `AGENTS.md`, `.devin/`,
  `.cursor/`, `.windsurf/`, `.agents/`.
- **One logical change.** If the diff contains unrelated changes, ask which
  subset to include. Refactors, formatting, and features are separate commits.
- **GPG fallback.** If signing fails, retry with `--no-gpg-sign`.

## Workflow

### 1. Gather state

Collect branch, status, staged diff, and recent history in parallel or in a
single command. You need: current branch name, `git status --short`,
`git diff --cached --stat`, and `git log --oneline -5`.

### 2. Branch gate

If on `main` or `master`:

1. Infer a branch name from the working changes: `type/short-description`
   (e.g. `fix/null-check`, `feat/export-csv`).
2. Create and switch: `git checkout -b <branch>`.
3. Continue from step 3.

Valid branch prefixes: `feat/`, `fix/`, `refactor/`, `docs/`, `test/`,
`perf/`, `ci/`, `build/`.

### 3. Stage changes

If nothing is staged (`git diff --cached` is empty):

- Review `git status --short`. Filter out AI config files listed above.
- If the remaining files form one logical change, stage them all.
- If files look unrelated, present the list and ask which to stage.
- After staging, get the full diff: `git diff --cached`.

### 4. Draft commit message

```
type(scope): imperative summary

Problem: <why this change is needed — 2-3 sentences>

Solution: <what this commit does — 2-3 sentences>
```

- **type** (required): `feat` `fix` `docs` `refactor` `perf` `test` `ci`
  `build` `revert`
- **scope** (optional): lowercase module or area name.
- **Header**: lowercase after colon, no trailing period, max 72 chars.
- **Body**: required for non-trivial changes. Wrap at 72 chars. Use backticks
  for code identifiers, function names, and file paths.
- **Trivial changes** (typo, rename, version bump): header only, no body.
- Match the tone and style of the recent commits from step 1.

### 5. Confirm

Present the full commit message. Ask for approval. Accept edits.

### 6. Commit

Run `git commit -m "<message>"`. If GPG signing fails, retry with
`git commit --no-gpg-sign -m "<message>"`.

Never amend. Never push (that's `/pr`'s job).
