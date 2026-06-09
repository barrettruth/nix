#!/usr/bin/env python

import argparse
import json
import os
import random
import re
import shlex
import subprocess
import sys
import tempfile
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


HOME = Path.home()
EDIT_WINDOW_NAME = "edit"
DEFAULT_LIMIT = 8

STOPWORDS = {
    "a",
    "about",
    "all",
    "and",
    "are",
    "around",
    "at",
    "by",
    "current",
    "edit",
    "file",
    "files",
    "for",
    "from",
    "in",
    "into",
    "me",
    "of",
    "on",
    "open",
    "please",
    "project",
    "repo",
    "repository",
    "related",
    "show",
    "that",
    "the",
    "these",
    "thing",
    "things",
    "this",
    "to",
    "up",
    "where",
    "which",
    "workspace",
    "with",
}

MULTIPLE_TOKENS = {
    "all",
    "both",
    "changed",
    "changes",
    "dirty",
    "files",
    "many",
    "matches",
    "modified",
    "multiple",
    "related",
    "several",
    "staged",
    "these",
    "unstaged",
    "untracked",
}

SINGULAR_TOKENS = {
    "one",
    "single",
}

TOKEN_ALIASES = {
    "bar": {"bar", "mux", "tmux", "waybar"},
    "browser": {"browser", "chromium"},
    "chrome": {"chromium"},
    "code": {"nvim", "neovim", "vim", "edit"},
    "codex": {"codex", "agent", "ai"},
    "completion": {"completion", "complete", "cmp"},
    "desktop": {"desktop", "hyprland", "waybar", "dunst"},
    "forge": {"forge", "forgejo", "vps", "gitea"},
    "gpg": {"gpg", "gnupg", "gpgagent"},
    "hypr": {"hypr", "hyprland", "hypridle", "hyprlock", "hyprpaper"},
    "neovim": {"neovim", "nvim", "vim"},
    "nix": {"nix", "nixos", "flake"},
    "shell": {"shell", "zsh", "bash"},
    "terminal": {"terminal", "ghostty", "tmux"},
    "theme": {"theme", "themes", "midnight", "daylight"},
    "tmux": {"tmux", "mux", "mosaic"},
    "vim": {"vim", "nvim", "neovim"},
}

DIRTY_TOKENS = {
    "changed",
    "changes",
    "dirty",
    "modified",
    "staged",
    "unstaged",
    "untracked",
}

TOKEN_RE = re.compile(r"[A-Za-z0-9]+")
PATH_TOKEN_RE = re.compile(r"(?:~|/|\./|\../)[^\s,;]+")


@dataclass(frozen=True)
class Candidate:
    path: Path
    score: float
    reason: str


@dataclass(frozen=True)
class QueryIntent:
    wants_file: bool
    wants_random: bool
    wants_multiple: bool
    wants_singular: bool


@dataclass(frozen=True)
class Window:
    name: str
    index: str
    command: str
    pane_id: str
    pane_pid: str
    panes: int


