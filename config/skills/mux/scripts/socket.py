#!/usr/bin/env python

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_lib"))
import muxlib  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Print the mux Neovim server socket for a project."
    )
    parser.add_argument("--root", help="repo root; defaults to the cwd's")
    args = parser.parse_args()

    root = muxlib.normalize_path(args.root) if args.root else muxlib.current_root()
    try:
        print(muxlib.socket_for_root(root, spawn=False))
    except muxlib.MuxError as err:
        print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
