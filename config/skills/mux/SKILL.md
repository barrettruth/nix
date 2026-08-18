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

## Send

`--remote-send` delivers keys and returns at once. Lead with `<Esc>` so they
land in normal mode, and send `<Esc>` alone to give a waiting session the
keypress it is after: it changes nothing when nothing is waiting, where `<CR>`
opens whatever is under the cursor.

```sh
nvim --server "$sock" --remote-send '<Esc>:CI<CR>'
```

A send returns before the command it sent has finished. Poll for what it
produces.

## Lua

Past a single value, put the Lua in a file and take the result from one. This
also settles the quoting, `--remote-expr` being Vimscript through a shell,
where a dictionary key carries quotes of its own (`{'name': 'Title'}`).

```sh
cat > /tmp/probe.lua <<'EOF'
vim.fn.writefile({ vim.api.nvim_buf_get_name(0) }, '/tmp/probe.out')
EOF
nvim --server "$sock" --remote-send '<Esc>:luafile /tmp/probe.lua<CR>'
```

## Restart

`:restart` rebinds the same socket and keeps the working directory, and is how
a session takes up changed plugin code. Read the modified buffers first, then
poll the socket until it answers again.

```sh
nvim --server "$sock" --remote-expr 'len(getbufinfo({"bufmodified":1}))'
nvim --server "$sock" --remote-send '<Esc>:restart<CR>'
```

## Rules

- Opening files is `nvim-edit`, review is `nvim-review`, commits are
  `nvim-commit`. This skill is the session itself.
- Say which buffer the session is left showing.
