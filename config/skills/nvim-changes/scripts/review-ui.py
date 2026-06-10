#!/usr/bin/env python3

# Open an agent's changes for review in mux: the `vcs` view gets a unified
# `:Diff review`, the `edit` view gets a quickfix of the changed files. Target
# resolution + base/diff computation live here; the view work is mux.skills.review.

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_lib"))
import muxlib  # noqa: E402

JUNK_TOP = {
    ".git",
    ".codex",
    ".agents",
    ".worktrees",
    "build",
    ".deps",
    ".cmake",
    ".tmp",
    ".direnv",
    "result",
}


def die(message: str):
    print(f"review-ui: {message}", file=sys.stderr)
    raise SystemExit(2)


def run(args: list[str], *, check: bool = True) -> None:
    subprocess.run(args, check=check, text=True)


def git(repo: Path, *args: str) -> str:
    return muxlib.maybe_output(["git", "-C", str(repo), *args])


def git_ok(repo: Path, *args: str) -> bool:
    return muxlib.git_rc(Path(repo), *args) == 0


# --- target resolution -------------------------------------------------------


def main_repo(start: Path) -> Path | None:
    common = git(start, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return None
    return Path(common).resolve().parent


def toplevel(path: Path) -> Path | None:
    top = git(path, "rev-parse", "--show-toplevel")
    return Path(top).resolve() if top else None


def ensure_branch_worktree(repo: Path, branch: str) -> Path:
    existing = muxlib.worktree_for_branch(repo, branch)
    if existing:
        return existing  # active branch: reuse in place (keeps uncommitted work)
    wt = (repo / ".worktrees" / f"review-{branch.replace('/', '-')}").resolve()
    if wt.is_dir():
        return wt
    if git_ok(repo, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"):
        run(["git", "-C", str(repo), "worktree", "add", str(wt), branch])
    else:
        run(["git", "-C", str(repo), "fetch", "--quiet", "origin", branch], check=False)
        run(
            [
                "git", "-C", str(repo), "worktree", "add", "--track",
                "-b", branch, str(wt), f"origin/{branch}",
            ]
        )
    return wt


def resolve_worktree(repo: Path | None, target: str | None) -> Path:
    if target:
        candidate = Path(target).expanduser()
        if candidate.is_dir() and git_ok(candidate, "rev-parse", "--is-inside-work-tree"):
            return toplevel(candidate) or candidate.resolve()
        if repo is None:
            die(f"cannot resolve branch '{target}': pass --repo <repo-root>")
        return ensure_branch_worktree(repo, target)
    here = toplevel(Path.cwd())
    if here:
        return here
    die("no target given and the current directory is not a git worktree")
    raise AssertionError  # unreachable


def default_base_ref(wt: Path) -> str:
    for ref in ("upstream/HEAD", "upstream/main", "upstream/master",
                "origin/HEAD", "origin/main", "origin/master", "main", "master"):
        if git_ok(wt, "rev-parse", "--verify", "--quiet", ref):
            return ref
    return "origin/main"


def compute_base(wt: Path) -> str:
    run(["git", "-C", str(wt), "fetch", "-q", "--all"], check=False)
    base = git(wt, "merge-base", "HEAD", default_base_ref(wt))
    return base or git(wt, "rev-parse", "HEAD")


def changed_files(wt: Path, base: str) -> list[Path]:
    rels = git(wt, "diff", "--name-only", base).splitlines()
    rels += git(wt, "ls-files", "--others", "--exclude-standard").splitlines()
    files: list[Path] = []
    seen: set[Path] = set()
    for rel in rels:
        if not rel or rel.split("/", 1)[0] in JUNK_TOP:
            continue
        path = (wt / rel).resolve()
        if path in seen or not path.exists():
            continue
        seen.add(path)
        files.append(path)
    return files


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Review an agent's changes in mux: vcs :Diff review + edit quickfix."
    )
    parser.add_argument("--repo", type=Path, default=None, help="repo root for a branch target")
    parser.add_argument(
        "--layout",
        choices=["unified", "stacked", "split"],
        default="unified",
        help="diff layout for the vcs :Diff review (default: unified)",
    )
    parser.add_argument(
        "target", nargs="?", default=None,
        help="branch name, worktree path, or omit to review your current project",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    repo = args.repo.resolve() if args.repo else main_repo(Path.cwd())
    wt = resolve_worktree(repo, args.target)
    branch = git(wt, "rev-parse", "--abbrev-ref", "HEAD") or "(detached)"
    base = compute_base(wt)
    files = changed_files(wt, base)
    if not files:
        print(f"review-ui: no reviewable changes in {branch} ({wt}) vs {base[:10]}")
        return 0

    items = [{"filename": str(p), "lnum": 1, "col": 1, "text": ""} for p in files]
    try:
        socket = muxlib.socket_for_root(wt)
        res = muxlib.call(
            socket,
            {
                "op": "review",
                "base": base,
                "files": [str(p) for p in files],
                "items": items,
                "root": str(wt),
                "layout": args.layout,
            },
        )
    except muxlib.MuxError as e:
        die(str(e))
    if not res.get("ok"):
        die(res.get("error", "review driver failed"))
    print(
        f"review-ui: reviewing {branch} ({wt}) vs {base[:10]} — {len(files)} files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
