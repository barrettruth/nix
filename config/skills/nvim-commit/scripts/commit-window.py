#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, NoReturn

SESSION_PROJECT_PATH_OPTION = "@mux-project-path"
VCS_WINDOW_NAME = "vcs"

# Open fugitive's commit status and a fresh commit buffer in the vcs window.
STATUS_LUA = "\n".join(
    [
        "pcall(vim.cmd, 'silent! only')",
        "local b = vim.fn.bufnr('COMMIT_EDITMSG')",
        "if b > 0 then pcall(vim.cmd, 'silent! bwipeout! ' .. b) end",
        "pcall(vim.cmd, 'silent! Git')",
        "pcall(vim.cmd, 'silent! only')",
        "pcall(vim.cmd, 'Git commit')",
    ]
)


def run(
    args: Iterable[str], *, check: bool = True, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def maybe_output(args: Iterable[str]) -> str:
    proc = subprocess.run(
        list(args),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return proc.stdout.rstrip("\n") if proc.returncode == 0 else ""


def tmux(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["tmux", *args], check=check)


def tmux_output(*args: str) -> str:
    return maybe_output(["tmux", *args])


def in_tmux() -> bool:
    if not os.environ.get("TMUX"):
        return False
    return (
        subprocess.run(
            ["tmux", "display-message", "-p", "#{session_name}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def normalize_path(path: str | Path) -> Path:
    return Path(path).expanduser().resolve()


def die(message: str) -> NoReturn:
    print(f"commit-window: {message}", file=sys.stderr)
    raise SystemExit(2)


def git_rc(repo: Path, *args: str) -> int:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode


def git_root(path: Path) -> Path:
    root = maybe_output(["git", "-C", str(path), "rev-parse", "--show-toplevel"])
    return normalize_path(root) if root else path


def current_root() -> Path:
    if in_tmux():
        session = tmux_output("display-message", "-p", "#{session_name}")
        project = tmux_output(
            "show-options", "-qv", "-t", session, SESSION_PROJECT_PATH_OPTION
        )
        if project:
            return git_root(normalize_path(project))
        pane = tmux_output("display-message", "-p", "#{pane_current_path}")
        return git_root(normalize_path(pane))
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


def resolve_root(base: Path, target: str | None) -> Path:
    if not target:
        return base
    candidate = Path(target).expanduser()
    if candidate.is_dir() and git_rc(candidate, "rev-parse", "--is-inside-work-tree") == 0:
        top = maybe_output(["git", "-C", str(candidate), "rev-parse", "--show-toplevel"])
        return normalize_path(top) if top else candidate.resolve()
    wt = worktree_for_branch(base, target)
    if wt is None:
        die(f"'{target}' is not a worktree path or a branch checked out under {base}")
    return wt


@dataclass(frozen=True)
class Window:
    name: str
    index: str
    command: str
    pane_pid: str
    path: Path


def list_windows(session: str) -> list[Window]:
    fmt = (
        "#{window_name}\t#{window_index}\t#{pane_current_command}"
        "\t#{pane_pid}\t#{pane_current_path}"
    )
    windows: list[Window] = []
    for line in tmux_output("list-windows", "-t", session, "-F", fmt).splitlines():
        name, index, command, pane_pid, path = (line.split("\t") + [""] * 5)[:5]
        windows.append(
            Window(name, index, command, pane_pid, normalize_path(path or "/"))
        )
    return windows


def find_vcs_window(session: str, root: Path) -> Window | None:
    for window in list_windows(session):
        if window.name == VCS_WINDOW_NAME and window.command == "nvim":
            if window.path == root:
                return window
    return None


def pane_command(target: str) -> str:
    return tmux_output("display-message", "-p", "-t", target, "#{pane_current_command}")


def wait_for_nvim(target: str, timeout: float = 6.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if pane_command(target) == "nvim":
            return True
        time.sleep(0.05)
    return pane_command(target) == "nvim"


def process_children(pid: str) -> list[str]:
    children: list[str] = []
    queue: deque[str] = deque([pid])
    while queue:
        current = queue.popleft()
        child_file = Path("/proc") / current / "task" / current / "children"
        try:
            direct = child_file.read_text(encoding="utf-8").split()
        except OSError:
            direct = []
        for child in direct:
            children.append(child)
            queue.append(child)
    return children


def nvim_socket_for_window(window: Window, root: Path) -> str:
    pids = [window.pane_pid, *process_children(window.pane_pid)]
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    candidates: list[Path] = []
    for pid in pids:
        if not pid:
            continue
        candidates.append(runtime / f"nvim.{pid}.0")
        candidates.append(Path(tempfile.gettempdir()) / f"nvim-{pid}.sock")
    for socket in candidates:
        if not socket.exists():
            continue
        proc = subprocess.run(
            ["nvim", "--server", str(socket), "--remote-expr", "getcwd()"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        if proc.returncode == 0 and normalize_path(proc.stdout.strip()) == root:
            return str(socket)
    return ""


def wait_for_socket(
    session: str, index: str, root: Path, timeout: float = 6.0
) -> tuple[Window | None, str]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        window = next((w for w in list_windows(session) if w.index == index), None)
        if window and window.command == "nvim":
            socket = nvim_socket_for_window(window, root)
            if socket:
                return window, socket
        time.sleep(0.1)
    return None, ""


def ensure_vcs_window(session: str, root: Path) -> tuple[Window, str]:
    window = find_vcs_window(session, root)
    if window is None:
        index = tmux_output(
            "new-window",
            "-d",
            "-P",
            "-F",
            "#{window_index}",
            "-t",
            f"{session}:",
            "-c",
            str(root),
            "-n",
            VCS_WINDOW_NAME,
            "nvim",
        )
        if not index:
            die("could not create vcs window")
        if not wait_for_nvim(f"{session}:{index}"):
            die("nvim did not start in the vcs window")
    else:
        index = window.index
    resolved, socket = wait_for_socket(session, index, root)
    if resolved is None or not socket:
        die("could not reach the nvim server in the vcs window")
    return resolved, socket


def remote_expr(socket: str, expr: str) -> tuple[int, str]:
    proc = subprocess.run(
        ["nvim", "--server", socket, "--remote-expr", expr],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return proc.returncode, proc.stdout.strip()


def run_lua(socket: str, lua: str) -> bool:
    fd, name = tempfile.mkstemp(prefix=f"commit-{os.getuid()}-", suffix=".lua")
    os.close(fd)
    script = Path(name)
    try:
        script.write_text(lua + "\n", encoding="utf-8")
        expr = f"execute('luafile ' . fnameescape({json.dumps(str(script))}))"
        rc, _ = remote_expr(socket, expr)
        return rc == 0
    finally:
        try:
            script.unlink()
        except OSError:
            pass


def wait_for_commit_buffer(socket: str, timeout: float = 6.0) -> bool:
    # Wait until fugitive's async :Git commit buffer exists AND is writable, so
    # a stale/half-open COMMIT_EDITMSG never gets populated.
    expr = (
        "bufloaded('COMMIT_EDITMSG') ? "
        "getbufvar(bufnr('COMMIT_EDITMSG'), '&modifiable') : 0"
    )
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rc, out = remote_expr(socket, expr)
        if rc == 0 and out == "1":
            return True
        time.sleep(0.1)
    return False


def populate_lua(message_lines: list[str]) -> str:
    msg = json.dumps(json.dumps(message_lines))
    return "\n".join(
        [
            f"local msg = vim.json.decode({msg})",
            "local b = vim.fn.bufnr('COMMIT_EDITMSG')",
            "if b < 1 then return end",
            "local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)",
            "local cut = #lines",
            "for i = 1, #lines do",
            "  if lines[i]:sub(1, 1) == '#' then cut = i - 1 break end",
            "end",
            "local head = {}",
            "for _, line in ipairs(msg) do head[#head + 1] = line end",
            "head[#head + 1] = ''",
            "vim.api.nvim_buf_set_lines(b, 0, cut, false, head)",
            "for _, w in ipairs(vim.fn.win_findbuf(b)) do",
            "  pcall(vim.api.nvim_win_set_cursor, w, { 1, 0 })",
            "end",
        ]
    )


def read_message(args: argparse.Namespace) -> list[str]:
    if args.file:
        text = (
            sys.stdin.read()
            if args.file == "-"
            else Path(args.file).expanduser().read_text(encoding="utf-8")
        )
    elif args.message:
        text = "\n".join(args.message)
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        die("no commit message: pass -F <file>, -m <line>, or pipe it on stdin")
    text = text.rstrip("\n")
    if not text.strip():
        die("empty commit message")
    return text.split("\n")


def ensure_staged(
    root: Path, stage: list[str], dry_run: bool
) -> tuple[bool, list[str]]:
    already_staged = git_rc(root, "diff", "--cached", "--quiet") == 1
    if already_staged:
        return True, []
    if not stage:
        die("nothing staged and no --stage paths given (never use git add -A)")
    paths = [str(normalize_path(p)) for p in stage]
    if not dry_run:
        run(["git", "-C", str(root), "add", "--", *paths], check=False)
        if git_rc(root, "diff", "--cached", "--quiet") != 1:
            die("staging produced no changes; check the --stage paths")
    return False, paths


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="commit-window",
        description=(
            "Open a fugitive commit in the mux vcs window, pre-filled with a "
            "drafted message, without focusing it."
        ),
    )
    parser.add_argument(
        "-F", "--file", default=None, help="read message from file ('-' = stdin)"
    )
    parser.add_argument(
        "-m", "--message", action="append", default=None, help="message line(s)"
    )
    parser.add_argument(
        "--stage",
        nargs="*",
        default=[],
        help="files to stage iff nothing is staged (never git add -A)",
    )
    parser.add_argument(
        "--root", type=Path, default=None, help="base repo (default: current project)"
    )
    parser.add_argument(
        "--target",
        default=None,
        help="branch or worktree path the changes live in (default: base repo)",
    )
    parser.add_argument(
        "--session", default=None, help="tmux session (default: current)"
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="print the plan; do not stage or touch tmux/nvim",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    base = args.root.resolve() if args.root else current_root()
    root = resolve_root(base, args.target)
    if git_rc(root, "rev-parse", "--is-inside-work-tree") != 0:
        die(f"not a git repository: {root}")

    message_lines = read_message(args)
    subject = message_lines[0]
    already_staged, staged = ensure_staged(root, args.stage, args.dry_run)

    if args.dry_run:
        print(f"root: {root}")
        print(f"staged-before: {already_staged}")
        if staged:
            print("would-stage:")
            for path in staged:
                print(f"  {path}")
        print("message:")
        for line in message_lines:
            print(f"  {line}")
        return 0

    if not in_tmux() and args.session is None:
        die("not inside tmux and no --session given")
    session = args.session or tmux_output("display-message", "-p", "#{session_name}")
    if not session:
        die("could not determine the tmux session")

    window, socket = ensure_vcs_window(session, root)
    if not run_lua(socket, STATUS_LUA):
        die("failed to open the fugitive commit buffer in the vcs window")
    if not wait_for_commit_buffer(socket):
        die("the fugitive commit buffer did not open")
    if not run_lua(socket, populate_lua(message_lines)):
        die("failed to write the commit message into the buffer")

    note = "reused staged" if already_staged else f"staged {len(staged)} file(s)"
    print(
        f"commit-window: {session}:{window.index} ({VCS_WINDOW_NAME}) ready — "
        f'{note}; drafted "{subject}"'
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
