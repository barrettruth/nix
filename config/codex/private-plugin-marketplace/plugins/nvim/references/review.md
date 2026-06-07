# Review Contract

Use for `$nvim-review`. This is a human inspection checkpoint for local
implementation patches, not commit preparation.

Do not read Codex memory.

Resolve `.codex/issue-wiki` as a plain key/value pointer file. If an issue
number is given, check
`/home/barrett/dev/neovim/.worktrees/<issue>/.codex/issue-wiki` first; do not
scan worktrees or run `git worktree list` unless that direct path is missing.
Follow its `wiki=` path and read `index.md`.

Proceed only when there are local reviewable implementation changes. Hard-stop
if there are no reviewable changed files. Do not route blocked, resolved
upstream, clarify, more-repro, or no-change outcomes through review.
For those states, stop without writing `evidence/review.md`.

Changed-file selection is broad by default: include changed tracked files and
untracked files, except known workflow/build junk. Exclude:

```text
.codex/
build/
.deps/
.cmake/
.tmp/
```

Do not stage, unstage, clean, revert, or diagnose staged-state weirdness. Use
the current git file state as-is.

Do not run verification, Spark, builds, tests, or local check commands. Read
`evidence/verify.md` if present; otherwise mark verification as missing.

Compute the review base with:

```sh
git -C <worktree> merge-base HEAD upstream/master
```

Write and overwrite:

```text
<wiki>/evidence/review.md
```

Use this shape:

```markdown
# Review

Status: ready for Barrett review

## Diff
- `path`: what changed and why it matters

## Evidence
- Plan: `evidence/plan.md`
- Verification: `evidence/verify.md` or `missing`

## Manual Review Focus
- `path`: what Barrett should inspect

## Risks
- Concrete remaining risks, or `None obvious from diff review.`

## UI
- Greview base: `<merge-base>`
- Edit quickfix: `review.md` + N changed files
```

Valid statuses:

- `ready for Barrett review`
- `needs verification`
- `needs changes`

After writing `review.md`, update only:

- `index.md`: review status and link to `evidence/review.md`
- `log.md`: one short append-only entry

Then prepare the live UI with:

```sh
../../scripts/review-ui.py --worktree <worktree> --base <merge-base> -- <wiki>/evidence/review.md <changed-file>...
```

The helper owns only live UI setup: `mux vcs`, `:Greview <base> | only`, mux
`edit` quickfix population, and restoring the foreground tmux window. It does
not read the issue wiki, inspect git, write markdown, verify, stage, commit, or
touch GitHub.

Stop before commit preparation, staging, commits, pushes, PR work, or GitHub
mutation.
