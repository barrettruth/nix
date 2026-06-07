#!/usr/bin/env python3

import argparse
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import cast


EDIT_HELPER = Path(
    "/home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit-window.py"
)


@dataclass(frozen=True)
class Args:
    worktree: Path
    base: str
    files: list[Path]


def run(
    args: list[str], *, cwd: Path | None = None, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )


def maybe_output(args: list[str]) -> str:
    proc = subprocess.run(
        args, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def tmux(*args: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return run(["tmux", *args], capture=capture)


def tmux_output(*args: str) -> str:
    return tmux(*args, capture=True).stdout.rstrip("\n")


def worktree_root(worktree: Path) -> Path:
    out = maybe_output(["git", "-C", str(worktree), "rev-parse", "--show-toplevel"])
    return Path(out).resolve() if out else worktree.resolve()


# The review lives in the session the user is attached to (their current
# session), not a mux-spawned per-worktree session.
def attached_session() -> str:
    out = maybe_output(["tmux", "list-clients", "-F", "#{client_session}"])
    for line in out.splitlines():
        name = line.strip()
        if name:
            return name
    return tmux_output("display-message", "-p", "#{session_name}")


def find_git_window(session: str, root: Path) -> str | None:
    fmt = (
        "#{window_index}\t#{window_name}\t#{pane_current_command}\t#{pane_current_path}"
    )
    rows = tmux_output("list-windows", "-t", session, "-F", fmt)
    for row in rows.splitlines():
        parts = row.split("\t")
        if len(parts) < 4:
            continue
        index, name, command, path = parts[:4]
        if name == "git" and command == "nvim" and Path(path).resolve() == root:
            return f"{session}:{index}"
    return None


def wait_for_nvim(target: str) -> None:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        command = maybe_output(
            ["tmux", "display-message", "-p", "-t", target, "#{pane_current_command}"]
        )
        if command == "nvim":
            return
        time.sleep(0.05)
    raise RuntimeError(f"git window nvim did not start: {target}")


def open_git_review(session: str, root: Path, base: str) -> str:
    target = find_git_window(session, root)
    if target is None:
        index = tmux_output(
            "new-window",
            "-d",
            "-t",
            f"{session}:",
            "-c",
            str(root),
            "-n",
            "git",
            "-P",
            "-F",
            "#{window_index}",
            "nvim",
        )
        target = f"{session}:{index}"
        wait_for_nvim(target)
    command = f"Diff review ++layout=unified {base} | only"
    _ = tmux("send-keys", "-t", target, "Escape")
    _ = tmux("send-keys", "-t", target, ":" + command, "Enter")
    return target


def populate_edit(session: str, root: Path, files: list[Path]) -> None:
    _ = run(
        [
            "python3",
            str(EDIT_HELPER),
            "--session",
            session,
            "--root",
            str(root),
            "--limit",
            str(len(files)),
            *[str(path) for path in files],
        ],
        cwd=root,
    )


def focus(target: str) -> None:
    session = target.split(":", 1)[0]
    _ = tmux("select-window", "-t", target)
    clients = maybe_output(
        ["tmux", "list-clients", "-t", session, "-F", "#{client_name}"]
    )
    for client in clients.splitlines():
        client = client.strip()
        if client:
            _ = subprocess.run(
                ["tmux", "switch-client", "-c", client, "-t", target], check=False
            )
            break


def parse_args(argv: list[str]) -> Args:
    parser = argparse.ArgumentParser(
        description="Prepare the mux review UI (git :Diff review + edit quickfix) "
        "in the current session for a worktree's changes."
    )
    _ = parser.add_argument("--worktree", required=True, type=Path)
    _ = parser.add_argument("--base", required=True)
    _ = parser.add_argument("files", nargs="+", type=Path)
    namespace = parser.parse_args(argv)
    return Args(
        worktree=cast(Path, namespace.worktree),
        base=cast(str, namespace.base),
        files=cast(list[Path], namespace.files),
    )


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    worktree = args.worktree.resolve()
    root = worktree_root(worktree)
    files = [
        path.resolve() if path.is_absolute() else (root / path).resolve()
        for path in args.files
    ]

    if not worktree.is_dir():
        raise SystemExit(f"review-ui: missing worktree: {worktree}")
    if not EDIT_HELPER.exists():
        raise SystemExit(f"review-ui: missing edit helper: {EDIT_HELPER}")
    for path in files:
        if not path.exists():
            raise SystemExit(f"review-ui: missing file: {path}")

    session = attached_session()
    git_target = open_git_review(session, root, args.base)
    populate_edit(session, root, files)
    focus(git_target)

    print(
        f"review-ui: {session} git = :Diff review ++layout=unified {args.base}; "
        f"edit quickfix = {len(files)} files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
