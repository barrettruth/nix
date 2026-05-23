#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import cast


@dataclass(frozen=True)
class Args:
    worktree: Path
    base: str
    files: list[Path]


@dataclass(frozen=True)
class TmuxTarget:
    client: str
    window: str


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


def tmux(*args: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return run(["tmux", *args], capture=capture)


def tmux_output(*args: str) -> str:
    return tmux(*args, capture=True).stdout.rstrip("\n")


def current_window_target() -> TmuxTarget:
    session = tmux_output("display-message", "-p", "#{session_name}")
    index = tmux_output("display-message", "-p", "#{window_index}")
    client = tmux_output("display-message", "-p", "#{client_name}")
    return TmuxTarget(client=client, window=f"{session}:{index}")


def restore_window(target: TmuxTarget) -> None:
    try:
        _ = tmux("select-window", "-t", target.window)
        if target.client:
            _ = tmux("switch-client", "-c", target.client, "-t", target.window)
    except subprocess.CalledProcessError as exc:
        print(f"review-ui: failed to restore tmux window: {exc}", file=sys.stderr)


def git_window_target(session: str) -> str:
    rows = tmux_output(
        "list-windows", "-t", session, "-F", "#{window_name}\t#{window_index}"
    )
    for row in rows.splitlines():
        name, index = row.split("\t", 1)
        if name == "git":
            return f"{session}:{index}"
    raise RuntimeError("mux git did not create a git window")


def pane_output(target: str, fmt: str) -> str:
    return tmux_output("display-message", "-p", "-t", target, fmt)


def git_window_ready(target: str, worktree: Path) -> bool:
    command = pane_output(target, "#{pane_current_command}")
    cwd = Path(pane_output(target, "#{pane_current_path}")).resolve()
    return command == "nvim" and cwd == worktree


def wait_for_git_window(target: str, worktree: Path) -> None:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if git_window_ready(target, worktree):
            return
        time.sleep(0.05)
    raise RuntimeError(f"mux git window is not ready for Greview: {target}")


def send_greview(worktree: Path, base: str) -> None:
    _ = run(
        ["mux", "_picker_open", "proj", "action", "git", f"proj:{worktree}"],
        cwd=worktree,
    )
    session = tmux_output("display-message", "-p", "#{session_name}")
    target = git_window_target(session)
    wait_for_git_window(target, worktree)
    command = f"Greview {base} | only"
    _ = tmux("send-keys", "-t", target, "Escape")
    _ = tmux("send-keys", "-t", target, ":" + command, "Enter")


def populate_edit(worktree: Path, files: list[Path]) -> None:
    helper = Path(__file__).with_name("edit-window.py")
    _ = run(
        [
            "python3",
            str(helper),
            "--limit",
            str(len(files)),
            *[str(path) for path in files],
        ],
        cwd=worktree,
    )


def parse_args(argv: list[str]) -> Args:
    parser = argparse.ArgumentParser(
        description="Prepare mux review UI for a Neovim issue worktree."
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
    files = [
        path.resolve() if path.is_absolute() else (worktree / path).resolve()
        for path in args.files
    ]

    if not worktree.is_dir():
        raise SystemExit(f"review-ui: missing worktree: {worktree}")
    for path in files:
        if not path.exists():
            raise SystemExit(f"review-ui: missing file: {path}")

    original = current_window_target() if os.environ.get("TMUX") else None
    try:
        send_greview(worktree, args.base)
        populate_edit(worktree, files)
    finally:
        if original:
            restore_window(original)

    print(f"review-ui: git window prepared with Greview {args.base}")
    print(f"review-ui: edit quickfix populated with {len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
