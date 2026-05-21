# Reproduction Contract

Use this for the `$nvim-issue` reproducer role. This is not a fix workflow.

Inputs:

- Read only the raw issue snapshot, worktree, `guardrails.md`, `spark.md`, and
  this file.
- Do not read `evidence/history.md`, `report.md`, or coordinator conclusions.

Owned paths:

```text
<worktree>/.codex/repros/script/repro.lua
<worktree>/.codex/repros/script/control.lua
<wiki>/evidence/repro.md
```

Current strategy: headless Lua script only. If the issue needs TUI, RPC,
`--server`, terminal, job-control, UI attach, LSP timing, or another strategy
that cannot be represented by this script shape, stop and write that reason in
`evidence/repro.md`; do not improvise a new strategy.

Run shape:

```sh
spark nvim build <issue>
spark nvim log <issue>
spark nvim run <issue> -- build/bin/nvim --clean --headless -n -i NONE -l .codex/repros/script/repro.lua
spark nvim log <issue>
```

To claim reproduced, include both a failure run and one relevant control run.
Use `.codex/repros/script/control.lua` when the control needs a separate file;
otherwise record the exact command variation. If there is no meaningful control,
mark the status as not yet reproduced and stop.

Do not do open-ended exploration. After the first credible failure plus control,
stop and write `evidence/repro.md`. If the script strategy cannot reproduce
after a small bounded set of attempts, stop and record what was tried.

`evidence/repro.md` must contain:

- `Status`: reproduced, not reproduced, or blocked.
- Repro file path and control file path if used.
- Exact build/run/control commands.
- `spark nvim log <issue>` paths for each build/run/test command.
- Minimal observed output or error excerpt.
- What was tried and why the role stopped.

No solutions, patch plans, or fix recommendations.
