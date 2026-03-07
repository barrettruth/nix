---
name: canola
description: This skill should be used when starting a canola.nvim issue fix
  session, processing upstream oil.nvim issues, or when the user invokes /canola.
version: 0.3.0
---

# Canola Issue Fix Session

## Repo rules (non-negotiable)

- ALL PRs target `barrettruth/canola.nvim` (remote `origin`) — NEVER `stevearc/oil.nvim`
- Upstream (`stevearc/oil.nvim`) is READ-ONLY: fetch, diff, view — never push or open PRs
- Always pass `--repo barrettruth/canola.nvim` explicitly to every `gh pr` command

## Phase 1: Research (parallel, 2 issues at a time)

Process at most 2 issues per session. Spawn one Agent(subagent_type=general,
worktree=true) per issue using EnterWorktree so each agent works in an
isolated git worktree. Each agent receives: issue number, description, and
instructions to find:
- Root cause (which files, which functions, line numbers)
- Whether a test already covers it
- Whether the fix has side effects in other adapters or modes
- What upstream's latest state is

## Phase 2: Plan mode — present BEFORE implementing

Call EnterPlanMode immediately after research completes.

For each issue, present the FULL picture:
- Problem statement (2-3 sentences, not just the title)
- Root cause (files + line numbers)
- **Expected behavior** — what the correct outcome looks like, step by step,
  so the user knows exactly what to verify after the fix
- Solution A: description, tradeoffs, risks
- Solution B: description, tradeoffs, risks
- Recommended solution and why
- Config surface change? (yes/no) → vimdoc needed?

Do NOT write any code or edit any files during plan mode.
Do NOT exit plan mode until the user has approved an approach for every issue.
Call ExitPlanMode only after receiving explicit approval.

## Phase 3: Implement (one at a time, after plan mode exits)

For each approved issue:
1. Write `/tmp/minimal_init.lua` — self-contained repro
2. Give user step-by-step instructions to confirm bug reproduces
3. Implement fix
4. Give user the pre-laid-out expected behavior from Phase 2 as a checklist
   to verify the fix works (no surprises — user already knows what to expect)
5. /gc — conventional commit on fix/<short> branch
6. /pr — push, create PR targeting `barrettruth/canola.nvim` with Problem/Solution body
7. Update doc/upstream.md — status → fixed, add PR + commit link
8. /gc + push the upstream.md change on same branch

## Subagent Research Prompt Template

"Research upstream oil.nvim issue #NNN for the canola.nvim fork.
Read: doc/upstream.md entry for this issue, then trace the relevant
source files to find the root cause. Return:
- Affected files and functions (with line numbers)
- Root cause in 2-3 sentences
- Expected correct behavior (step by step)
- Risky areas (other code that touches the same path)
- Whether existing tests cover this behavior"
