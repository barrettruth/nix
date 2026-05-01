# Git Workflow Rules

## Commit Message Format

```
type(scope): imperative summary

Problem: describe the issue or motivation

Solution: describe what this commit does
```

### Header

- **type** (required): `feat` `fix` `docs` `refactor` `perf` `test` `ci` `build` `revert`
- **scope** (optional): lowercase module/area name, e.g. `feat(parser):`
- **summary**: imperative mood, lowercase after colon, no trailing period, max 72 chars

### Body

Required for any non-trivial change. Use `Problem:` / `Solution:` sections.
2-3 sentences per section, max. Wrap at 72 characters. Separate from header
with a blank line.

Use backticks around code identifiers, function names, and file paths
(e.g. `setup()`, `lua/oil/view.lua`, `FIELD_NAME`).

### Examples

Good:

```
fix(lsp): correct off-by-one in `diagnostic_range`

Problem: diagnostics highlighted one character past the actual error,
causing confusion on adjacent tokens.

Solution: subtract 1 from the end column returned by the language
server before converting to 0-indexed nvim columns.
```

```
refactor: extract repeated buffer lookup into `get_buf_entry`
```

Bad:

```
Fixed stuff
feat: Add Feature.
fix(lsp): correct off-by-one in diagnostic range and also refactor the
entire highlight module and add new tests
```

## Branch Rules

Always work on a feature branch. Never commit or push directly to `main` or
`master`. If on the default branch, create and switch to a topic branch first.

```
type/short-description
```

Examples: `fix/diagnostic-range`, `feat/code-actions`, `refactor/highlight-module`

## PR Body Format

If the repo has `.github/pull_request_template.md`, follow that template exactly.

If no template exists, fall back to:

```
## Problem

<1-2 sentences>

## Solution

<1-2 sentences>
```

Write concise prose. No bullet-point walls, no verbose AI-style markdown.
Use backticks for code references.

## Post-PR Steps

After creating a PR, immediately:

1. Fetch upstream: `git fetch origin`
2. Check for conflicts between your branch and `origin/main`:
   `git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main`
3. If conflicts exist, rebase or merge `origin/main` into the branch and resolve
   them before considering the PR done.

## GPG Signing

If GPG signing fails for any reason, retry the commit or push with
`--no-gpg-sign` rather than stopping.

## Decomposition Rules

- One logical change per commit.
- Refactors go in their own commit before the feature that depends on them.
- Formatting/style changes are never mixed with behavioral changes.
- Test-only commits are fine when adding coverage for existing code.
- If a PR has more than ~3 commits, consider whether it should be split into
  separate PRs.
