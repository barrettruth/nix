#!/usr/bin/env python3

import argparse
import json
import os
import re
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

# Wipe any stale PR compose buffers, then ask forge.nvim to open a draft create
# compose. Driving via :Forge (not require) ensures lz.n loads forge + its config.
CREATE_LUA = "\n".join(
    [
        "for _, b in ipairs(vim.fn.getbufinfo()) do",
        "  local n = b.name or ''",
        "  if n:find('/pr/', 1, true) and vim.bo[b.bufnr].filetype == 'forgecompose' then",
        "    pcall(vim.cmd, 'silent! bwipeout! ' .. b.bufnr)",
        "  end",
        "end",
        "pcall(vim.cmd, 'silent! Forge pr create draft')",
    ]
)

# Fallback when a PR already exists for the branch (create aborts): open the edit
# compose instead.
EDIT_LUA = "pcall(vim.cmd, 'silent! Forge pr edit')"

# Synchronous "does an open PR already exist for this branch?" check. Runs after
# CREATE_LUA, so forge is loaded with its config. 1 = a PR exists (-> edit),
# 0 = none / unknown (-> wait for the create compose). This is the authoritative
# create-vs-edit signal; never infer it from a poll timeout (create is async and
# base resolution can be slow).
PR_EXISTS_LUA = (
    '(function() local ok, f = pcall(require, "forge") if not ok then return 0 end '
    "local d = f.detect() if not d then return 0 end "
    "local pr, err = f.current_pr({ forge = d }) if err then return 0 end "
    'if type(pr) == "table" and pr.num then return 1 end return 0 end)()'
)

# Return the name of the live PR compose buffer (or '' if none is ready yet).
POLL_LUA = (
    "(function() for _, b in ipairs(vim.fn.getbufinfo()) do "
    'local n = b.name or "" '
    'if n:find("/pr/", 1, true) and vim.api.nvim_buf_is_valid(b.bufnr) '
    'and vim.bo[b.bufnr].filetype == "forgecompose" '
    "and #vim.api.nvim_buf_get_lines(b.bufnr, 0, -1, false) > 1 then return n end "
    'end return "" end)()'
)

