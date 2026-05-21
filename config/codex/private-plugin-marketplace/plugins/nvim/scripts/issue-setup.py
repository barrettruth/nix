#!/usr/bin/env python3

import datetime as dt
import json
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import TypedDict, cast

REPO = Path("/home/barrett/dev/neovim")
WORKTREES = REPO / ".worktrees"
STATE_ROOT = Path("/home/barrett/.local/state/codex-nvim/issues")
GH_REPO = "neovim/neovim"


class SetupError(Exception):
    pass


class NameLike(TypedDict, total=False):
    login: str
    name: str


class Actor(NameLike, total=False):
    pass


class NamedItem(NameLike, total=False):
    pass


class Comment(TypedDict, total=False):
    author: Actor
    body: str
    createdAt: str
    url: str


class Issue(TypedDict, total=False):
    number: int
    title: str
    state: str
    author: Actor
    body: str
    comments: list[Comment]
    labels: list[NamedItem]
    assignees: list[Actor]
    milestone: NamedItem | None
    url: str
    createdAt: str
    updatedAt: str
    closedAt: str | None


def die(message: str) -> None:
    raise SetupError(message)


def run(
    args: list[str], *, cwd: Path | None = None, stdout: Path | None = None
) -> None:
    out = stdout.open("w") if stdout else None
    try:
        _ = subprocess.run(args, cwd=cwd, check=True, text=True, stdout=out)
    finally:
        if out:
            out.close()


def output(args: list[str], *, cwd: Path | None = None) -> str:
    return subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


def normalize_issue(value: str) -> str:
    issue = value.removeprefix("#")
    if not issue.isdigit():
        die(f"expected numeric issue, got: {value}")
    return issue


def ensure_repo() -> None:
    if not REPO.is_dir():
        die(f"missing repo: {REPO}")
    remotes = output(["git", "remote"], cwd=REPO).splitlines()
    if "upstream" not in remotes:
        die("missing upstream remote in /home/barrett/dev/neovim")


def branch_exists(issue: str) -> bool:
    return (
        subprocess.run(
            ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{issue}"],
            cwd=REPO,
            check=False,
        ).returncode
        == 0
    )


