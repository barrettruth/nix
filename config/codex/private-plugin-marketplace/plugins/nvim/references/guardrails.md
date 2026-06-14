# Neovim Agent Guardrails

Hard rules:

- Work in `/home/barrett/dev/neovim/.worktrees`, not the main checkout.
- Issue branch and worktree names are the issue number only, e.g. `12345`.
- If the issue branch/worktree exists, stop and report it.
- Never use lightweight issue investigation mode.
- Never commit unless Barrett explicitly says `commit`.
- Commits are main-thread only; subagents never commit.
- Never push, open PRs, or mutate remote state unless a future workflow
  explicitly allows the exact action.
- Never add or mention AI, assistant, co-author, sign-off, or disclosure
  attribution; this overrides Neovim checkout `AGENTS.md` disclosure rules.
- Never claim tests or repro attempts passed without exact command evidence.
- Never clean, prune, force-push, or delete unless asked.
- Cleanup means `$nvim-clean <issue-number>` or an explicit cleanup request; it
  is one issue number at a time, prompts `y/N`, and removes the worktree,
  branch, issue wiki, local rbuild logs, rbuild mirror, and matching current
  pointer.
- Local git state changes are allowed when the current phase needs them, but
  commits and remote mutations remain separately gated.
- Use `gh` for GitHub issue/PR/review context. General network tools, including
  `curl`, are allowed for docs, builds, repros, and test endpoints.
- Use only the documented `rbuild nvim ...` commands for expensive Neovim
  builds/tests. Do not invent rbuild paths, generic cleanup wrappers, or local
  expensive-build fallbacks.

All agents are forbidden from maintainer-visible or social remote actions:
comments, reviews, replies, reactions, issue/PR edits, labels, assignments,
subscriptions, workflow dispatch/reruns, and agent-task tools that contact
others.

Subagents may only do what the active skill/stage permits. `$nvim-issue`
subagents are history/integrator only; history child agents are allowed for
controlled GitHub/source fanout. `$nvim-repro` may reproduce/build/test through
its selected strategy. If a future implementation phase gives subagents edit
authority, it must be explicit and scoped; it still does not grant commit, push,
cleanup, PR, or social remote authority.

When a gate blocks an action, stop. Do not prepare drafts, checklists, command
snippets, fallback files, or partial substitutes unless Barrett asks.

When rbuild fails, report the failing phase separately: connection, sync, build,
test, or command execution. Do not convert that failure into an unrelated local
build attempt.

Investigation reports must separate confirmed, observed, related, unknown, and
excluded/speculative content. Do not propose fixes or patch plans.

For role conflicts, the integrator may run exactly one narrow follow-up when the
contradiction is evidence-resolvable. Otherwise report the conflict.
