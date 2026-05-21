#!/usr/bin/env python3
import json
import shlex
import sys
from pathlib import Path

NVIM_ROOT = Path("/home/barrett/dev/neovim")

GIT_BLOCKED = {
    "commit",
    "commit-tree",
    "push",
    "send-pack",
    "c",
    "cane",
    "pu",
    "acp",
}

GIT_GLOBAL_OPTIONS_WITH_VALUE = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
}

GH_GLOBAL_OPTIONS_WITH_VALUE = {
    "-R",
    "--repo",
    "--hostname",
    "--config",
}

GH_ALLOWED = {
    "issue": {"view", "list", "status"},
    "pr": {"view", "list", "diff", "checks", "status"},
    "search": {"issues", "prs", "repos", "code", "commits"},
    "repo": {"view", "list"},
    "run": {"list", "view", "watch"},
    "workflow": {"list", "view"},
    "release": {"list", "view", "verify", "verify-asset"},
    "label": {"list"},
    "ruleset": {"list", "view", "check"},
    "project": {"list", "view", "field-list", "item-list"},
}


def deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )


def is_nvim_cwd(cwd: str) -> bool:
    try:
        path = Path(cwd).resolve(strict=False)
    except Exception:
        return False

    return path == NVIM_ROOT or NVIM_ROOT in path.parents


def skip_git_globals(tokens: list[str], index: int) -> int:
    position = index
    while position < len(tokens):
        token = tokens[position]
        if token in GIT_GLOBAL_OPTIONS_WITH_VALUE:
            position += 2
            continue
        if token.startswith(("--git-dir=", "--work-tree=", "--namespace=", "--exec-path=")):
            position += 1
            continue
        if token == "--bare" or token.startswith("-"):
            position += 1
            continue
        break
    return position


def skip_gh_globals(tokens: list[str], index: int) -> int:
    position = index
    while position < len(tokens):
        token = tokens[position]
        if token in GH_GLOBAL_OPTIONS_WITH_VALUE:
            position += 2
            continue
        if token.startswith(("--repo=", "--hostname=", "--config=")):
            position += 1
            continue
        if token in {"--help", "-h", "--version"}:
            position += 1
            continue
        break
    return position


def gh_api_method(tokens: list[str]) -> tuple[str | None, bool]:
    method = None
    explicit = False
    position = 0
    while position < len(tokens):
        token = tokens[position]
        if token in {"--method", "-X"} and position + 1 < len(tokens):
            method = tokens[position + 1].upper()
            explicit = True
            position += 2
            continue
        if token.startswith("--method="):
            method = token.split("=", 1)[1].upper()
            explicit = True
        position += 1
    return method, explicit


def gh_api_endpoint(tokens: list[str]) -> str | None:
    position = 0
    while position < len(tokens):
        token = tokens[position]
        if token in {
            "--method",
            "-X",
            "--preview",
            "-p",
            "--hostname",
            "--jq",
            "-q",
            "--template",
            "-t",
            "--input",
        }:
            position += 2
            continue
        if token in {
            "--paginate",
            "--slurp",
            "--silent",
            "-i",
            "--include",
            "--cache",
        }:
            position += 1
            continue
        if token in {"--field", "-F", "--raw-field", "-f"}:
            position += 2
            continue
        if token.startswith("-"):
            position += 1
            continue
        return token
    return None


def gh_graphql_query(tokens: list[str]) -> str | None:
    position = 0
    while position < len(tokens):
        token = tokens[position]
        if token in {"--field", "-F", "--raw-field", "-f"} and position + 1 < len(tokens):
            value = tokens[position + 1]
            if value.startswith("query="):
                return value.split("=", 1)[1]
            position += 2
            continue
        if token.startswith(("--field=", "--raw-field=")):
            value = token.split("=", 1)[1]
            if value.startswith("query="):
                return value.split("=", 1)[1]
        position += 1
    return None


def inspect_git(tokens: list[str], index: int) -> str | None:
    command_index = skip_git_globals(tokens, index + 1)
    if command_index >= len(tokens):
        return None

    command = tokens[command_index]
    if command in GIT_BLOCKED:
        return f"Neovim Codex guard: git {command} is gated. Commit runs only in the future main-thread commit workflow; push is not allowed here."
    return None


def inspect_gh_api(tokens: list[str]) -> str | None:
    endpoint = gh_api_endpoint(tokens)
    if endpoint == "graphql":
        query = gh_graphql_query(tokens)
        if not query:
            return "Neovim Codex guard: gh api graphql must include an inspectable read-only query."
        if "mutation" in query.lower():
            return "Neovim Codex guard: GraphQL mutations are forbidden in active Neovim phases."
        return None

    method, explicit = gh_api_method(tokens)
    if method != "GET" or not explicit:
        return "Neovim Codex guard: gh api REST calls must use explicit --method GET."
    return None


def inspect_gh(tokens: list[str], index: int) -> str | None:
    command_index = skip_gh_globals(tokens, index + 1)
    if command_index >= len(tokens):
        return None

    top = tokens[command_index]
    args = tokens[command_index + 1 :]

    if top in {"help", "version"}:
        return None
    if top == "api":
        return inspect_gh_api(args)
    if top == "auth":
        return "Neovim Codex guard: gh auth commands are forbidden here to avoid token exposure or auth mutation."
    if top in {"alias", "extension", "agent-task", "skill"}:
        return f"Neovim Codex guard: gh {top} is forbidden here because it can hide writes or interact externally."

    allowed_subcommands = GH_ALLOWED.get(top)
    if allowed_subcommands is None:
        return f"Neovim Codex guard: gh {top} is not on the read-only allowlist."
    if not args:
        return f"Neovim Codex guard: gh {top} must name a read-only subcommand."

    subcommand = args[0]
    if subcommand not in allowed_subcommands:
        return f"Neovim Codex guard: gh {top} {subcommand} is not read-only allowed here."
    return None


def inspect_tokens(tokens: list[str]) -> str | None:
    for index, token in enumerate(tokens):
        if token == "git":
            reason = inspect_git(tokens, index)
            if reason:
                return reason
        if token == "gh":
            reason = inspect_gh(tokens, index)
            if reason:
                return reason
        if Path(token).name in {"bash", "sh", "zsh"}:
            reason = inspect_shell_wrapper(tokens, index)
            if reason:
                return reason
    return None


def inspect_shell_wrapper(tokens: list[str], index: int) -> str | None:
    position = index + 1
    while position < len(tokens):
        token = tokens[position]
        if token == "-c" or (token.startswith("-") and "c" in token and not token.startswith("--")):
            if position + 1 >= len(tokens):
                return None
            nested_command = tokens[position + 1]
            try:
                nested_tokens = shlex.split(nested_command)
            except ValueError:
                if "git" in nested_command or "gh" in nested_command:
                    return "Neovim Codex guard: could not safely parse nested git/gh shell command."
                return None
            return inspect_tokens(nested_tokens)
        if token == "--":
            position += 1
            continue
        if not token.startswith("-"):
            return None
        position += 1
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    if payload.get("tool_name") != "Bash":
        return 0
    if not is_nvim_cwd(str(payload.get("cwd", ""))):
        return 0

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0

    command = tool_input.get("command")
    if not isinstance(command, str):
        return 0

    try:
        tokens = shlex.split(command)
    except ValueError:
        if "git" in command or "gh" in command:
            deny("Neovim Codex guard: could not safely parse a git/gh shell command.")
        return 0

    reason = inspect_tokens(tokens)
    if reason:
        deny(reason)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