# For an existing PR's edit compose: is the body region (between the title and the
# <!-- metadata block) empty? 1 = empty (-> populate it), 0 = has content (-> leave).
EDIT_BODY_EMPTY_LUA = (
    "(function() for _, b in ipairs(vim.fn.getbufinfo()) do "
    'local n = b.name or "" '
    'if n:sub(-5) == "/edit" and vim.bo[b.bufnr].filetype == "forgecompose" then '
    "local lines = vim.api.nvim_buf_get_lines(b.bufnr, 0, -1, false) "
    "local cut = #lines "
    'for i = 1, #lines do if lines[i]:match("^%s*<!%-%-") then cut = i - 1 break end end '
    'for i = 3, cut do if vim.trim(lines[i]) ~= "" then return 0 end end '
    "return 1 end end return 0 end)()"
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
    print(f"pr-window: {message}", file=sys.stderr)
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
    if (
        candidate.is_dir()
        and git_rc(candidate, "rev-parse", "--is-inside-work-tree") == 0
    ):
        top = maybe_output(
            ["git", "-C", str(candidate), "rev-parse", "--show-toplevel"]
        )
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
    fd, name = tempfile.mkstemp(prefix=f"pr-{os.getuid()}-", suffix=".lua")
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


def poll_compose(socket: str, timeout: float) -> str:
    expr = f"luaeval('{POLL_LUA}')"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rc, out = remote_expr(socket, expr)
        if rc == 0 and out:
            return out
        time.sleep(0.15)
    return ""


def pr_exists(socket: str) -> bool:
    rc, out = remote_expr(socket, f"luaeval('{PR_EXISTS_LUA}')")
    return rc == 0 and out == "1"


def edit_body_empty(socket: str) -> bool:
    rc, out = remote_expr(socket, f"luaeval('{EDIT_BODY_EMPTY_LUA}')")
    return rc == 0 and out == "1"


def surgery_lua(body_lines: list[str], title: str | None = None) -> str:
    # Writes body into the live PR compose buffer, preserving forge's trailing
    # <!-- metadata --> block. When `title` is given (create), also replaces the
    # title line; when omitted (filling an existing PR's empty body), the existing
    # title is kept.
    body_lit = json.dumps(json.dumps(body_lines))
    title_block: list[str] = []
    if title is not None:
        title_lit = json.dumps(json.dumps(title))
        title_block = [
            f"local title = vim.json.decode({title_lit})",
            "vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# ' .. title })",
        ]
    return "\n".join(
        [
            f"local body = vim.json.decode({body_lit})",
            "local buf = -1",
            "for _, b in ipairs(vim.fn.getbufinfo()) do",
            "  local n = b.name or ''",
            "  if n:find('/pr/', 1, true) and vim.bo[b.bufnr].filetype == 'forgecompose' then",
            "    buf = b.bufnr break",
            "  end",
            "end",
            "if buf < 0 then return end",
            "local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)",
            "local cut = #lines",
            "for i = 1, #lines do",
            "  if lines[i]:match('^%s*<!%-%-') then cut = i - 1 break end",
            "end",
            *title_block,
            "local head = {}",
            "for _, l in ipairs(body) do head[#head + 1] = l end",
            "head[#head + 1] = ''",
            "vim.api.nvim_buf_set_lines(buf, 2, cut, false, head)",
            "for _, w in ipairs(vim.fn.win_findbuf(buf)) do",
            "  pcall(vim.api.nvim_win_set_cursor, w, { 1, 0 })",
            "end",
            # forge's open_pr leaves the title in select mode (normal! v$h + <C-G>);
            # clear it so the buffer is in normal mode when Barrett arrives.
            "pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)",
        ]
    )


def read_body(args: argparse.Namespace) -> list[str]:
    if args.file:
        text = (
            sys.stdin.read()
            if args.file == "-"
            else Path(args.file).expanduser().read_text(encoding="utf-8")
        )
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        text = ""
    lines = text.rstrip("\n").split("\n") if text.strip() else []
    for i, line in enumerate(lines):
        if re.match(r"^\s*<!--", line):
            die(
                f"body line {i + 1} starts with '<!--', which collides with "
                "forge's metadata block; rephrase it"
            )
    return lines


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="pr-window",
        description=(
            "Open forge.nvim's draft PR compose in the mux vcs window, pre-filled "
            "with a title + template body, without focusing it."
        ),
    )
    parser.add_argument("--title", required=True, help="PR title (the # line)")
    parser.add_argument(
        "-F", "--file", default=None, help="read body from file ('-' = stdin)"
    )
    parser.add_argument(
        "--target",
        default=None,
        help="branch or worktree path the changes live in (default: base repo)",
    )
    parser.add_argument(
        "--root", type=Path, default=None, help="base repo (default: current project)"
    )
    parser.add_argument(
        "--session", default=None, help="tmux session (default: current)"
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="print the plan; do not touch tmux/nvim",
    )
    args = parser.parse_args(argv)
    if not args.title.strip():
        parser.error("--title cannot be empty")
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    base = args.root.resolve() if args.root else current_root()
    root = resolve_root(base, args.target)
    if git_rc(root, "rev-parse", "--is-inside-work-tree") != 0:
        die(f"not a git repository: {root}")

    # Assume committed + clean; bail on uncommitted tracked changes (untracked
    # per-machine noise is fine — it is never part of the PR).
    if (
        git_rc(root, "diff", "--quiet") != 0
        or git_rc(root, "diff", "--cached", "--quiet") != 0
    ):
        die(
            "uncommitted changes to tracked files; commit first (nvim-commit), then retry"
        )

    branch = maybe_output(["git", "-C", str(root), "rev-parse", "--abbrev-ref", "HEAD"])
    body = read_body(args)

    if args.dry_run:
        print(f"root: {root}")
        print(f"branch: {branch}")
        print(f"title: {args.title}")
        print("body:")
        for line in body:
            print(f"  {line}")
        return 0

    if not in_tmux() and args.session is None:
        die("not inside tmux and no --session given")
    session = args.session or tmux_output("display-message", "-p", "#{session_name}")
    if not session:
        die("could not determine the tmux session")

    window, socket = ensure_vcs_window(session, root)

    # CREATE_LUA wipes stale PR composes and runs `:Forge pr create draft`, which
    # loads forge (so the sync existing-PR check below works) and either opens a
    # draft create compose or aborts because a PR already exists. We decide
    # create-vs-edit from the authoritative sync check, not the poll timing.
    run_lua(socket, CREATE_LUA)
    if pr_exists(socket):
        run_lua(socket, EDIT_LUA)
        name = poll_compose(socket, timeout=8.0)
    else:
        name = poll_compose(socket, timeout=8.0)

    if name.endswith("/pr/new"):
        if not run_lua(socket, surgery_lua(body, title=args.title)):
            die("failed to write the PR compose buffer")
        note = "draft PR compose"
    elif name.endswith("/edit"):
        match = re.search(r"/pr/(\d+)/edit", name)
        num = match.group(1) if match else "?"
        if edit_body_empty(socket):
            run_lua(socket, surgery_lua(body))  # fill empty description; keep title
            note = f"existing PR #{num} — filled empty description"
        else:
            note = f"existing PR #{num} — edit compose (left as-is)"
    else:
        die(
            "no PR compose opened — no forge detected, detached HEAD, "
            "or no commits/existing PR for this branch"
        )

    print(
        f"pr-window: {session}:{window.index} ({VCS_WINDOW_NAME}) ready — {note} for {branch}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
