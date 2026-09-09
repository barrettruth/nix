---
name: aerospace
description: Use when diagnosing, explaining, configuring, or operating the AeroSpace macOS window manager or its `aerospace` CLI, including layouts, overlapping windows, focus, workspaces, monitors, app placement, callbacks, or this Nix-managed setup. Do not use for aviation, aerospace engineering, or unrelated window managers.
---

# aerospace

Work from live AeroSpace state when explaining behaviour and from the Nix source
when changing persistent configuration. AeroSpace workspaces are virtual: they
are not macOS Spaces, and AeroSpace manages top-level windows rather than tabs
inside an application.

## Establish the state

- Treat the installed client as the source of truth. Start with
  `aerospace --version`. Check `aerospace <command> --help` before relying on a
  flag.
- Use `aerospace config --config-path` to find the active generated TOML. Read
  it when needed, but never edit it: it is an immutable Nix store file here.
- Prefer the structured `--json` output of `list-apps`, `list-monitors`,
  `list-windows`, and `list-workspaces`. Add `--format` with only the fields the
  task needs; the default window format includes window titles.
- Use focused or visible workspace/monitor filters unless the question actually
  spans all workspaces or monitors.
- For a concrete symptom or common operation, read only the matching section of
  [references/snippets.md](references/snippets.md).

For a question such as "why are these windows overlapping?", inspect and
explain without changing the live layout. If the user asks to fix live state,
prefer an explicit `--window-id` or `--workspace` target. If they ask for a
persistent change, edit the Nix source. Do not turn a configuration question
into a live window operation or rebuild.

## This setup

The configuration repo is `~/.config/nix` even when the current working
directory is elsewhere.

- `modules/darwin/barrett/workstation.nix` owns `services.aerospace.settings`,
  the shared app schema, and `services.skhd.skhdConfig`.
- `hosts/<host>/configuration.nix` extends the app and floating-app lists for a
  particular Mac.
- `barrett.mac.apps` drives app launch bindings, login agents, and workspace
  routing. `barrett.mac.floatingApps` drives floating callbacks.
- `skhd` owns the keyboard bindings. An empty AeroSpace `mode` table is expected.
- nix-darwin starts AeroSpace as a keep-alive user LaunchAgent. Keep
  `start-at-login = false`; do not add an AeroSpace login path beside launchd.

Run Nix repository commands through `direnv exec .`. When a requested persistent
change must be activated, use the repository's `just rebuild-<host>` recipe for
the actual host. Never invoke `darwin-rebuild` directly.

## Configuration semantics

- `aerospace config` currently exposes only `mode.*`; it cannot replace reading
  the generated TOML for top-level settings.
- Missing `config-version` means version 1. Use the dry-run reload snippet to
  surface compatibility warnings.
- `on-window-detected` is ordered and normally stops after the first matching
  callback. Combine actions in one `run`, or use `check-further-callbacks` when
  one window must match multiple rules.
- Bundle IDs are more reliable than app names for routing. Obtain them from
  `list-apps` or application metadata rather than guessing.
- Window titles can initialize after detection, so title rules may miss a newly
  created window.
- Callback commands inherit the originating window through
  `AEROSPACE_WINDOW_ID`; a later command in the same callback still targets that
  window even if focus changes.
- Empty non-persistent workspaces disappear. Do not infer the configured
  workspace vocabulary from the current `list-workspaces` output alone.

## CLI boundaries

Read-only commands include the `list-*` family, `config`, `echo`, `test`, and
`test-not`. `reload-config --dry-run` parses without applying.

Commands such as `workspace`, `focus`, `layout`, `move*`, `resize`, `swap`,
`fullscreen`, `flatten-workspace-tree`, `balance-sizes`, `close`, `enable`,
`mode`, `trigger-binding`, and non-dry-run `reload-config` change live state.
`eval` can contain either kind, so inspect its whole expression before running
it. `subscribe` blocks while listening for events; use it only for an explicit
monitoring task.

AeroSpace's expression language supports `;`, `&&`, `||`, `|`, and parentheses.
It is not POSIX shell: `&&` binds more tightly than `||`, and pipelines use
pipefail semantics.

Report the observed cause and the smallest relevant correction. Distinguish a
one-time live correction from the Nix change that makes it persistent.
