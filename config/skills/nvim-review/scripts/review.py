#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_lib"))
import muxlib  # noqa: E402  # ty: ignore[unresolved-import]  # pyright: ignore[reportMissingImports]

JUNK_TOP = {
    ".git",
    ".jj",
    ".agents",
    ".worktrees",
    "build",
    ".deps",
    ".cmake",
    ".tmp",
    ".direnv",
    "result",
}


class ReviewError(Exception):
    pass


def run(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def git(repo: Path, *args: str) -> str:
    proc = run(repo, *args)
    return proc.stdout.rstrip("\n") if proc.returncode == 0 else ""


def require_git(repo: Path, *args: str) -> str:
    proc = run(repo, *args)
    if proc.returncode != 0:
        message = proc.stderr.strip() or proc.stdout.strip() or "git failed"
        raise ReviewError(message)
    return proc.stdout.rstrip("\n")


def git_ok(repo: Path, *args: str) -> bool:
    return run(repo, *args).returncode == 0


def root_for(path: Path) -> Path:
    value = require_git(path, "rev-parse", "--show-toplevel")
    return Path(value).resolve()


def current_branch(repo: Path) -> str:
    return git(repo, "branch", "--show-current") or "(detached)"


def commit_for(repo: Path, ref: str) -> str | None:
    value = git(repo, "rev-parse", "--verify", f"{ref}^{{commit}}")
    return value or None


def default_base_ref(repo: Path) -> str:
    for ref in (
        "upstream/HEAD",
        "upstream/main",
        "upstream/master",
        "origin/HEAD",
        "origin/main",
        "origin/master",
        "main",
        "master",
    ):
        if commit_for(repo, ref):
            return ref
    return "HEAD"


def compute_base(repo: Path, ref: str | None) -> tuple[str, str]:
    base_ref = ref or default_base_ref(repo)
    if not commit_for(repo, base_ref):
        raise ReviewError(f"invalid base ref: {base_ref}")
    base = git(repo, "merge-base", "HEAD", base_ref)
    if not base:
        base = require_git(repo, "rev-parse", "HEAD")
    return base_ref, base


def review_paths(repo: Path, base: str) -> tuple[list[str], list[Path]]:
    rels = git(repo, "diff", "--name-only", base).splitlines()
    rels += git(repo, "ls-files", "--others", "--exclude-standard").splitlines()
    paths: list[str] = []
    files: list[Path] = []
    seen_paths: set[str] = set()
    seen_files: set[Path] = set()
    for rel in rels:
        if not rel or rel.split("/", 1)[0] in JUNK_TOP:
            continue
        if rel not in seen_paths:
            paths.append(rel)
            seen_paths.add(rel)
        path = (repo / rel).resolve()
        if path.exists() and path not in seen_files:
            files.append(path)
            seen_files.add(path)
    return paths, files


def review_model(repo: Path, layout: str, base_ref: str | None) -> dict[str, Any]:
    root = root_for(repo)
    resolved_base_ref, base = compute_base(root, base_ref)
    paths, files = review_paths(root, base)
    items = [{"filename": str(path), "lnum": 1, "col": 1, "text": ""} for path in files]
    return {
        "ok": True,
        "root": str(root),
        "branch": current_branch(root),
        "base_ref": resolved_base_ref,
        "base": base,
        "layout": layout,
        "paths": paths,
        "files": [str(path) for path in files],
        "items": items,
        "count": len(paths),
    }


def open_review(model: dict[str, Any]) -> None:
    socket = muxlib.socket_for_root(Path(model["root"]))
    review = muxlib.call(
        socket,
        {
            "op": "review",
            "base": model["base"],
            "layout": model["layout"],
        },
    )
    if not review.get("ok"):
        raise ReviewError(review.get("error", "review driver failed"))
    edit = muxlib.call(
        socket,
        {
            "op": "edit",
            "files": model["files"],
            "items": model["items"],
            "root": model["root"],
        },
    )
    if not edit.get("ok"):
        raise ReviewError(edit.get("error", "edit driver failed"))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Open the current checkout's changes in mux review UI."
    )
    _ = parser.add_argument("--repo", type=Path, default=Path.cwd())
    _ = parser.add_argument("--base", default=None)
    _ = parser.add_argument(
        "--layout", choices=["unified", "stacked", "split"], default="unified"
    )
    _ = parser.add_argument("--dry-run", action="store_true")
    _ = parser.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def print_json(data: dict[str, Any]) -> None:
    print(json.dumps(data, indent=2, sort_keys=True))


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        model = review_model(args.repo, args.layout, args.base)
        if args.json:
            print_json(model)
        if model["count"] == 0:
            if not args.json:
                print(
                    f"nvim-review: no reviewable changes in {model['branch']} ({model['root']})"
                )
            return 0
        if args.dry_run:
            if not args.json:
                print(
                    f"nvim-review: would review {model['branch']} ({model['root']}) vs {model['base'][:10]} — {model['count']} paths"
                )
            return 0
        open_review(model)
        print(
            f"nvim-review: reviewing {model['branch']} ({model['root']}) vs {model['base'][:10]} — {model['count']} paths"
        )
        return 0
    except (ReviewError, muxlib.MuxError) as exc:
        if args.json:
            print_json({"ok": False, "error": str(exc)})
        else:
            print(f"nvim-review: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
