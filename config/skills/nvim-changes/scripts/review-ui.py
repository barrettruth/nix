#!/usr/bin/env python3

import argparse
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


def tmux(*args: str) -> None:
    _ = subprocess.run(["tmux", *args], check=True, text=True)


def tmux_out(*args: str) -> str:
    return out(["tmux", *args])


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


def attached_session() -> str:
    for line in out(["tmux", "list-clients", "-F", "#{client_session}"]).splitlines():
        if line.strip():
            return line.strip()
    return tmux_out("display-message", "-p", "#{session_name}")


def session_project(session: str) -> Path | None:
    path = out(["tmux", "show-options", "-qv", "-t", session, "@mux-project-path"])
    return Path(path).resolve() if path else None


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
    # No target: review the project the user is currently attached to.
    proj = session_project(attached_session())
    if proj and git_ok(proj, "rev-parse", "--is-inside-work-tree"):
        return toplevel(proj) or proj
    here = toplevel(Path.cwd())
    if here:
        return here
    die("no target given and current session is not in a git worktree")
    raise AssertionError  # unreachable


def default_base_ref(wt: Path) -> str:
    head = git(wt, "rev-parse", "--abbrev-ref", "origin/HEAD")
    if head:
        return head
    for ref in ("origin/main", "origin/master", "main", "master"):
        if git_ok(wt, "rev-parse", "--verify", "--quiet", ref):
            return ref
    return "origin/main"


def compute_base(wt: Path) -> str:
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


def find_vcs_window(session: str, root: Path) -> str | None:
    fmt = (
        "#{window_index}\t#{window_name}\t#{pane_current_command}\t#{pane_current_path}"
    )
    for row in tmux_out("list-windows", "-t", session, "-F", fmt).splitlines():
        parts = row.split("\t")
        if len(parts) < 4:
            continue
        index, name, command, path = parts[:4]
        if name == "vcs" and command == "nvim" and Path(path).resolve() == root:
            return f"{session}:{index}"
    return None


def wait_for_nvim(target: str) -> None:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if (
            out(
                [
                    "tmux",
                    "display-message",
                    "-p",
                    "-t",
                    target,
                    "#{pane_current_command}",
                ]
            )
            == "nvim"
        ):
            return
        time.sleep(0.05)
    raise RuntimeError(f"vcs window nvim did not start: {target}")


def open_vcs_review(session: str, root: Path, base: str) -> str:
    target = find_vcs_window(session, root)
    if target is None:
        index = tmux_out(
            "new-window",
            "-d",
            "-t",
            f"{session}:",
            "-c",
            str(root),
            "-n",
            "vcs",
            "-P",
            "-F",
            "#{window_index}",
            "nvim",
        )
        target = f"{session}:{index}"
        wait_for_nvim(target)
    tmux("send-keys", "-t", target, "Escape")
    tmux(
        "send-keys",
        "-t",
        target,
        f":Diff review ++layout=unified {base} | only",
        "Enter",
    )
    return target


def populate_edit(session: str, root: Path, files: list[Path]) -> None:
    run(
        [
            "python3",
            str(EDIT_HELPER),
            "--session",
            session,
            "--root",
            str(root),
            "--limit",
            str(len(files)),
            *[str(p) for p in files],
        ],
        cwd=root,
    )


def focus(target: str) -> None:
    session = target.split(":", 1)[0]
    tmux("select-window", "-t", target)
    for client in out(
        ["tmux", "list-clients", "-t", session, "-F", "#{client_name}"]
    ).splitlines():
        if client.strip():
            _ = subprocess.run(
                ["tmux", "switch-client", "-c", client.strip(), "-t", target],
                check=False,
            )
            break


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

    session = attached_session()
    vcs_target = open_vcs_review(session, wt, base)
    populate_edit(session, wt, files)
    focus(vcs_target)
    print(
        f"review-ui: {session} reviewing {branch} ({wt}) vs {base[:10]} — "
        f"{len(files)} files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
