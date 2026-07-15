"""Shared client for the nvim-{commit,pr,edit,changes} skills.

Owns the parts every helper repeated: git/target resolution, locating the
project's mux Neovim server, and the RPC into `mux.skills`. The view/focus
logic lives in Lua (config/nvim/lua/mux/); these helpers just resolve a socket
and hand a payload across.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Iterable


class MuxError(Exception):
    """A user-facing failure; callers print it with their own prog prefix."""


# --- subprocess helpers ------------------------------------------------------


def maybe_output(args: Iterable[str]) -> str:
    proc = subprocess.run(
        list(args),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return proc.stdout.rstrip("\n") if proc.returncode == 0 else ""


def normalize_path(path: str | Path) -> Path:
    return Path(path).expanduser().resolve()


# --- git ---------------------------------------------------------------------


def git_rc(repo: Path, *args: str) -> int:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode


def workspace_root(path: Path) -> Path | None:
    root = maybe_output(["git", "-C", str(path), "rev-parse", "--show-toplevel"])
    if root:
        return normalize_path(root)
    cur = normalize_path(path)
    if cur.is_file():
        cur = cur.parent
    for parent in (cur, *cur.parents):
        if (parent / ".git").exists() or (parent / ".jj").exists():
            return parent
    return None


def git_root(path: Path) -> Path:
    return workspace_root(path) or path


def current_root() -> Path:
    return git_root(Path.cwd())


def worktree_for_branch(repo: Path, branch: str) -> Path | None:
    block: dict[str, str] = {}
    rows = maybe_output(
        ["git", "-C", str(repo), "worktree", "list", "--porcelain"]
    ).splitlines() + [""]
    for line in rows:
        if line.startswith("worktree "):
            block = {"path": line[len("worktree ") :]}
        elif line.startswith("branch "):
            block["branch"] = line[len("branch ") :]
        elif line == "" and block:
            if block.get("branch") == f"refs/heads/{branch}":
                return normalize_path(block["path"])
            block = {}
    return None


def resolve_target(base: Path, target: str | None) -> Path:
    """Resolve a --target (worktree path or branch checked out elsewhere) to a
    repo root, defaulting to `base`."""
    if not target:
        return base
    candidate = Path(target).expanduser()
    if candidate.is_dir():
        root = workspace_root(candidate)
        if root:
            return root
    wt = worktree_for_branch(base, target)
    if wt is None:
        raise MuxError(
            f"'{target}' is not a worktree path or a branch checked out under {base}"
        )
    return wt


# --- mux server discovery ----------------------------------------------------


def _server_cwd(socket: str) -> str:
    proc = subprocess.run(
        ["nvim", "--server", socket, "--remote-expr", "getcwd()"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def _runtime_dir() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(base) / "mux"


def _stem(root: Path) -> str:
    proc = subprocess.run(
        ["cksum"],
        check=False,
        input=str(root),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        raise MuxError("cksum failed")
    checksum = proc.stdout.split()[0]
    base = re.sub(r"[^A-Za-z0-9._-]", "_", root.name)
    base = re.sub(r"_+", "_", base).strip("_") or "project"
    return f"{base}-{checksum}"


def _socket_path(root: Path) -> Path:
    return _runtime_dir() / f"{_stem(root)}.sock"


def _server_root(socket: str) -> Path | None:
    proc = subprocess.run(
        [
            "nvim",
            "--server",
            socket,
            "--remote-expr",
            "luaeval('require([[mux.server]]).probe()')",
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return None
    try:
        decoded = json.loads(proc.stdout.strip())
    except json.JSONDecodeError:
        return None
    if not decoded.get("ok") or not isinstance(decoded.get("server"), dict):
        return None
    server_root = decoded["server"].get("root")
    return normalize_path(server_root) if server_root else None


def socket_for_root(root: Path, *, spawn: bool = True) -> str:
    """The project's mux Neovim server socket for `root`.

    Tries $NVIM (the fast path when run inside that server's terminal), then the
    live `mux list`, then spawns one with `mux ensure` (unless spawn=False).
    Raises MuxError if none can be found/created.
    """
    target = normalize_path(root)

    env = os.environ.get("NVIM")
    if (
        env
        and os.path.exists(env)
        and normalize_path(_server_cwd(env) or "/") == target
    ):
        return env

    sock = _socket_path(target)
    if sock.exists() and _server_root(str(sock)) == target:
        return str(sock)

    hint = "open it with mux first" if spawn else "not found"
    raise MuxError(f"no mux server for {target} ({hint})")


# --- RPC ---------------------------------------------------------------------


_EDIT_LUA = (
    '(function() local payload = vim.json.decode(table.concat(vim.fn.readfile(_A), "\\n")) or {}; '
    "local files = payload.files or {}; local items = payload.items or {}; local root = payload.root or vim.fn.getcwd(); local line = tonumber(payload.line); local column = tonumber(payload.column); "
    'local result, err = require("mux.view").call("edit", function() '
    'pcall(vim.fn.setreg, "/", ""); pcall(vim.fn.histdel, "search"); pcall(vim.cmd, "silent! nohlsearch"); pcall(vim.cmd, "silent! only"); '
    'if #files == 0 then vim.cmd("edit " .. vim.fn.fnameescape(root)); else vim.cmd("%argdelete"); local escaped = {}; for i, file in ipairs(files) do escaped[i] = vim.fn.fnameescape(file); end; vim.cmd("args " .. table.concat(escaped, " ")); vim.cmd("edit " .. vim.fn.fnameescape(files[1])); for i = 2, #files do vim.cmd("badd " .. vim.fn.fnameescape(files[i])); end; end; '
    'if #files == 1 and line and line >= 1 then local maxline = math.max(vim.api.nvim_buf_line_count(0), 1); local target_line = math.min(line, maxline); local text = vim.api.nvim_buf_get_lines(0, target_line - 1, target_line, false)[1] or ""; local target_column = math.max((column or 1) - 1, 0); target_column = math.min(target_column, #text); pcall(vim.api.nvim_win_set_cursor, 0, { target_line, target_column }); end; '
    'vim.fn.setqflist({}, "r", { title = "edit", items = items }); if #items > 1 then vim.cmd("botright copen"); vim.cmd("wincmd p"); else vim.cmd("cclose"); end; pcall(vim.cmd, "silent! nohlsearch"); vim.cmd("redraw!"); return true; end); '
    "if err then return vim.json.encode({ ok = false, error = err }); end; return vim.json.encode({ ok = result == true, count = #files }); end)()"
)

_REVIEW_LUA = (
    '(function() local payload = vim.json.decode(table.concat(vim.fn.readfile(_A), "\\n")) or {}; '
    'local base = payload.base or ""; local layout = payload.layout or "unified"; '
    'if base == "" then return vim.json.encode({ ok = false, error = "missing base" }); end; '
    'if layout ~= "unified" and layout ~= "stacked" and layout ~= "split" then layout = "unified"; end; '
    'local result, err = require("mux.view").call("vcs", function() vim.cmd("silent! only"); vim.cmd("Diff review ++layout=" .. layout .. " " .. base); if layout ~= "split" then vim.cmd("silent! only"); end; vim.cmd("redraw!"); return true; end); '
    "if err then return vim.json.encode({ ok = false, error = err }); end; return vim.json.encode({ ok = result == true }); end)()"
)


def _call_lua(socket: str, lua: str, payload: dict[str, Any]) -> dict[str, Any]:
    fd, name = tempfile.mkstemp(prefix=f"mux-rpc-{os.getuid()}-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
        expr = f"luaeval({_vim_str(lua)}, {_vim_str(name)})"
        proc = subprocess.run(
            ["nvim", "--server", socket, "--remote-expr", expr],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        out = proc.stdout.strip()
        if proc.returncode != 0 or not out:
            err = (proc.stderr or "").strip() or "no response from nvim server"
            raise MuxError(err)
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            raise MuxError(f"unexpected server reply: {out}")
    finally:
        try:
            os.unlink(name)
        except OSError:
            pass


def call(socket: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Invoke mux.skills.rpc(payload) on the server, returning its result dict.

    The payload is passed via a temp file (its path as luaeval's _A) so commit
    messages / PR bodies with quotes or apostrophes never need shell/vim
    escaping. Raises MuxError on transport failure.
    """
    if payload.get("op") == "edit":
        return _call_lua(socket, _EDIT_LUA, payload)
    if payload.get("op") == "review":
        return _call_lua(socket, _REVIEW_LUA, payload)
    return _call_lua(
        socket,
        'require([[mux.skills]]).rpc(vim.json.decode(table.concat(vim.fn.readfile(_A), "\\n")))',
        payload,
    )


def _vim_str(s: str) -> str:
    """Quote a string as a Vim single-quoted literal (doubling any quote)."""
    return "'" + s.replace("'", "''") + "'"
