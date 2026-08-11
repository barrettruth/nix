#!/usr/bin/env python3
import json
import shlex
import sys
from pathlib import Path
from typing import cast


PACKAGE_MANAGERS = {"npm", "npx", "pnpm", "pnpx", "yarn", "bun"}


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


def raw_gws_reference(token: str) -> bool:
    lowered = token.lower()
    return (
        "googleworkspace/cli" in lowered
        or "googleworkspace-cli" in lowered
        or "@googleworkspace/cli" in lowered
    )


def inspect_nix(tokens: list[str], index: int) -> str | None:
    tail = tokens[index + 1 :]
    if not tail:
        return None
    if tail[0] in {"run", "shell", "develop", "build"} and any(
        raw_gws_reference(token) for token in tail[1:]
    ):
        return "Google Workspace guard: use the Nix-managed `google` wrapper, not raw `nix run/shell github:googleworkspace/cli`."
    return None


def inspect_package_manager(tokens: list[str], index: int) -> str | None:
    if any(raw_gws_reference(token) for token in tokens[index + 1 :]):
        return "Google Workspace guard: use the Nix-managed `google` wrapper, not raw npm/npx package execution."
    return None


def inspect_shell_wrapper(tokens: list[str], index: int) -> str | None:
    position = index + 1
    while position < len(tokens):
        token = tokens[position]
        if token == "-c" or (
            token.startswith("-") and "c" in token and not token.startswith("--")
        ):
            if position + 1 >= len(tokens):
                return None
            nested_command = tokens[position + 1]
            try:
                nested_tokens = shlex.split(nested_command)
            except ValueError:
                if "gws" in nested_command or "googleworkspace" in nested_command:
                    return "Google Workspace guard: could not safely parse nested raw gws shell command."
                return None
            return inspect_tokens(nested_tokens)
        if token == "--":
            position += 1
            continue
        if not token.startswith("-"):
            return None
        position += 1
    return None


def is_gws_lookup(tokens: list[str]) -> bool:
    for index, token in enumerate(tokens):
        name = Path(token).name
        if name in {"which", "type"}:
            targets = tokens[index + 1 :]
            return bool(targets) and all(
                target.startswith("-") or Path(target).name in {"gws", "google"}
                for target in targets
            )

        if name == "command":
            tail = tokens[index + 1 :]
            lookup_seen = False
            targets: list[str] = []
            for item in tail:
                if item in {"-v", "-V"}:
                    lookup_seen = True
                    continue
                if item.startswith("-"):
                    continue
                targets.append(item)
            return lookup_seen and bool(targets) and all(
                Path(target).name in {"gws", "google"} for target in targets
            )

    return False


def inspect_tokens(tokens: list[str]) -> str | None:
    if is_gws_lookup(tokens):
        return None

    for index, token in enumerate(tokens):
        name = Path(token).name
        if name == "google":
            continue
        if name == "gws":
            return "Google Workspace guard: use `google ...`; direct `gws ...` bypasses the creation-only policy."
        if name == "nix":
            reason = inspect_nix(tokens, index)
            if reason:
                return reason
        if name in PACKAGE_MANAGERS:
            reason = inspect_package_manager(tokens, index)
            if reason:
                return reason
        if name in {"bash", "sh", "zsh"}:
            reason = inspect_shell_wrapper(tokens, index)
            if reason:
                return reason
    return None


def as_object_dict(value: object) -> dict[str, object] | None:
    if not isinstance(value, dict):
        return None
    return cast(dict[str, object], value)


def inspect_command(command: str) -> str | None:
    try:
        tokens = shlex.split(command)
    except ValueError:
        if "gws" in command or "googleworkspace" in command:
            return "Google Workspace guard: could not safely parse raw gws command."
        return None
    return inspect_tokens(tokens)


def run_self_tests() -> int:
    denied = [
        "gws drive files list",
        "/nix/store/abc-gws-0.22.5/bin/gws gmail +send --to x",
        "nix run github:googleworkspace/cli -- drive files list",
        "nix shell github:googleworkspace/cli/a3768 --command gws drive files list",
        "npx @googleworkspace/cli drive files list",
        "bash -lc 'gws drive files list'",
        "which gws && gws drive files list",
    ]
    allowed = [
        "google drive files list",
        "direnv exec ~/dev/death google drive files list",
        "python3 scripts/google-workspace-guard.py --dry-run-wrapper drive files list",
        "which gws",
        "command -v gws",
        "type gws",
        "direnv exec ~/dev/death which gws",
        "bash -lc 'command -v gws'",
    ]
    for command in denied:
        assert inspect_command(command), command
    for command in allowed:
        assert inspect_command(command) is None, command
    print("google-workspace-pre-tool-use self-test passed")
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return run_self_tests()

    try:
        raw_payload = cast(object, json.load(sys.stdin))
    except Exception:
        return 0
    payload = as_object_dict(raw_payload)
    if payload is None or payload.get("tool_name") != "Bash":
        return 0

    tool_input = as_object_dict(payload.get("tool_input"))
    if tool_input is None:
        return 0
    command = tool_input.get("command")
    if not isinstance(command, str):
        return 0

    reason = inspect_command(command)
    if reason:
        deny(reason)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
