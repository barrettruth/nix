#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path
from typing import NoReturn

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_lib"))
import muxlib  # noqa: E402  # ty: ignore[unresolved-import]  # pyright: ignore[reportMissingImports]


def die(message: str) -> NoReturn:
    print(f"commit-window: {message}", file=sys.stderr)
    raise SystemExit(2)


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
    already = muxlib.git_rc(root, "diff", "--cached", "--quiet") == 1
    if already:
        return True, []
    if not stage:
        die("nothing staged and no --stage paths given (never use git add -A)")
    paths = [str(muxlib.normalize_path(p)) for p in stage]
    if not dry_run:
        muxlib.maybe_output(["git", "-C", str(root), "add", "--", *paths])
        if muxlib.git_rc(root, "diff", "--cached", "--quiet") != 1:
            die("staging produced no changes; check the --stage paths")
    return False, paths


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="commit-window",
        description="Draft a fugitive commit in the mux vcs view, unfocused.",
    )
    p.add_argument(
        "-F", "--file", default=None, help="read message from file ('-' = stdin)"
    )
    p.add_argument(
        "-m", "--message", action="append", default=None, help="message line(s)"
    )
    p.add_argument(
        "--stage", nargs="*", default=[], help="files to stage iff nothing is staged"
    )
    p.add_argument(
        "--root", type=Path, default=None, help="base repo (default: current project)"
    )
    p.add_argument(
        "--target", default=None, help="branch or worktree the changes live in"
    )
    p.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="print the plan; do not stage/touch nvim",
    )
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    base = args.root.resolve() if args.root else muxlib.current_root()
    try:
        root = muxlib.resolve_target(base, args.target)
        if muxlib.git_rc(root, "rev-parse", "--is-inside-work-tree") != 0:
            die(f"not a git repository: {root}")

        message = read_message(args)
        already, staged = ensure_staged(root, args.stage, args.dry_run)

        if args.dry_run:
            print(f"root: {root}")
            print(f"staged-before: {already}")
            for path in staged:
                print(f"  would-stage: {path}")
            print("message:")
            for line in message:
                print(f"  {line}")
            return 0

        socket = muxlib.socket_for_root(root)
        res = muxlib.call(socket, {"op": "commit", "message": message})
    except muxlib.MuxError as e:
        die(str(e))

    if not res.get("ok"):
        die(res.get("error", "commit driver failed"))
    note = "reused staged" if already else f"staged {len(staged)} file(s)"
    print(
        f'commit-window: vcs ready — {note}; drafted "{res.get("subject", message[0])}"'
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
