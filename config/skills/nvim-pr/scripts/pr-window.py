#!/usr/bin/env python3

# Draft a PR title + body into forge.nvim's compose in the mux `vcs` view, left
# unfocused for Barrett to `:w`/`:q`. Git checks + body prep live here; forge
# driving, create-vs-edit, and the surgery live in Lua (mux.skills.pr).

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_lib"))
import muxlib  # noqa: E402


def die(message: str):
    print(f"pr-window: {message}", file=sys.stderr)
    raise SystemExit(2)


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


def view_spec(args: argparse.Namespace):
    if args.win is not None:
        return {"win": args.win}
    if args.tab is not None:
        return {"tab": args.tab}
    return args.view


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="pr-window",
        description="Open forge's draft PR compose in the mux vcs view, pre-filled, unfocused.",
    )
    p.add_argument("--title", required=True, help="PR title (the # line)")
    p.add_argument("-F", "--file", default=None, help="read body from file ('-' = stdin)")
    p.add_argument("--target", default=None, help="branch or worktree the changes live in")
    p.add_argument("--root", type=Path, default=None, help="base repo (default: current project)")
    p.add_argument("--view", default="vcs", help="destination view name (default: vcs)")
    p.add_argument("--win", type=int, default=None, help="destination window id (overrides --view)")
    p.add_argument("--tab", type=int, default=None, help="destination tab number (overrides --view)")
    p.add_argument("-n", "--dry-run", action="store_true", help="print the plan; do not touch nvim")
    args = p.parse_args(argv)
    if not args.title.strip():
        p.error("--title cannot be empty")
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    base = args.root.resolve() if args.root else muxlib.current_root()
    try:
        root = muxlib.resolve_target(base, args.target)
        if muxlib.git_rc(root, "rev-parse", "--is-inside-work-tree") != 0:
            die(f"not a git repository: {root}")
        # Assume committed + clean; untracked per-machine noise is never part of a PR.
        if (
            muxlib.git_rc(root, "diff", "--quiet") != 0
            or muxlib.git_rc(root, "diff", "--cached", "--quiet") != 0
        ):
            die("uncommitted changes to tracked files; commit first (nvim-commit), then retry")

        branch = muxlib.maybe_output(["git", "-C", str(root), "rev-parse", "--abbrev-ref", "HEAD"])
        body = read_body(args)

        if args.dry_run:
            print(f"root: {root}")
            print(f"branch: {branch}")
            print(f"title: {args.title}")
            print("body:")
            for line in body:
                print(f"  {line}")
            return 0

        socket = muxlib.socket_for_root(root)
        res = muxlib.call(
            socket,
            {"op": "pr", "title": args.title, "body": body, "view": view_spec(args)},
        )
    except muxlib.MuxError as e:
        die(str(e))

    if not res.get("ok"):
        die(res.get("error", "pr driver failed"))
    mode = res.get("mode")
    if mode == "create":
        note = "draft PR compose"
    elif mode == "edit_filled":
        note = f"existing PR #{res.get('num', '?')} — filled empty description"
    elif mode == "edit_kept":
        note = f"existing PR #{res.get('num', '?')} — edit compose (left as-is)"
    else:
        note = mode or "ready"
    print(f"pr-window: vcs ready — {note} for {branch}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