def run(
    args: Iterable[str],
    *,
    check: bool = True,
    capture: bool = False,
    input_text: str | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        check=check,
        text=True,
        input=input_text,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def output(args: Iterable[str]) -> str:
    return run(args, capture=True).stdout.rstrip("\n")


def maybe_output(args: Iterable[str]) -> str:
    proc = subprocess.run(
        list(args),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.rstrip("\n")


def normalize_path(path: str | Path) -> Path:
    return Path(path).expanduser().resolve()


def git_root(path: Path) -> Path:
    root = maybe_output(["git", "-C", str(path), "rev-parse", "--show-toplevel"])
    return normalize_path(root) if root else path


def current_root() -> Path:
    return git_root(Path.cwd())


def rel(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def tokenize(value: str) -> list[str]:
    return [token.lower() for token in TOKEN_RE.findall(value)]


def query_tokens(query: str) -> list[str]:
    seen: set[str] = set()
    tokens: list[str] = []
    for token in tokenize(query):
        if token in STOPWORDS or token in seen:
            continue
        seen.add(token)
        tokens.append(token)
    return tokens


def expanded_tokens(tokens: Iterable[str]) -> set[str]:
    expanded: set[str] = set()
    for token in tokens:
        expanded.add(token)
        expanded.update(TOKEN_ALIASES.get(token, set()))
    return expanded


def split_path_tokens(path: str) -> list[str]:
    return tokenize(path)


def git_files(root: Path) -> list[Path]:
    files = maybe_output(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
        ]
    )
    if files:
        return [root / line for line in files.splitlines() if line]
    fallback = maybe_output(["rg", "--files", str(root)])
    return [Path(line) for line in fallback.splitlines() if line]


def dirty_files(root: Path) -> list[Path]:
    status = maybe_output(["git", "-C", str(root), "status", "--porcelain=v1", "-uall"])
    paths: list[Path] = []
    for line in status.splitlines():
        if not line:
            continue
        value = line[3:]
        if " -> " in value:
            value = value.rsplit(" -> ", 1)[1]
        paths.append(root / value)
    return paths


def clean_path_token(value: str) -> str:
    return value.strip().rstrip(".,;:!?)]}'\"")


def pathlike_terms(query: str) -> list[str]:
    terms: list[str] = []
    seen: set[str] = set()
    for part in [query, *query.split(), *PATH_TOKEN_RE.findall(query)]:
        candidates = [part]
        candidates.extend(PATH_TOKEN_RE.findall(part))
        for candidate in candidates:
            cleaned = clean_path_token(candidate)
            if not cleaned:
                continue
            looks_pathlike = (
                any(sep in cleaned for sep in ("/", ".", "~"))
                or Path(cleaned).is_absolute()
            )
            if not looks_pathlike or cleaned in seen:
                continue
            terms.append(cleaned)
            seen.add(cleaned)
    return terms


def directory_files(path: Path) -> list[Path]:
    try:
        return sorted(
            child
            for child in path.iterdir()
            if child.is_file() and os.access(child, os.R_OK)
        )
    except OSError:
        return []


def implied_path_terms(query_words: set[str]) -> list[str]:
    tmp_context = {"dir", "directory", "folder", "random", "root"}
    if "tmp" in query_words and query_words & tmp_context:
        return [tempfile.gettempdir()]
    return []


def query_intent(raw_query: str) -> QueryIntent:
    words = set(tokenize(raw_query))
    wants_random = "random" in words
    wants_file = bool(words & {"file", "files", "random"})
    wants_multiple = bool(words & MULTIPLE_TOKENS)
    wants_singular = bool(words & SINGULAR_TOKENS)
    if "file" in words and "files" not in words and not wants_multiple:
        wants_singular = True
    if wants_random and "files" not in words and not wants_multiple:
        wants_singular = True
    return QueryIntent(
        wants_file=wants_file,
        wants_random=wants_random,
        wants_multiple=wants_multiple,
        wants_singular=wants_singular,
    )


def effective_limit(raw_query: str, requested_limit: int | None) -> int:
    if requested_limit is not None:
        return max(1, requested_limit)
    intent = query_intent(raw_query)
    if intent.wants_singular:
        return 1
    return DEFAULT_LIMIT


def project_files(root: Path) -> list[Path]:
    return [normalize_path(path) for path in git_files(root) if path.is_file()]


def random_project_files(root: Path, limit: int) -> list[Path]:
    files = project_files(root)
    if not files:
        return []
    count = min(max(1, limit), len(files))
    if count == 1:
        return [random.choice(files)]
    return random.sample(files, count)


def explicit_paths(root: Path, query: str) -> list[Path]:
    matches: list[Path] = []
    query_words = set(tokenize(query))
    wants_file = bool(query_words & {"file", "files", "random"})
    wants_random = "random" in query_words
    terms = pathlike_terms(query)
    term_paths = {normalize_path(term) for term in terms if not term.startswith("-")}
    for implied in implied_path_terms(query_words):
        implied_path = normalize_path(implied)
        if implied_path not in term_paths:
            terms.append(implied)
            term_paths.add(implied_path)
    for part in terms:
        if not part or part.startswith("-"):
            continue
        raw = Path(part).expanduser()
        pattern = raw if raw.is_absolute() else root / raw
        globbed = (
            sorted(pattern.parent.glob(pattern.name))
            if any(c in part for c in "*?[")
            else []
        )
        candidates = globbed or [pattern]
        for candidate in candidates:
            if not candidate.exists():
                continue
            normalized = normalize_path(candidate)
            if normalized.is_dir() and wants_file:
                files = directory_files(normalized)
                if wants_random and files:
                    matches.append(random.choice(files))
                else:
                    matches.extend(files)
            else:
                matches.append(normalized)
    return unique_paths(matches)


def unique_paths(paths: Iterable[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        normalized = normalize_path(path)
        if normalized in seen:
            continue
        result.append(normalized)
        seen.add(normalized)
    return result


def score_file(
    root: Path, path: Path, tokens: list[str], raw_query: str
) -> Candidate | None:
    relpath = rel(root, path)
    path_text = " ".join(split_path_tokens(relpath))
    path_tokens = set(split_path_tokens(relpath))
    basename = path.name.lower()
    stem = path.stem.lower()
    expanded = expanded_tokens(tokens)
    score = 0.0
    hits: list[str] = []
    matched_tokens: set[str] = set()

    compact_query = " ".join(tokens)
    if compact_query and compact_query in path_text:
        score += 18
        hits.append("phrase")

    for token in tokens:
        aliases = TOKEN_ALIASES.get(token, {token})
        token_hit = False
        for alias in aliases:
            if alias in path_tokens:
                score += 9 if alias == token else 6
                token_hit = True
            elif alias in relpath.lower():
                score += 4 if alias == token else 2.5
                token_hit = True
            if alias == basename or alias == stem:
                score += 8
                token_hit = True
        if token_hit:
            hits.append(token)
            matched_tokens.add(token)

    if basename in expanded or stem in expanded:
        score += 10
        hits.append("basename")

    if any(token in path_tokens for token in {"test", "spec"}):
        if "test" in expanded or "spec" in expanded:
            score += 7
        else:
            score -= 2

    if "config" in expanded and (
        "config" in path_tokens or path.suffix in {".conf", ".toml", ".nix"}
    ):
        score += 5
    if "script" in expanded or "command" in expanded:
        if "scripts" in path_tokens or path.suffix in {".py", ".sh"}:
            score += 4

    depth = len(path.relative_to(root).parts) if path.is_relative_to(root) else 8
    score -= min(depth, 8) * 0.15

    if score <= 0:
        return None
    if len(tokens) > 1:
        coverage = len(matched_tokens) / len(tokens)
        score *= 0.45 + (coverage * 0.55)
    reason = ", ".join(dict.fromkeys(hits)) or raw_query
    return Candidate(path=path, score=score, reason=reason)


def content_hits(root: Path, tokens: list[str]) -> dict[Path, int]:
    meaningful = [token for token in tokens if len(token) >= 3][:5]
    if not meaningful:
        return {}
    hits: dict[Path, int] = defaultdict(int)
    for token in meaningful:
        args = [
            "rg",
            "--files-with-matches",
            "--ignore-case",
            "--hidden",
            "--glob",
            "!.git",
            "--glob",
            "!result",
            "--glob",
            "!result-*",
            "-e",
            token,
            str(root),
        ]
        try:
            proc = subprocess.run(
                args,
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            continue
        if proc.returncode not in (0, 1):
            continue
        for line in proc.stdout.splitlines():
            path = normalize_path(line)
            if path.is_file():
                hits[path] += 1
    return hits


def resolve_files(root: Path, query_parts: list[str], limit: int) -> list[Candidate]:
    raw_query = " ".join(query_parts).strip()
    if not raw_query:
        return [Candidate(root, 1, "project")]

    explicit = explicit_paths(root, raw_query)
    if explicit:
        return [Candidate(path, 100, "explicit path") for path in explicit[:limit]]

    intent = query_intent(raw_query)
    if intent.wants_random and intent.wants_file:
        files = random_project_files(root, limit)
        if files:
            return [Candidate(path, 100, "random project file") for path in files]

    tokens = query_tokens(raw_query)
    if not tokens:
        return [Candidate(root, 1, "project")]

    expanded = expanded_tokens(tokens)
    if expanded & DIRTY_TOKENS:
        return [
            Candidate(path, 100, "dirty working tree file")
            for path in dirty_files(root)[: max(limit, DEFAULT_LIMIT)]
        ]

    scored: dict[Path, Candidate] = {}
    for path in git_files(root):
        if not path.is_file():
            continue
        candidate = score_file(root, normalize_path(path), tokens, raw_query)
        if candidate:
            scored[candidate.path] = candidate

    for path, count in content_hits(root, tokens).items():
        existing = scored.get(path)
        boost = 2 + (4 * count)
        if existing:
            scored[path] = Candidate(
                path, existing.score + boost, existing.reason + ", content"
            )
        else:
            scored[path] = Candidate(path, boost, "content")

    candidates = sorted(
        scored.values(),
        key=lambda item: (-item.score, len(rel(root, item.path)), rel(root, item.path)),
    )
    if not candidates:
        return [Candidate(root, 1, "project")]
    return candidates[:limit]


def nvim_command(root: Path, query: str, candidates: list[Candidate]) -> str:
    script = remote_script(root, query, candidates)
    args = ["nvim", f"+luafile {script}"]
    return f"cd {shlex.quote(str(root))} && exec " + " ".join(
        shlex.quote(arg) for arg in args
    )


def vim_lua_string(value: str) -> str:
    return json.dumps(value)


def remote_script(root: Path, query: str, candidates: list[Candidate]) -> Path:
    files = [candidate.path for candidate in candidates if candidate.path != root]
    items = [
        {
            "filename": str(candidate.path),
            "lnum": 1,
            "col": 1,
            "text": "",
        }
        for candidate in candidates
        if candidate.path != root and len(files) > 1
    ]
    payload = {
        "title": "edit",
        "files": [str(p) for p in files],
        "items": items,
        "root": str(root),
    }
    fd, script_name = tempfile.mkstemp(prefix=f"open-{os.getuid()}-", suffix=".lua")
    os.close(fd)
    script = Path(script_name)
    script.write_text(
        "\n".join(
            [
                f"local payload = vim.json.decode({vim_lua_string(json.dumps(payload))})",
                "local function reset_editor_state()",
                "  pcall(vim.fn.setreg, '/', '')",
                "  pcall(vim.fn.histdel, 'search')",
                "  pcall(function() vim.v.errmsg = '' end)",
                "  pcall(vim.cmd, 'silent! nohlsearch')",
                "  pcall(vim.cmd, 'silent! messages clear')",
                "  pcall(function() vim.v.errmsg = '' end)",
                "  pcall(vim.api.nvim_echo, {{ ' ', 'Normal' }}, false, {})",
                "end",
                "reset_editor_state()",
                "pcall(vim.cmd, 'silent! only')",
                "local files = payload.files or {}",
                "if #files == 0 then",
                "  vim.cmd('edit ' .. vim.fn.fnameescape(payload.root))",
                "else",
                "  vim.cmd('%argdelete')",
                "  vim.cmd('args ' .. table.concat(vim.tbl_map(vim.fn.fnameescape, files), ' '))",
                "  vim.cmd('edit ' .. vim.fn.fnameescape(files[1]))",
                "  for i = 2, #files do vim.cmd('badd ' .. vim.fn.fnameescape(files[i])) end",
                "end",
                "local items = payload.items or {}",
                "vim.fn.setqflist({}, 'r', { title = payload.title, items = items })",
                "if #items > 1 then vim.cmd('botright copen') vim.cmd('wincmd p') else vim.cmd('cclose') end",
                "reset_editor_state()",
                "vim.cmd('redraw!')",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    return script


def remote_into_nvim(
    socket: str, root: Path, query: str, candidates: list[Candidate]
) -> bool:
    script = remote_script(root, query, candidates)
    expr = f"execute('luafile ' . fnameescape({vim_lua_string(str(script))}))"
    proc = subprocess.run(
        ["nvim", "--server", socket, "--remote-expr", expr],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc.returncode == 0


def print_plan(root: Path, query: str, candidates: list[Candidate]) -> None:
    print(f"root: {root}")
    print(f"query: {query}")
    for candidate in candidates:
        print(f"{candidate.score:.1f}\t{rel(root, candidate.path)}\t{candidate.reason}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="edit",
        description="Populate the mux edit window from a natural-language file target.",
    )
    parser.add_argument(
        "-n", "--dry-run", action="store_true", help="print the resolved files"
    )
    parser.add_argument(
        "-l", "--limit", type=int, default=None, help="maximum files to populate"
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="repository root for the edit window (default: current mux project)",
    )
    parser.add_argument("query", nargs=argparse.REMAINDER)
    return parser.parse_args(argv)


def env_socket_for_root(root: Path) -> str:
    # The project's nvim server: $NVIM is auto-set in the server's :terminal to
    # its socket. Returns "" unless that server's cwd is `root`.
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
    if proc.returncode == 0 and normalize_path(proc.stdout.strip()) == root:
        return socket
    return ""


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = args.root.resolve() if args.root else current_root()
    query_parts = args.query
    query = " ".join(query_parts).strip()
    candidates = resolve_files(root, query_parts, effective_limit(query, args.limit))

    if args.dry_run:
        print_plan(root, query, candidates)
        return 0

    socket = env_socket_for_root(root)
    if not socket:
        print(
            f"edit: no nvim server for {root} (is $NVIM set / mux running?)",
            file=sys.stderr,
        )
        return 1
    return 0 if remote_into_nvim(socket, root, query, candidates) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
