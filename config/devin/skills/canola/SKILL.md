---
name: canola
description: Canola.nvim issue fix session — research, plan, implement
user-invocable: true
version: 1.0.0
---

# /canola

Process upstream oil.nvim issues for the canola.nvim fork.

## Repo rules (non-negotiable)

- ALL PRs target `barrettruth/canola.nvim` (remote `origin`).
  Always pass `--repo barrettruth/canola.nvim` to every `gh pr` command.
- Upstream `stevearc/oil.nvim` is **read-only**: fetch, diff, view — never push
  or open PRs against it.

## Phase 1 — Research (parallel)

Process at most 2 issues per session. For each issue, launch a **background
subagent** (`run_subagent` with `subagent_general` profile, `is_background=true`)
so research runs in parallel.

Each subagent receives:

- Issue number and description
- Instructions to find:
  - Root cause (files, functions, line numbers)
  - Whether existing tests cover the behavior
  - Whether the fix has side effects in other adapters or modes
  - Upstream's latest state on the affected code

Wait for all research subagents to complete before proceeding.

## Phase 2 — Plan (present before implementing)

For each issue, present the full picture using `todo_write` to track:

- **Problem statement** — 2-3 sentences, not just the issue title.
- **Root cause** — files and line numbers.
- **Expected behavior** — step-by-step description of the correct outcome,
  so the user knows exactly what to verify after the fix.
- **Solution A** — description, tradeoffs, risks.
- **Solution B** — description, tradeoffs, risks.
- **Recommended solution** and why.
- **Config surface change?** If yes, vimdoc update needed.

Do NOT write code or edit files during this phase.
Do NOT proceed until the user has approved an approach for every issue.

## Phase 3 — Implement (one issue at a time)

For each approved issue:

1. Write `/tmp/minimal_init.lua` — self-contained repro config.
2. Give the user step-by-step instructions to confirm the bug reproduces.
3. Implement the fix.
4. Present the expected-behavior checklist from Phase 2 for the user to verify.
5. Invoke `/gc` — conventional commit on a `fix/<short>` branch.
6. Invoke `/pr` — push, create PR targeting `barrettruth/canola.nvim` with
   Problem/Solution body. CI and conflict checks run in background as per
   `/pr` workflow.
7. Update `doc/upstream.md` (see rules below).
8. Invoke `/gc` + push the `upstream.md` change on the same branch.

## `doc/upstream.md` rules

The tracker has grouped tables. Each issue/PR appears in exactly ONE section.

### Sections

- **Upstream PRs** — single table, all upstream PRs. Status is a column.
- **Issues** — single table, sorted by number. Columns: Issue, Description,
  Status.

### Issue status values

| Status                     | Meaning                                |
| -------------------------- | -------------------------------------- |
| `open`                     | Unresolved                             |
| `fixed (#NN)`              | Fixed in this fork, with fork PR link  |
| `cherry-picked (#NN)`      | Resolved by cherry-picking upstream PR |
| `not actionable -- reason` | Won't fix, with explanation            |

### Rules

- When fixing an issue: change status from `open` to `fixed (#NN)` with the
  fork's PR number.
- Never include commit hashes — only PR numbers (stable across rebases).
- Never include priority markers (P0/P1/P2).

### Link format

- Upstream issues: `[#NNN](https://github.com/stevearc/oil.nvim/issues/NNN)`
- Upstream PRs: `[#NNN](https://github.com/stevearc/oil.nvim/pull/NNN)`
- Fork PRs: `[#NNN](https://github.com/barrettruth/canola.nvim/pull/NNN)`
