# Spark Contract

Use Spark for expensive Neovim builds/tests and parallel reproducer work. Agents
should assume Spark works and should not quietly fall back to local Neovim
builds.

Cheap local checks are allowed: `rg`, `git diff`, status inspection, small
scripts, and narrow non-build checks.

Spark-side work mirrors the local issue worktree exactly:

```text
/home/barrett/dev/neovim/.worktrees/<issue>
~/dev/neovim/.worktrees/<issue>
```

The local worktree is the source of truth. Issue identifiers are numeric issue
numbers only; do not invent session names, branch suffixes, or alternate Spark
directories. Each `build`, `deps`, `test`, `run`, and `shell` command syncs the
local worktree to the matching Spark mirror before running.

The Spark mirror is a build/test copy, not the Git checkout of record. Run Git
inspection and edits in the local worktree, then use Spark for expensive
commands.

Agent command forms:

```sh
spark ping
spark nvim build <issue>
spark nvim deps <issue>
spark nvim test <issue> [test-file]
spark nvim run <issue> -- <command> [args...]
spark nvim shell <issue>
spark nvim clean <issue>
```

Use `spark ping` as the first health check when diagnosing Spark access. It
does not sync the repository or start a build.

Do not use generic `spark --cleanup ...` with Neovim worktrees. Do not call
generic `spark clean` for Neovim issue mirrors. Use only
`spark nvim clean <issue>` for Spark-side Neovim cleanup.

Use `-j2` by default. Use `-j4` only when Barrett asks or when the agent is
known to be running alone. Do not override CPU, memory, or task limits unless
the task is specifically about Spark resource tuning.

Report Spark connection, sync, build, and test failures separately. If Spark
fails, stop and report; do not start an expensive local build.

Cleanup never runs automatically. `spark nvim clean <issue>` removes only the
Spark mirror for that issue after showing the exact path, disk usage, and
prompting `y/N`.
