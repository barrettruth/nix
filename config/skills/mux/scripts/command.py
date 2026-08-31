#!/usr/bin/env python

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_lib"))
import muxlib  # noqa: E402  # ty: ignore[unresolved-import]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run an Ex command in a named view of a mux Neovim session."
    )
    _ = parser.add_argument("command", help="Ex command, without a leading colon")
    _ = parser.add_argument("--root", help="repo root; defaults to the cwd's")
    _ = parser.add_argument("--view", default="edit", help="mux view; defaults to edit")
    args = parser.parse_args()

    root = muxlib.normalize_path(args.root) if args.root else muxlib.current_root()

    try:
        socket = muxlib.socket_for_root(root, spawn=False)
        result = muxlib.call(
            socket,
            {
                "op": "command",
                "command": args.command,
                "view": args.view,
            },
        )
    except muxlib.MuxError as err:
        print(err, file=sys.stderr)
        return 1

    if not result.get("ok"):
        print(result.get("error", "command failed"), file=sys.stderr)
        return 1

    print(f"{result['view']}\t{result['buffer']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
