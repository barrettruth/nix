# Neovim Agent Workflow Backlog

Planning notes only. This file is not part of the `nvim` skill and does not
grant agents permission to commit, push, clean, publish, or interact remotely.

Keep setup reproducible from this Nix config. Do not treat personal Codex paths
such as `~/.agents` as part of the workflow setup; use the tracked
`config/codex/private-plugin-marketplace` marketplace and `config/codex/config.toml`.

## Target Stage Pipeline

- Identify issue and create the isolated worktree/wiki setup.
- Explore and report the issue before proposing fixes; reproduction is a
  separate stage after intake.
- Explain on demand at any stage: after issue investigation, before planning,
  after implementation, or after verification.
- Plan exactly three outcome options before implementation, then recommend one.
- Implement only after Barrett chooses an outcome.
- Verify and review in a loop, including Barrett-requested revisions.
- Commit only after the review stage. Prefer a visible Fugitive commit-buffer
  workflow in the mux `git` window; direct commits remain separately gated.
- PR workflow comes later and should use Barrett's Neovim tooling, especially
  `forge.nvim`; remote-visible review replies and PR updates need their own
  workflow.

## Refactor Order

1. Stage map and shared vocabulary.
2. Reproduction playbooks and Spark proof artifacts.
3. Explain and plan/outcome workflows.
4. Implementation and verification loops.
5. Review checkpoint before commit.
6. Fugitive/mux commit preparation.
7. PR and review-response workflow through `forge.nvim`.

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
- Build out the missing reproducer-facing Spark guidance: how to build, locate
  the built `nvim`, set runtime paths, run commands under `spark nvim run`, and
  consume `spark nvim log` output without falling back to expensive local
  builds.
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

- Expand the initial `$nvim-repro` workflow beyond the current `script`
  strategy.
- Do not rely on `$nvim-verify` for issue reproduction; verification is for
  implementation-phase checks, while repro needs its own playbooks and prompts.
- Headless, UI, TUI, RPC, `--server`, job-control, terminal, LSP, and network
  reproduction patterns.
- Reproducer agents need concrete examples for shaping minimal scripts, choosing
  `spark nvim build/test/run`, preserving exact command evidence, and writing
  `evidence/repro.md`.
- Repro reports must include a short copy-paste rerun path near the top and
  persist the runnable harness files. Do not leave only a "command shape" that
  depends on hidden shell variables or transient `/tmp` payloads.
- Once credible failure evidence exists, the reproducer should stop
  experimentation and write `evidence/repro.md`; long post-repro exploration
  needs explicit permission or a bounded next question.
- Repro playbooks need an explicit calibration stop: if the agent cannot see a
  credible repro path for an issue of this complexity, it should say so, record
  what is missing, and stop for Barrett to revise the approach.
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
