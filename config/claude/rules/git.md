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
Wrap at 72 characters. Separate from header with a blank line.

### Examples

Good:

```
fix(lsp): correct off-by-one in diagnostic range

Problem: diagnostics highlighted one character past the actual error,
causing confusion when multiple diagnostics appeared on adjacent tokens.

Solution: subtract 1 from the end column returned by the language server
before converting to 0-indexed nvim columns.
```

```
refactor: extract repeated buffer lookup into helper
```

Bad:

```
Fixed stuff          # not imperative, vague
feat: Add Feature.   # uppercase after colon, trailing period
fix(lsp): correct off-by-one in diagnostic range and also refactor the
entire highlight module and add new tests   # multiple concerns
```

## Branch Naming

```
type/short-description
```

Examples: `fix/diagnostic-range`, `feat/code-actions`, `refactor/highlight-module`

## PR Body Format

If the repo has `.github/pull_request_template.md`, follow that template exactly.

If no template exists, fall back to:

```
## Problem

<why this change is needed>

## Solution

<what the change does>
```

Either way, write in plain prose. No bullet-point walls, no AI-style markdown
headings beyond what the template calls for. Keep it concise and human.

## Decomposition Rules

- One logical change per commit.
- Refactors go in their own commit before the feature that depends on them.
- Formatting/style changes are never mixed with behavioral changes.
- Test-only commits are fine when adding coverage for existing code.
- If a PR has more than ~3 commits, consider whether it should be split into
  separate PRs.
