# Neovim Agent Workflow Backlog

Planning notes only. This file is not part of the `nvim` skill and does not
grant agents permission to commit, push, clean, publish, or interact remotely.

## Commit And PR Gates

- Dedicated commit workflow with literal `commit` permission only.
- Hard rejection of AI, co-author, co-assisted, and signoff attribution.
- Separate push/publish/PR workflow.
- PR creation must fail if no local commit exists.
- PR body, title, review, and maintainer-interaction policy needs separate
  research before enabling remote writes.

## Remote Interaction Guardrails

- Codex execpolicy rules for obvious forbidden command prefixes.
- `PreToolUse` hook for parsed `git`, `gh`, `gh api`, GraphQL, aliases, and
  shell wrappers.
- Git hooks that reject prohibited attribution and protect pushes.
- Decide whether plugin-bundled hooks should be enabled at all.

## Spark Build System

- Exact Spark CLI contract for Neovim builds/tests is initially implemented in
  `scripts/spark`; revisit after real use.
- Run one real issue worktree through build/test/clean before changing the
  contract.
- Decide after that dry run whether parallel subagents share one issue mirror or
  need explicit suffixed mirrors.
- Resource defaults and safe concurrency still need observed data.

## Verification And CI

- What counts as a cheap local check versus Spark-only validation.
- How to map changed files to focused Neovim checks.
- Exact compile/build commands and expected build directories.
- Targeted functional/unit/oldtest commands and failure interpretation.
- Local CI-equivalent strategy versus read-only remote GitHub CI status.
- How issue-wiki reports should explain what was checked and why.

## Reproduction Playbooks

- Future `nvim-repro` workflow.
- Headless, UI, TUI, RPC, `--server`, job-control, terminal, LSP, and network
  reproduction patterns.
- How to use internals while keeping reproducer reports objective.
- How to record failed reproduction attempts without proposing fixes.

## Context And Speed

- Research `codegraph` only after one or two real issue reports show concrete
  token/context pain.
- Compare other context-reduction tools before adopting one, and keep any tool
  read-only until it proves useful.
- Decide how generated code maps link into the issue wiki without bloating
  `index.md`.
- Post-optimize agent speed after the core workflow and guardrails work.

## Editor And Tmux Integration

- Explore how Codex should integrate with Barrett's live tmux and Neovim setup.
- Consider active Neovim instance handoff, session naming, worktree switching,
  and checkout visibility.
- Consider future `diffs.nvim` / `:Greview` integration for issue/PR inspection
  and review workflows.
- Keep this separate from the current `nvim` skill until the interaction model
  is designed.
