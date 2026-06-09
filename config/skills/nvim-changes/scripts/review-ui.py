#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


EDIT_HELPER = Path(
    "/home/barrett/.config/nix/config/skills/nvim-edit/scripts/edit-window.py"
)

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


def run(
    args: list[str], *, cwd: Path | None = None, check: bool = True
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, check=check, text=True)


def out(args: list[str]) -> str:
    proc = subprocess.run(
        args, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def git(repo: Path, *args: str) -> str:
    return out(["git", "-C", str(repo), *args])


def git_ok(repo: Path, *args: str) -> bool:
    return (
        subprocess.run(
            ["git", "-C", str(repo), *args],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def die(message: str) -> None:
    print(f"review-ui: {message}", file=sys.stderr)
    raise SystemExit(2)


# --- target resolution -------------------------------------------------------


def main_repo(start: Path) -> Path | None:
    common = git(start, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return None
    return Path(common).resolve().parent


def worktree_for_branch(repo: Path, branch: str) -> Path | None:
    block: dict[str, str] = {}
    rows = git(repo, "worktree", "list", "--porcelain").splitlines() + [""]
    for line in rows:
        if line.startswith("worktree "):
            block = {"path": line[len("worktree ") :]}
        elif line.startswith("branch "):
            block["branch"] = line[len("branch ") :]
        elif line == "" and block:
            if block.get("branch") == f"refs/heads/{branch}":
                return Path(block["path"]).resolve()
            block = {}
    return None


def ensure_branch_worktree(repo: Path, branch: str) -> Path:
    existing = worktree_for_branch(repo, branch)
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
                "git",
                "-C",
                str(repo),
                "worktree",
                "add",
                "--track",
                "-b",
                branch,
                str(wt),
                f"origin/{branch}",
            ]
        )
    return wt


def toplevel(path: Path) -> Path | None:
    top = git(path, "rev-parse", "--show-toplevel")
    return Path(top).resolve() if top else None


def resolve_worktree(repo: Path | None, target: str | None) -> Path:
    if target:
        candidate = Path(target).expanduser()
        if candidate.is_dir() and git_ok(
            candidate, "rev-parse", "--is-inside-work-tree"
        ):
            return toplevel(candidate) or candidate.resolve()
        if repo is None:
            die(f"cannot resolve branch '{target}': pass --repo <repo-root>")
        return ensure_branch_worktree(repo, target)  # type: ignore[arg-type]
    # No target: review the current project (the cwd's git worktree).
    here = toplevel(Path.cwd())
    if here:
        return here
    die("no target given and the current directory is not a git worktree")
    raise AssertionError  # unreachable


def default_base_ref(wt: Path) -> str:
    # Prefer the real mainline (upstream) over a possibly-stale fork (origin).
    for ref in ("upstream/HEAD", "upstream/main", "upstream/master",
                "origin/HEAD", "origin/main", "origin/master", "main", "master"):
        if git_ok(wt, "rev-parse", "--verify", "--quiet", ref):
            return ref
    return "origin/main"


def compute_base(wt: Path) -> str:
    # Refresh tracking refs first so the base is never stale.
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


# --- live UI (in the attached session) ---------------------------------------


def populate_edit(session: str | None, root: Path, files: list[Path]) -> None:
    args = ["python3", str(EDIT_HELPER), "--root", str(root)]
    if session:
        args += ["--session", session]
    args += ["--limit", str(len(files)), *[str(p) for p in files]]
    run(args, cwd=root)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Review an agent's changes in mux: resolve target -> worktree, "
        "compute base, build the vcs :Diff review + edit quickfix in the current session."
    )
    parser.add_argument(
        "--repo", type=Path, default=None, help="repo root for a branch target"
    )
    parser.add_argument(
        "target",
        nargs="?",
        default=None,
        help="branch name, worktree path, or omit to review your current project",
    )
    return parser.parse_args(argv)


def env_socket_for_root(root: Path) -> str:
    # The project's nvim server: $NVIM is auto-set in the server's :terminal to
    # its socket. Returns "" unless that server's cwd is `root` (e.g. a worktree
    # whose root differs from the server cwd).
    socket = os.environ.get("NVIM")
    if not socket or not os.path.exists(socket):
        return ""
    proc = subprocess.run(
        ["nvim", "--server", socket, "--remote-expr", "getcwd()"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode == 0 and Path(proc.stdout.strip()).resolve() == root.resolve():
        return socket
    return ""


def open_vcs_review_rpc(socket: str, base: str) -> None:
    keys = f"<C-\\><C-n>:Diff review ++layout=unified {base} | only<CR>"
    subprocess.run(
        ["nvim", "--server", socket, "--remote-send", keys],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not EDIT_HELPER.exists():
        die(f"missing edit helper: {EDIT_HELPER}")
    repo = args.repo.resolve() if args.repo else main_repo(Path.cwd())
    wt = resolve_worktree(repo, args.target)
    branch = git(wt, "rev-parse", "--abbrev-ref", "HEAD") or "(detached)"
    base = compute_base(wt)
    files = changed_files(wt, base)
    if not files:
        print(f"review-ui: no reviewable changes in {branch} ({wt}) vs {base[:10]}")
        return 0

    socket = env_socket_for_root(wt)
    if not socket:
        die(f"no nvim server for {wt} (is $NVIM set / mux running?)")
    open_vcs_review_rpc(socket, base)
    populate_edit(None, wt, files)
    print(
        f"review-ui: nvim server reviewing {branch} ({wt}) vs "
        f"{base[:10]} — {len(files)} files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
