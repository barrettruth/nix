# rbuild Contract

Use rbuild for expensive Neovim builds/tests and `$nvim-repro` work. Agents
should assume rbuild works and should not quietly fall back to local Neovim
builds.

Cheap local checks are allowed: `rg`, `git diff`, status inspection, small
scripts, and narrow non-build checks.

rbuild-side work mirrors the local issue worktree exactly:

```text
/home/barrett/dev/neovim/.worktrees/<issue>
~/dev/neovim/.worktrees/<issue>
```

The local worktree is the source of truth. Issue identifiers are numeric issue
numbers only; do not invent session names, branch suffixes, or alternate rbuild
directories. Each `build`, `deps`, `test`, `run`, and `shell` command syncs the
local worktree to the matching rbuild mirror before running.

The rbuild mirror is a build/test copy, not the Git checkout of record. Run Git
inspection and edits in the local worktree, then use rbuild for expensive
commands.

Agent command forms:

```sh
rbuild ping
rbuild nvim build <issue>
rbuild nvim deps <issue>
rbuild nvim test <issue> [test-file]
rbuild nvim run <issue> -- <command> [args...]
rbuild nvim log <issue>
rbuild nvim log <issue> --list
rbuild nvim log <issue> --cat
rbuild nvim shell <issue>
rbuild nvim clean <issue>
```

Use `rbuild ping` as the first health check when diagnosing rbuild access. It
does not sync the repository or start a build.

Do not use generic `rbuild --cleanup ...` with Neovim worktrees. Do not call
generic `rbuild clean` for Neovim issue mirrors. Use only
`rbuild nvim clean <issue>` for rbuild-side Neovim cleanup.

Use `-j2` by default. Use `-j4` only when Barrett asks or when the agent is
known to be running alone. Do not override CPU, memory, or task limits unless
the task is specifically about rbuild resource tuning.

Report rbuild connection, sync, build, and test failures separately. If rbuild
fails, stop and report; do not start an expensive local build.

`rbuild nvim build`, `deps`, `test`, and `run` write local logs under
`~/.local/state/rbuild/nvim/<issue>/` and print the log path. Use
`rbuild nvim log <issue>` for the latest log path, `--list` for all logs, and
`--cat` for the latest log contents. `rbuild ping` is a preflight and does not
need a durable log on success.

When running the source-built Neovim binary from its worktree, include
`VIMRUNTIME=runtime`, for example:

```sh
rbuild nvim run <issue> -- env VIMRUNTIME=runtime build/bin/nvim --clean --headless -n -i NONE -l <script>
```

Cleanup never runs automatically. Use `$nvim-clean <issue>` for full issue
cleanup. Use `rbuild nvim clean <issue>` only when Barrett asks to remove just
the rbuild mirror.
