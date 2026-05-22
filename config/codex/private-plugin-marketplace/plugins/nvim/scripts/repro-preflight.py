#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path
from typing import NoReturn, cast

REPO = Path("/home/barrett/dev/neovim")
WORKTREES = REPO / ".worktrees"
STATE_ROOT = Path("/home/barrett/.local/state/codex-nvim/issues")


class PreflightError(Exception):
    pass


def die(message: str) -> NoReturn:
    raise PreflightError(message)


def output(args: list[str], *, cwd: Path | None = None) -> str:
    return subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


def run_quiet(args: list[str], *, cwd: Path | None = None) -> int:
    return subprocess.run(
        args,
        cwd=cwd,
        check=False,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode


def normalize_issue(value: str) -> str:
    issue = value.removeprefix("#")
    if not issue.isdigit():
        die(f"expected numeric issue, got: {value}")
    return issue


def require_file(path: Path) -> None:
    if not path.is_file():
        die(f"missing file: {path}")


def require_dir(path: Path) -> None:
    if not path.is_dir():
        die(f"missing directory: {path}")


def load_pointer(path: Path) -> dict[str, str]:
    require_file(path)
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        key, separator, value = line.partition("=")
        if separator:
            values[key] = value
    return values


def load_issue_number(path: Path) -> int:
    data = cast(object, json.loads(path.read_text()))
    if not isinstance(data, dict):
        die(f"unexpected issue JSON shape: {path}")
    issue_data = cast(dict[str, object], data)
    number = issue_data.get("number")
    if isinstance(number, int):
        return number
    die(f"missing numeric issue number in: {path}")


def git_status_clean(worktree: Path) -> bool:
    status = output(
        ["git", "status", "--porcelain=v1", "--untracked-files=no"],
        cwd=worktree,
    )
    return status == ""


def git_check_ignore(worktree: Path, path: str) -> bool:
    return run_quiet(["git", "check-ignore", "-q", path], cwd=worktree) == 0


def preflight(issue: str) -> dict[str, str]:
    worktree = WORKTREES / issue
    wiki = STATE_ROOT / issue
    index = wiki / "index.md"
    report = wiki / "report.md"
    log = wiki / "log.md"
    repro = wiki / "evidence" / "repro.md"
    script_dir = worktree / ".codex" / "repros" / "script"
    repro_script = script_dir / "repro.lua"
    pointer_path = worktree / ".codex" / "issue-wiki"
    issue_json = wiki / "sources" / "github" / "issue.json"
    issue_md = wiki / "sources" / "github" / "issue.md"

    require_dir(REPO)
    require_dir(worktree)
    require_dir(wiki)
    for path in [index, report, log, issue_json, issue_md]:
        require_file(path)

    pointer = load_pointer(pointer_path)
    expected_pointer = {
        "issue": issue,
        "wiki": str(wiki),
        "index": str(index),
        "report": str(report),
    }
    for key, expected in expected_pointer.items():
        actual = pointer.get(key)
        if actual != expected:
            die(f"pointer {key} mismatch: expected {expected}, got {actual}")

    json_issue = load_issue_number(issue_json)
    if json_issue != int(issue):
        die(f"issue JSON mismatch: expected {issue}, got {json_issue}")

    root = output(["git", "rev-parse", "--show-toplevel"], cwd=worktree)
    if root != str(worktree):
        die(f"worktree root mismatch: expected {worktree}, got {root}")

    branch = output(["git", "branch", "--show-current"], cwd=worktree)
    if branch != issue:
        die(f"branch mismatch: expected {issue}, got {branch}")

    if not git_status_clean(worktree):
        die("tracked worktree status is not clean")

    if not git_check_ignore(worktree, ".codex/"):
        die(".codex/ is not ignored in the worktree")

    existing = [path for path in [repro] if path.exists()]
    if script_dir.exists():
        existing.extend(sorted(path for path in script_dir.iterdir() if path.is_file()))
    repro_state = "existing" if existing else "ready"

    result = {
        "issue": issue,
        "worktree": str(worktree),
        "wiki": str(wiki),
        "index": str(index),
        "report": str(report),
        "log": str(log),
        "repro": str(repro),
        "script_dir": str(script_dir),
        "repro_script": str(repro_script),
        "branch": branch,
        "head": output(["git", "rev-parse", "--short", "HEAD"], cwd=worktree),
        "status": "clean",
        "codex_ignored": "yes",
        "raw_issue_json": str(issue_json),
        "raw_issue_md": str(issue_md),
        "repro_state": repro_state,
    }
    if existing:
        result["existing_repro_paths"] = ",".join(str(path) for path in existing)
    return result


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: repro-preflight.py <issue>", file=sys.stderr)
        return 2

    try:
        issue = normalize_issue(argv[0])
        result = preflight(issue)
    except PreflightError as exc:
        print(f"nvim repro preflight: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(
            f"nvim repro preflight: command failed with exit {exc.returncode}",
            file=sys.stderr,
        )
        return exc.returncode
    except json.JSONDecodeError as exc:
        print(f"nvim repro preflight: invalid JSON: {exc}", file=sys.stderr)
        return 1

    for key, value in result.items():
        print(f"{key}={value}")

    if result["repro_state"] == "existing":
        print("error=existing_repro_artifacts_reset_before_rerun")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
