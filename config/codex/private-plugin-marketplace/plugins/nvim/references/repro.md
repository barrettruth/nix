# Reproduction Contract

Use this for `$nvim-repro`. This is not issue intake and not a fix workflow.

Inputs:

- Explicit issue number only.
- Require an existing issue wiki and worktree from `$nvim-issue`; do not create
  setup if missing.
- Require the worktree `.codex/issue-wiki` pointer, validate its `issue`,
  `wiki`, and `index` values match the requested issue, and require
  `sources/github/issue.json` plus `sources/github/issue.md`.
- Run `../../scripts/repro-preflight.py <issue>` before spawning the reproducer.
  If it fails, stop. Use its printed paths; do not rediscover them manually.
- Coordinator selects exactly one strategy from the allowlist, then spawns one
  isolated reproducer subagent.
- If the raw issue is not a bug claim, for example a feature request or
  behavior question with no erroneous runtime behavior to exercise, write
  `Status: not applicable` in `evidence/repro.md` and stop without Spark.
- Coordinator prompts must be short: issue number, paths, references to read,
  owned write paths, and hard prohibitions. Do not paste this full contract into
  the subagent prompt.
- The reproducer reads only the raw issue snapshot, worktree, `guardrails.md`,
  `spark.md`, and this file.
- Do not read Codex memory for `$nvim-repro`.
- Do not read `evidence/history.md`, `report.md`, or coordinator conclusions
  unless Barrett explicitly asks for a history-informed repro pass.

Owned paths:

```text
<worktree>/.codex/repros/script/repro.lua
<wiki>/evidence/repro.md
```

Strategy allowlist:

- `script`: headless Lua script only.

Use `script` for now. If the issue needs TUI, RPC,
`--server`, terminal, job-control, UI attach, LSP timing, or another strategy
that cannot be represented by this script shape, stop and write that reason in
`evidence/repro.md`; do not improvise a new strategy.

For script strategy, start from `../templates/repro-script.lua`. Keep the marker,
message scan, and final status shape; replace only the issue-specific section.

Run shape:

```sh
spark nvim build <issue>
spark nvim log <issue>
spark nvim run <issue> -- env VIMRUNTIME=runtime build/bin/nvim --clean --headless -n -i NONE -l .codex/repros/script/repro.lua
spark nvim log <issue>
```

Source-tree Neovim runs must use `VIMRUNTIME=runtime`.

Qualify reproduced status by strategy, e.g. `reproduced via script strategy`;
do not imply native TUI/user-path reproduction unless that strategy was used.

To claim not reproduced, prove the intended path ran. The script must emit
markers for each critical event it relies on, such as UI presence, autocmd
entry, buffer delete, LSP detach, diagnostic event, and captured messages. If
those markers are missing, use `Status: blocked` and explain which path was not
exercised.

Do not do open-ended exploration. After the first credible reproduction, stop
and write `evidence/repro.md`. If reproduction is not applicable, or if the
script strategy cannot reproduce after a small bounded set of attempts, stop
and record why.

`evidence/repro.md` must contain:

- `Status`: reproduced, not reproduced, blocked, or not applicable.
- Repro file path.
- Exact build/run commands.
- `spark nvim log <issue>` paths for each build/run/test command.
- Every Spark log path for every attempt mentioned in prose.
- Minimal observed output or error excerpt.
- What was tried and why the role stopped.

No solutions, patch plans, or fix recommendations.

After the subagent finishes, the coordinator updates only:

- `index.md`: reproduction status, link to `evidence/repro.md`, and important
  Spark log links.
- `log.md`: one short append-only entry with strategy and status.

Do not update `report.md` or `sources.md` during `$nvim-repro`.
