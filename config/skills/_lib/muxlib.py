"""Shared client for the nvim-{commit,pr,edit,changes} skills.

Owns the parts every helper repeated: git/target resolution, locating the
project's mux Neovim server, and the RPC into `mux.skills`. The view/focus
logic lives in Lua (config/nvim/lua/mux/); these helpers just resolve a socket
and hand a payload across.
"""

from __future__ import annotations

import json
import os
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
        raise MuxError(f"'{target}' is not a worktree path or a branch checked out under {base}")
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


def socket_for_root(root: Path, *, spawn: bool = True) -> str:
    """The project's mux Neovim server socket for `root`.

    Tries $NVIM (the fast path when run inside that server's terminal), then the
    live `mux list`, then spawns one with `mux ensure` (unless spawn=False).
    Raises MuxError if none can be found/created.
    """
    target = normalize_path(root)

    env = os.environ.get("NVIM")
    if env and os.path.exists(env) and normalize_path(_server_cwd(env) or "/") == target:
        return env

    listing = maybe_output(["mux", "list"])
    for line in listing.splitlines():
        fields = line.split("\t")
        if len(fields) < 3:
            continue
        cwd, sock, status = fields[:3]
        if status == "live" and sock and normalize_path(cwd) == target:
            if os.path.exists(sock):
                return sock

    if spawn:
        sock = maybe_output(["mux", "ensure", str(target)])
        sock = sock.splitlines()[0].strip() if sock else ""
        if sock and os.path.exists(sock):
            return sock

    raise MuxError(f"no mux server for {target} (is mux running?)")


# --- RPC ---------------------------------------------------------------------


def call(socket: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Invoke mux.skills.rpc(payload) on the server, returning its result dict.

    The payload is passed via a temp file (its path as luaeval's _A) so commit
    messages / PR bodies with quotes or apostrophes never need shell/vim
    escaping. Raises MuxError on transport failure.
    """
    fd, name = tempfile.mkstemp(prefix=f"mux-rpc-{os.getuid()}-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
        expr = (
            "luaeval('require([[mux.skills]]).rpc("
            'vim.json.decode(table.concat(vim.fn.readfile(_A), "\\n")))\', '
            f"{_vim_str(name)})"
        )
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


def _vim_str(s: str) -> str:
    """Quote a string as a Vim single-quoted literal (doubling any quote)."""
    return "'" + s.replace("'", "''") + "'"