def append_unique_line(path: Path, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    current = path.read_text() if path.exists() else ""
    if line in current.splitlines():
        return
    with path.open("a") as file:
        if current and not current.endswith("\n"):
            _ = file.write("\n")
        _ = file.write(f"{line}\n")


def exclude_path(cwd: Path) -> Path:
    git_dir = Path(output(["git", "rev-parse", "--absolute-git-dir"], cwd=cwd))
    return git_dir / "info" / "exclude"


def ensure_main_worktrees_ignored() -> None:
    append_unique_line(exclude_path(REPO), ".worktrees/")


def write_if_missing(path: Path, text: str) -> None:
    if not path.exists():
        _ = path.write_text(text)


def load_issue(path: Path) -> Issue:
    data = cast(object, json.loads(path.read_text()))
    if not isinstance(data, dict):
        die(f"unexpected issue JSON shape: {path}")
    return cast(Issue, data)


def actor_label(actor: Actor | None) -> str:
    if not actor:
        return "unknown"
    login = actor.get("login") or "unknown"
    name = actor.get("name")
    if name and name != login:
        return f"{name} (@{login})"
    return f"@{login}"


def item_names(items: Sequence[NameLike]) -> str:
    names = [item.get("name") or item.get("login") for item in items]
    return ", ".join(f"`{name}`" for name in names if name) or "none"


def issue_markdown(issue: Issue) -> str:
    number = issue.get("number", "")
    title = issue.get("title", "")
    state = issue.get("state", "")
    url = issue.get("url", "")
    body = issue.get("body") or "_No body captured._"
    labels = item_names(issue.get("labels", []))
    assignees = item_names(issue.get("assignees", []))
    milestone = issue.get("milestone")
    milestone_name = milestone.get("name") if milestone else None
    comments = issue.get("comments", [])

    lines = [
        f"# Neovim issue {number}",
        "",
        f"Title: {title}",
        f"State: {state}",
        f"URL: {url}",
        f"Author: {actor_label(issue.get('author'))}",
        f"Created: {issue.get('createdAt', '')}",
        f"Updated: {issue.get('updatedAt', '')}",
        f"Closed: {issue.get('closedAt') or 'n/a'}",
        f"Labels: {labels}",
        f"Assignees: {assignees}",
        f"Milestone: {milestone_name or 'none'}",
        "",
        "## Body",
        "",
        body,
        "",
        "## Comments",
        "",
    ]

    if not comments:
        lines.append("_No comments captured._")
    for index, comment in enumerate(comments, start=1):
        lines.extend(
            [
                f"### Comment {index}",
                "",
                f"Author: {actor_label(comment.get('author'))}",
                f"Created: {comment.get('createdAt', '')}",
                f"URL: {comment.get('url', '')}",
                "",
                comment.get("body") or "_No body captured._",
                "",
            ]
        )

    return "\n".join(lines).rstrip() + "\n"


def fetch_issue(issue: str, github_dir: Path) -> None:
    github_dir.mkdir(parents=True, exist_ok=True)
    fields = ",".join(
        [
            "number",
            "title",
            "state",
            "author",
            "body",
            "comments",
            "labels",
            "assignees",
            "milestone",
            "url",
            "createdAt",
            "updatedAt",
            "closedAt",
        ]
    )
    run(
        ["gh", "issue", "view", issue, "--repo", GH_REPO, "--json", fields],
        stdout=github_dir / "issue.json",
    )
    issue_data = load_issue(github_dir / "issue.json")
    _ = (github_dir / "issue.md").write_text(issue_markdown(issue_data))


def create_wiki(issue: str, worktree: Path, wiki: Path) -> None:
    for path in [
        wiki / "sources/github",
        wiki / "sources/commands",
        wiki / "evidence",
        wiki / "logs",
    ]:
        path.mkdir(parents=True, exist_ok=True)

    now = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    write_if_missing(
        wiki / "index.md",
        f"""# Neovim issue {issue}

Issue: https://github.com/neovim/neovim/issues/{issue}
Worktree: {worktree}
Phase: setup complete; investigation/report only
Last updated: {now}

## Start Here
- [Report](report.md)
- [Sources](sources.md)

## Evidence
- [History](evidence/history.md)
- [Repro](evidence/repro.md)

## Open Questions
- Pending investigation.
""",
    )
    write_if_missing(
        wiki / "report.md",
        f"# Neovim issue {issue}\n\nPending history and reproduction evidence.\n",
    )
    write_if_missing(
        wiki / "sources.md",
        f"""# Sources

- Issue JSON: [sources/github/issue.json](sources/github/issue.json)
- Issue readable snapshot: [sources/github/issue.md](sources/github/issue.md)

Commands:

```sh
gh issue view {issue} --repo {GH_REPO} --json ...
```
""",
    )
    with (wiki / "log.md").open("a") as file:
        _ = file.write(
            f"\n## [{now}] setup\nCreated issue wiki and worktree pointer.\n"
        )
    write_if_missing(wiki / "evidence/history.md", "# History\n\nPending.\n")
    write_if_missing(wiki / "evidence/repro.md", "# Reproduction\n\nPending.\n")


def ensure_ignored(worktree: Path) -> None:
    append_unique_line(exclude_path(worktree), ".codex/")


def write_pointers(issue: str, worktree: Path, wiki: Path) -> None:
    (worktree / ".codex" / "repros" / "script").mkdir(parents=True, exist_ok=True)

    pointer = worktree / ".codex" / "issue-wiki"
    pointer.parent.mkdir(parents=True, exist_ok=True)
    _ = pointer.write_text(
        f"""issue={issue}
wiki={wiki}
report={wiki / "report.md"}
index={wiki / "index.md"}
"""
    )

    current = WORKTREES / ".codex" / "current"
    current.parent.mkdir(parents=True, exist_ok=True)
    _ = current.write_text(
        f"""issue={issue}
worktree={worktree}
wiki={wiki}
report={wiki / "report.md"}
index={wiki / "index.md"}
"""
    )


def setup(issue: str) -> tuple[Path, Path]:
    ensure_repo()
    ensure_main_worktrees_ignored()
    worktree = WORKTREES / issue
    wiki = STATE_ROOT / issue

    if worktree.exists():
        die(f"worktree exists: {worktree}")
    if branch_exists(issue):
        die(f"branch exists: {issue}")

    fetch_issue(issue, wiki / "sources/github")
    run(["git", "fetch", "upstream", "master"], cwd=REPO)
    run(
        ["git", "worktree", "add", "-b", issue, str(worktree), "upstream/master"],
        cwd=REPO,
    )
    create_wiki(issue, worktree, wiki)
    ensure_ignored(worktree)
    write_pointers(issue, worktree, wiki)
    return worktree, wiki


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: issue-setup.py <issue>", file=sys.stderr)
        return 2

    try:
        issue = normalize_issue(argv[0])
        worktree, wiki = setup(issue)
    except SetupError as exc:
        print(f"nvim issue setup: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(
            f"nvim issue setup: command failed with exit {exc.returncode}",
            file=sys.stderr,
        )
        return exc.returncode

    print(f"worktree={worktree}")
    print(f"wiki={wiki}")
    print(f"index={wiki / 'index.md'}")
    print(f"report={wiki / 'report.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
