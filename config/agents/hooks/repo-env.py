#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import TypedDict, cast

TIMEOUT = 3


class ToolResponse(TypedDict, total=False):
    output: str | None
    error: str | None


class HookEvent(TypedDict, total=False):
    tool_response: ToolResponse | str


class Arguments(argparse.Namespace):
    mode: str = "session"


def run(root: Path, *args: str) -> str:
    try:
        proc = subprocess.run(
            args,
            check=False,
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=TIMEOUT,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return proc.stdout.strip() if proc.returncode == 0 else ""


def project_root() -> Path | None:
    start = Path(os.environ.get("DEVIN_PROJECT_DIR") or Path.cwd()).resolve()
    for path in (start, *start.parents):
        if (path / ".jj").is_dir() or (path / ".git").exists():
            return path
    return None


def direnv_loaded(root: Path) -> bool:
    loaded = os.environ.get("DIRENV_DIR", "")
    return bool(loaded) and Path(loaded.lstrip("-")).resolve() == root


def has_devshells(root: Path) -> bool:
    if (root / ".git").exists():
        return bool(run(root, "git", "grep", "-l", "devShells", "--", "*.nix"))
    for count, path in enumerate(root.rglob("*.nix")):
        if count > 300:
            break
        try:
            if "devShells" in path.read_text(errors="ignore"):
                return True
        except OSError:
            continue
    return False


def enter(root: Path) -> str | None:
    if (root / ".envrc").is_file() and not direnv_loaded(root):
        return "direnv exec . <cmd>"
    if (root / "flake.nix").is_file() and has_devshells(root):
        return "nix develop -c <cmd>"
    return None


def facts(root: Path) -> list[str]:
    found: list[str] = []

    if (root / ".jj").is_dir():
        colocated = " colocated with git" if (root / ".git").exists() else ""
        found.append("VCS is jujutsu" + colocated + ", not plain git.")

    if any((root / name).is_file() for name in ("justfile", "Justfile")):
        summary = run(root, "just", "--summary")
        if summary:
            found.append("just recipes: " + summary + ".")

    entry = enter(root)
    if entry and (root / ".envrc").is_file():
        found.append(
            ".envrc is present but direnv is not active in this environment;"
            + " repo tooling runs under `"
            + entry
            + "`."
        )
    elif entry:
        found.append(
            "The flake defines devShells; a tool missing from PATH is supplied by `"
            + entry
            + "`."
        )

    return found


def emit(event: str, context: str) -> None:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": event,
                "additionalContext": context,
            }
        },
        sys.stdout,
    )


def session() -> None:
    root = project_root()
    if root is None:
        return
    found = facts(root)
    if not found:
        return
    lines = "\n".join("- " + fact for fact in found)
    header = "Checkout facts, probed at session start (" + str(root) + "):\n"
    emit("SessionStart", header + lines)


def command_not_found() -> None:
    try:
        payload = cast(HookEvent, json.load(sys.stdin))
    except (json.JSONDecodeError, ValueError):
        return
    response = payload.get("tool_response") or ToolResponse()
    haystack = (
        response
        if isinstance(response, str)
        else (response.get("output") or "") + "\n" + (response.get("error") or "")
    )
    if "command not found" not in haystack and "not found in $PATH" not in haystack:
        return
    root = project_root()
    entry = enter(root) if root else None
    if entry is None:
        return
    emit(
        "PostToolUse",
        "That command is missing from PATH, but this checkout supplies tooling"
        + " through `"
        + entry
        + "`. Re-run it that way before concluding the tool is unavailable.",
    )


def parse_arguments() -> Arguments:
    parser = argparse.ArgumentParser(
        prog="repo-env",
        description="Report checkout facts to the agent as lifecycle hooks.",
    )
    sub = parser.add_subparsers(dest="mode", required=True)
    _ = sub.add_parser("session", help="SessionStart: state what the checkout provides")
    _ = sub.add_parser(
        "command-not-found", help="PostToolUse: name the shell that supplies the tool"
    )
    return cast(Arguments, parser.parse_args())


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.mode == "session":
            session()
        else:
            command_not_found()
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
