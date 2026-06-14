#!/usr/bin/env python3

import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path("/home/barrett/dev/neovim")
WORKTREES = REPO / ".worktrees"
STATE_ROOT = Path("/home/barrett/.local/state/codex-nvim/issues")
RBUILD_LOG_ROOT = Path("/home/barrett/.local/state/rbuild/nvim")
CURRENT_POINTER = WORKTREES / ".codex" / "current"
RBUILD_REMOTE_WORKTREES = "/home/barrett/dev/neovim/.worktrees"


class CleanError(Exception):
    pass


def die(message: str) -> None:
    raise CleanError(message)


def normalize_issue(value: str) -> str:
    issue = value.removeprefix("#")
    if not issue or not issue.isdigit():
        die(f"expected numeric issue, got: {value}")
    return issue


def output(args: list[str], *, cwd: Path | None = None) -> str:
    return subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


def run(args: list[str], *, cwd: Path | None = None) -> None:
    _ = subprocess.run(args, cwd=cwd, check=True, text=True)


def run_capture(
    args: list[str], *, cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=False,
        text=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def branch_exists(issue: str) -> bool:
    return (
        subprocess.run(
            ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{issue}"],
            cwd=REPO,
            check=False,
        ).returncode
        == 0
    )


def registered_worktree(worktree: Path) -> bool:
    return (
        f"worktree {worktree}"
        in output(["git", "worktree", "list", "--porcelain"], cwd=REPO).splitlines()
    )


def worktree_status(worktree: Path) -> str:
    if not worktree.exists():
        return "(missing)"
    result = run_capture(["git", "status", "--short", "--branch"], cwd=worktree)
    if result.returncode != 0:
        return "(not a valid git worktree)"
    return result.stdout.strip() or "(clean)"


def current_pointer_state(issue: str) -> str:
    if not CURRENT_POINTER.exists():
        return "(missing)"
    text = CURRENT_POINTER.read_text()
    if f"issue={issue}" in text.splitlines():
        return "(points to this issue)"
    return "(points elsewhere)"


def path_state(path: Path) -> str:
    return "(exists)" if path.exists() else "(missing)"


def rbuild_state(issue: str) -> str:
    path = f"{RBUILD_REMOTE_WORKTREES}/{issue}"
    command = f"test -e {path} && printf exists || printf missing"
    result = run_capture(["ssh", "barrett@desktop", command])
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "unknown ssh error"
        return f"(unknown: {detail})"
    return f"({result.stdout.strip()})"


def print_plan(issue: str) -> None:
    worktree = WORKTREES / issue
    wiki = STATE_ROOT / issue
    rbuild_logs = RBUILD_LOG_ROOT / issue

    print(f"Neovim issue cleanup: {issue}")
    print(f"worktree: {worktree} {path_state(worktree)}")
    print(f"registered worktree: {'yes' if registered_worktree(worktree) else 'no'}")
    print(f"branch: {issue} {'(exists)' if branch_exists(issue) else '(missing)'}")
    print("status:")
    print(worktree_status(worktree))
    print(f"issue wiki: {wiki} {path_state(wiki)}")
    print(f"local rbuild logs: {rbuild_logs} {path_state(rbuild_logs)}")
    print(f"current pointer: {CURRENT_POINTER} {current_pointer_state(issue)}")
    print(f"rbuild mirror: barrett@desktop:{RBUILD_REMOTE_WORKTREES}/{issue} {rbuild_state(issue)}")


def remove_worktree(issue: str) -> None:
    worktree = WORKTREES / issue
    if registered_worktree(worktree):
        run(["git", "worktree", "remove", "--force", str(worktree)], cwd=REPO)
    elif worktree.exists():
        shutil.rmtree(worktree)


def remove_branch(issue: str) -> None:
    if branch_exists(issue):
        run(["git", "branch", "-D", issue], cwd=REPO)


def remove_current_pointer(issue: str) -> None:
    if not CURRENT_POINTER.exists():
        return
    if f"issue={issue}" in CURRENT_POINTER.read_text().splitlines():
        CURRENT_POINTER.unlink()


def remove_rbuild_mirror(issue: str) -> None:
    path = f"{RBUILD_REMOTE_WORKTREES}/{issue}"
    result = run_capture(["ssh", "barrett@desktop", f"rm -rf {path}"])
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "unknown ssh error"
        die(f"failed to remove rbuild mirror: {detail}")


def clean(issue: str) -> None:
    remove_worktree(issue)
    remove_branch(issue)
    shutil.rmtree(STATE_ROOT / issue, ignore_errors=True)
    shutil.rmtree(RBUILD_LOG_ROOT / issue, ignore_errors=True)
    remove_current_pointer(issue)
    remove_rbuild_mirror(issue)


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: issue-clean.py <issue>", file=sys.stderr)
        return 2

    try:
        issue = normalize_issue(argv[0])
        print_plan(issue)
        answer = input(f"Hard remove all Neovim issue {issue} cleanup targets? y/N ")
        if answer != "y":
            print("aborted")
            return 0
        clean(issue)
    except CleanError as exc:
        print(f"nvim issue clean: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(
            f"nvim issue clean: command failed with exit {exc.returncode}",
            file=sys.stderr,
        )
        return exc.returncode

    print(f"removed Neovim issue {issue} cleanup targets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
