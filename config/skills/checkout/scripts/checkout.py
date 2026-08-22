#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class CheckoutError(Exception):
    pass


@dataclass(frozen=True)
class Worktree:
    path: Path
    branch: str | None
    head: str | None
    dirty: bool
    staged: bool
    unstaged: bool
    untracked: bool


def run(
    repo: Path, *args: str, check: bool = False
) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and proc.returncode != 0:
        message = proc.stderr.strip() or proc.stdout.strip() or "git failed"
        raise CheckoutError(message)
    return proc


def output(repo: Path, *args: str) -> str:
    proc = run(repo, *args)
    return proc.stdout.rstrip("\n") if proc.returncode == 0 else ""


def root_for(path: Path) -> Path:
    start = path.expanduser().resolve()
    proc = subprocess.run(
        ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        raise CheckoutError(f"not a git worktree: {start}")
    return Path(proc.stdout.strip()).resolve()


def current_branch(repo: Path) -> str | None:
    name = output(repo, "branch", "--show-current")
    return name or None


def common_dir(repo: Path) -> Path:
    value = output(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not value:
        raise CheckoutError(f"cannot resolve git common dir: {repo}")
    return Path(value).resolve()


def canonical_repo(repo: Path) -> Path:
    common = common_dir(repo)
    if common.name == ".git":
        return common.parent
    return repo


def local_branches(repo: Path) -> list[str]:
    lines = output(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads")
    return sorted(line for line in lines.splitlines() if line)


def dirty_state(repo: Path) -> tuple[bool, bool, bool, bool]:
    lines = output(repo, "status", "--porcelain=v1", "-uall").splitlines()
    staged = False
    unstaged = False
    untracked = False
    for line in lines:
        if not line:
            continue
        x = line[0]
        y = line[1] if len(line) > 1 else " "
        if line.startswith("??"):
            untracked = True
            continue
        if x != " ":
            staged = True
        if y != " ":
            unstaged = True
    dirty = staged or unstaged or untracked
    return dirty, staged, unstaged, untracked


def worktrees(repo: Path) -> list[Worktree]:
    rows = output(repo, "worktree", "list", "--porcelain").splitlines() + [""]
    current: dict[str, str] = {}
    result: list[Worktree] = []
    for line in rows:
        if line.startswith("worktree "):
            current = {"path": line.removeprefix("worktree ")}
            continue
        if line.startswith("HEAD "):
            current["head"] = line.removeprefix("HEAD ")
            continue
        if line.startswith("branch "):
            ref = line.removeprefix("branch ")
            current["branch"] = ref.removeprefix("refs/heads/")
            continue
        if line == "" and current:
            path = Path(current["path"]).resolve()
            try:
                dirty, staged, unstaged, untracked = dirty_state(path)
            except CheckoutError:
                dirty = staged = unstaged = untracked = False
            result.append(
                Worktree(
                    path=path,
                    branch=current.get("branch"),
                    head=current.get("head"),
                    dirty=dirty,
                    staged=staged,
                    unstaged=unstaged,
                    untracked=untracked,
                )
            )
            current = {}
    return result


def serialize_worktree(entry: Worktree) -> dict[str, Any]:
    return {
        "path": str(entry.path),
        "branch": entry.branch,
        "head": entry.head,
        "dirty": entry.dirty,
        "staged": entry.staged,
        "unstaged": entry.unstaged,
        "untracked": entry.untracked,
    }


def inspect_repo(repo: Path) -> dict[str, Any]:
    root = root_for(repo)
    branches = local_branches(root)
    entries = worktrees(root)
    return {
        "current_root": str(root),
        "current_branch": current_branch(root),
        "canonical_repo": str(canonical_repo(root)),
        "git_common_dir": str(common_dir(root)),
        "branches": branches,
        "worktrees": [serialize_worktree(entry) for entry in entries],
    }


def path_target(value: str) -> Path | None:
    raw = Path(value).expanduser()
    if raw.exists():
        return root_for(raw)
    return None


def branch_worktree(entries: list[Worktree], branch: str) -> Worktree | None:
    for entry in entries:
        if entry.branch == branch:
            return entry
    return None


def target_candidates(
    target: str, branches: list[str], entries: list[Worktree]
) -> list[str]:
    value = target.lower()
    candidates = [branch for branch in branches if value in branch.lower()]
    for entry in entries:
        name = entry.path.name.lower()
        if value in name:
            candidates.append(str(entry.path))
    return sorted(dict.fromkeys(candidates))


def resolve(repo: Path, target: str) -> dict[str, Any]:
    info = inspect_repo(repo)
    root = Path(info["current_root"])
    branches = list(info["branches"])
    entries = worktrees(root)
    path = path_target(target)
    if path is not None:
        entry = next((item for item in entries if item.path == path), None)
        return {
            "ok": True,
            "kind": "worktree",
            "target": str(path),
            "path": str(path),
            "branch": entry.branch if entry else current_branch(path),
            "action": "current" if path == root else "existing",
            "worktree": serialize_worktree(entry) if entry else None,
        }
    if target in branches:
        entry = branch_worktree(entries, target)
        if entry:
            return {
                "ok": True,
                "kind": "branch",
                "target": target,
                "path": str(entry.path),
                "branch": target,
                "action": "current" if entry.path == root else "existing",
                "worktree": serialize_worktree(entry),
            }
        return {
            "ok": True,
            "kind": "branch",
            "target": target,
            "path": None,
            "branch": target,
            "action": "create",
            "worktree": None,
        }
    candidates = target_candidates(target, branches, entries)
    return {
        "ok": False,
        "error": f"unknown target: {target}",
        "candidates": candidates,
    }


def worktree_name(branch: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]", "-", branch).strip("-")
    return value or "worktree"


def ensure(repo: Path, target: str, dry_run: bool) -> dict[str, Any]:
    resolved = resolve(repo, target)
    if not resolved.get("ok"):
        return resolved
    if resolved["action"] in {"current", "existing"}:
        resolved["created"] = False
        return resolved
    if resolved["kind"] != "branch":
        raise CheckoutError(
            f"cannot create worktree for target kind: {resolved['kind']}"
        )
    root = root_for(repo)
    base = canonical_repo(root) / ".worktrees"
    path = base / worktree_name(resolved["branch"])
    if path.exists():
        raise CheckoutError(f"target worktree path already exists: {path}")
    if dry_run:
        resolved["path"] = str(path)
        resolved["created"] = False
        resolved["dry_run"] = True
        return resolved
    base.mkdir(parents=True, exist_ok=True)
    _ = run(root, "worktree", "add", str(path), resolved["branch"], check=True)
    out = resolve(path, str(path))
    out["created"] = True
    return out


def print_result(data: dict[str, Any], as_json: bool) -> None:
    if as_json:
        print(json.dumps(data, indent=2, sort_keys=True))
        return
    if not data.get("ok", True):
        print(data.get("error", "checkout failed"), file=sys.stderr)
        candidates: list[str] = data.get("candidates") or []
        if candidates:
            print("candidates:", file=sys.stderr)
            for candidate in candidates:
                print(f"  {candidate}", file=sys.stderr)
        raise SystemExit(1)
    if "worktrees" in data:
        print(
            f"current: {data['current_branch'] or '(detached)'} {data['current_root']}"
        )
        for entry in data["worktrees"]:
            marker = "*" if entry["path"] == data["current_root"] else " "
            state = "dirty" if entry["dirty"] else "clean"
            print(f"{marker} {entry['branch'] or '(detached)'} {entry['path']} {state}")
        return
    print(
        f"{data['action']}: {data.get('branch') or data['target']} -> {data.get('path')}"
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="checkout")
    sub = parser.add_subparsers(dest="command", required=True)
    inspect_cmd = sub.add_parser("inspect")
    _ = inspect_cmd.add_argument("--repo", type=Path, default=Path.cwd())
    _ = inspect_cmd.add_argument("--json", action="store_true")
    for name in ["resolve", "ensure"]:
        cmd = sub.add_parser(name)
        _ = cmd.add_argument("--repo", type=Path, default=Path.cwd())
        _ = cmd.add_argument("--target", required=True)
        _ = cmd.add_argument("--json", action="store_true")
        if name == "ensure":
            _ = cmd.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        if args.command == "inspect":
            data = inspect_repo(args.repo)
        elif args.command == "resolve":
            data = resolve(args.repo, args.target)
        elif args.command == "ensure":
            data = ensure(args.repo, args.target, args.dry_run)
        else:
            raise CheckoutError(f"unknown command: {args.command}")
        print_result(data, args.json)
        return 0 if data.get("ok", True) else 1
    except CheckoutError as exc:
        data = {"ok": False, "error": str(exc)}
        print_result(data, getattr(args, "json", False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
