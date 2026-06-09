# mux — tmux→Neovim multiplexer migration (persistent tracker)

Neovim is the multiplexer: one `nvim --headless --listen <sock>` server per
project (git root), a Ghostty client attached via `--remote-ui`, project switch
via `:connect`. Shell launcher: `scripts/mux`. In-nvim brain:
`config/nvim/lua/mux/init.lua` (activated only on mux servers via `NMUX=1` +
`-c require('mux').setup()`; inert in the daily/tmux nvim).

## Done & verified

- `scripts/mux`: ensure/attach/list/kill, per-project socket, stale-socket
  cleanup (#30123); `-c` activates mux + sets `NMUX=1`; defaults to real config.
- `mux.lua`: tagged-tab views — `edit`(eager) + `ai/vcs/run/build/test`(lazy);
  ephemeral (ai/vcs/run close on exit) vs persistent (build/test); just-recipe
  gating; async fzf-lua project picker `<leader>m`; role keys
  `<leader>{e,a,v,r,b,t}`; `:bd`/`:bw` rebind frees `<leader>b` for build.
- Picker theme-adapts for free (rides the existing fzf reload mechanism).
- Marker legend: `*` current / `o` running / ` ` cold.
- Session persistence: per-project cwd-keyed `mksession` (terminals restored by
  re-running their command), view tags persisted via `g:MuxViews` and re-applied
  on restore, autosave every 600s; validated via hard-kill→respawn round-trip.
- All four agent skills (`nvim-edit`/`commit`/`pr`/`changes`) drive the project
  server directly when `$NVIM` is set (skip tmux discovery); prod-safe fallback
  intact; edit/commit/pr validated against live servers, changes renders too.
- `$EDITOR`/`$GIT_EDITOR` routing in zshrc (gated on `$NVIM`) → parent server via
  `nvim --remote-wait`; `gitcommit` ftplugin `bufhidden=wipe` so `:wq` unblocks.
- Lint clean (stylua/selene/shellcheck/black); demoed live on Hyprland ws9.

## Validated facts (don't re-derive)

- `mksession` with `terminal` in `sessionoptions` RESTORES terminals by re-running
  their `term://` command (no scrollback) — this is what we want.
- `mksession` does NOT persist tabpage-local vars → view tags must be re-applied
  manually on restore.
- The `globals` sessionoption saves only globals that start uppercase AND contain
  a lowercase letter (e.g. `g:MuxViews`); all-caps names are NOT saved (those go to
  shada, which does NOT survive a crash) — so persist `tabnr→view` as `g:MuxViews`
  inside the session file. (Earlier all-caps test only "worked" via shada — wrong.)
- tmux-continuum interval is in MINUTES; this config uses `10` → autosave target
  = 600s (continuum also delays the first save by one interval).

## Session persistence — DONE (above); one open follow-up

- Restoring persistent task terminals (`just build`/`test`) re-runs the command on
  restore; decide later whether to skip re-running task-view terminals.

## Remaining — statusline / tabline

- Show current project + active view name (the deferred "project label"); pick
  native statusline segment vs. tabline; keep ascii, no icons.

## Agents / skills sweep — DONE; small remainders

- Seam = `$NVIM` (nvim auto-sets it in a server's `:terminal` children) → no
  launcher change, no-op under tmux. Done in all four skills. (Skills are not in
  any CI linter scope: `_python-scripts` globs `scripts/` only.)
- Remaining: `nvim-changes` worktree review (target root != server cwd) still
  falls back to tmux — needs a per-worktree-server decision.
- Remaining: retire old tmux `mux` script paths during cutover; broader tmux grep.
- Remaining: end-to-end with a real devin agent inside an mux `:terminal`.

## Remaining — launcher / startup

- Decide the zsh function name and whether it takes args; define its relationship
  to `scripts/mux` (thin wrapper? + a shell fzf project-picker keybind?).
- Wire Hyprland startup (flip `exec-once … -e mux` → mux) — promotion step.
- Promotion to Nix: drop tmux packages/plugins once fully cut over.

## Deferred

- Project-switch recency slots / "last project" toggle (Q10).
- Tab-local buffer scoping (scope.nvim) — decided NO for now.
- Fancy/CAS terminal scrollback reconstruction — explicitly dropped.

## Locked decisions

- One nvim server per project; switch via `:connect`; one visible client.
- Views = tagged tabs; `edit` eager, rest lazy/find-or-create.
- Picker = fzf-lua on `<leader>m`; no separate "open" role menu.
- mux lives only on mux servers (NMUX=1 gate); daily nvim untouched.
- No appname profile / plugin-sharing (would reinstall plugins) — use real config.
