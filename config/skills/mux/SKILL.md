---
name: mux
description: Talk to a running mux Neovim session over its socket — resolve it, read its state, send it commands, restart it. Use when a task needs to inspect or exercise the editor itself rather than open files in it.
---

# mux

A mux project has one Neovim server on a deterministic socket. Everything here
goes through that socket.

## Socket

```sh
python3 ~/.config/nix/config/skills/mux/scripts/socket.py [--root <repo-root>]
```

Prints the socket, or exits 1 naming the project it found no server for.

## Read

`--remote-expr` evaluates and waits for an answer, which comes once the session
is not itself waiting on input. Give a read a timeout and take a timeout to
mean it is waiting.

```sh
timeout 10 nvim --server "$sock" --remote-expr 'bufname("%")'
```

## Command

Run Ex commands through the RPC helper. It executes inside the named mux view
even when another view is focused, waits for completion, restores the user's
focus, and prints the view and buffer it acted on.

```sh
python3 ~/.config/nix/config/skills/mux/scripts/command.py \
  --root <repo-root> --view edit 'lsp restart bazel_ls'
python3 ~/.config/nix/config/skills/mux/scripts/command.py \
  --root <repo-root> --view vcs 'Git status'
```

Do not follow `nvim-edit` with `--remote-send`: opening a file populates the
`edit` view but deliberately leaves the user's focused view unchanged.

## Keys

`--remote-send` targets Neovim's currently focused window; it cannot select a
mux view. Use it only when the task is specifically to send literal keys to the
confirmed current window, never as a way to run an Ex or Lua command. To leave
insert, command-line, or terminal mode, use `<C-\><C-N>`; `<Esc>` is delivered
to the program inside a terminal buffer.

```sh
nvim --server "$sock" --remote-expr '[bufname("%"), mode()]'
nvim --server "$sock" --remote-send '<C-\><C-N>'
```

## Lua

Past a single Ex command, add a narrow operation to
`config/skills/_lib/driver.lua` and invoke it with `muxlib.call`. This gives
structured arguments and deterministic view targeting. Do not inject
`:luafile` with `--remote-send`.

## Restart

`:restart` rebinds the same socket and keeps the working directory, and is how
a session takes up changed plugin code. Read the modified buffers first, then
poll the socket until it answers again.

```sh
nvim --server "$sock" --remote-expr 'len(getbufinfo({"bufmodified":1}))'
nvim --server "$sock" --remote-send '<C-\><C-N>:restart<CR>'
```

## Rules

- Opening files is `nvim-edit`, review is `nvim-review`, commits are
  `nvim-commit`. This skill is the session itself.
- Commands that must run in a named view use `command.py`, never
  `--remote-send`.
- Say which buffer the session is left showing.
