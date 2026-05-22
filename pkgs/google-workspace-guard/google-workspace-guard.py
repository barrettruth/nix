#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Any


OPTIONS_WITH_VALUE = {
    "--api-version",
    "--format",
    "--json",
    "--output",
    "-o",
    "--page-delay",
    "--page-limit",
    "--params",
    "--sanitize",
    "--upload",
    "--upload-content-type",
}

HELP_FLAGS = {"-h", "--help", "help"}
VERSION_FLAGS = {"--version", "version"}

ALLOWED_SERVICES = {"drive", "gmail", "docs", "sheets", "slides"}

DRIVE_ALLOWED = {
    "about": {"get"},
    "accessproposals": {"get", "list"},
    "approvals": {"get", "list"},
    "apps": {"get", "list"},
    "changes": {"get", "getStartPageToken", "list"},
    "comments": {"get", "list"},
    "drives": {"get", "list"},
    "files": {"create", "download", "export", "generateIds", "get", "list"},
    "operations": {"get"},
    "permissions": {"get", "list"},
    "replies": {"get", "list"},
    "revisions": {"get", "list"},
    "teamdrives": {"get", "list"},
}

GMAIL_READ_HELPERS = {"+read", "+triage"}
GMAIL_BLOCKED_HELPERS = {"+send", "+reply", "+reply-all", "+forward", "+watch"}
GMAIL_READ_METHODS = {"get", "getProfile", "list"}


@dataclass(frozen=True)
class Decision:
    allowed: bool
    reason: str


def allow(reason: str) -> Decision:
    return Decision(True, reason)


def deny(reason: str) -> Decision:
    return Decision(False, reason)


def option_values(args: list[str], option: str) -> list[str]:
    values: list[str] = []
    index = 0
    prefix = f"{option}="
    while index < len(args):
        arg = args[index]
        if arg == option and index + 1 < len(args):
            values.append(args[index + 1])
            index += 2
            continue
        if arg.startswith(prefix):
            values.append(arg.split("=", 1)[1])
        index += 1
    return values


def positionals(args: list[str]) -> list[str]:
    result: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--":
            result.extend(args[index + 1 :])
            break
        if arg in OPTIONS_WITH_VALUE:
            index += 2
            continue
        if any(arg.startswith(f"{option}=") for option in OPTIONS_WITH_VALUE):
            index += 1
            continue
        if arg.startswith("-"):
            index += 1
            continue
        result.append(arg)
        index += 1
    return result


def parse_json_values(args: list[str], option: str) -> list[Any]:
    parsed = []
    for raw in option_values(args, option):
        try:
            parsed.append(json.loads(raw))
        except json.JSONDecodeError as err:
            raise ValueError(f"{option} must be valid JSON: {err}") from err
    return parsed


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for key, child in value.items():
            yield key
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def has_truthy_key(value: Any, name: str) -> bool:
    if isinstance(value, dict):
        for key, child in value.items():
            if key == name and bool(child):
                return True
            if has_truthy_key(child, name):
                return True
    if isinstance(value, list):
        return any(has_truthy_key(child, name) for child in value)
    return False


def payload_is_safe(args: list[str]) -> Decision:
    try:
        bodies = parse_json_values(args, "--json")
        params = parse_json_values(args, "--params")
    except ValueError as err:
        return deny(str(err))

    for body in bodies:
        if has_truthy_key(body, "trashed"):
            return deny("google guard: refusing to create or mutate a trashed Drive item.")
        for item in walk(body):
            if isinstance(item, str) and item.lower() in {
                "anyone",
                "domain",
                "writer",
                "organizer",
                "fileorganizer",
            }:
                return deny("google guard: refusing payload that looks like sharing or permission mutation.")

    for params_value in params:
        for item in walk(params_value):
            if isinstance(item, str) and "trashed=true" in item.replace(" ", "").lower():
                return deny("google guard: refusing trash searches; this wrapper does not support trash workflows.")

    return allow("payload accepted")


def upload_is_allowed(args: list[str], service: str, parts: list[str]) -> Decision:
    if not option_values(args, "--upload"):
        return allow("no media upload requested")
    if service == "drive" and parts[:2] == ["files", "create"]:
        return allow("Drive files.create upload is creation-only")
    return deny("google guard: --upload is only allowed for drive files create.")


def decide_drive(args: list[str], parts: list[str]) -> Decision:
    if not parts or parts[0] in HELP_FLAGS:
        return allow("Drive help")
    if parts[0] == "+upload":
        return payload_is_safe(args)
    if len(parts) < 2:
        return allow("Drive resource help")

    resource, method = parts[0], parts[1]
    if method not in DRIVE_ALLOWED.get(resource, set()):
        return deny(f"google guard: drive {resource} {method} is not in the read/create allowlist.")
    if resource == "files" and method == "create":
        payload = payload_is_safe(args)
        if not payload.allowed:
            return payload
    return upload_is_allowed(args, "drive", parts)


def decide_gmail(parts: list[str]) -> Decision:
    if not parts or parts[0] in HELP_FLAGS:
        return allow("Gmail help")
    if parts[0] in GMAIL_READ_HELPERS:
        return allow("Gmail read helper")
    if parts[0] in GMAIL_BLOCKED_HELPERS:
        return deny(f"google guard: gmail {parts[0]} is blocked; Gmail is read-only here.")
    if parts[0] != "users":
        return deny("google guard: only Gmail users read resources are allowed.")
    method = parts[-1]
    if method in GMAIL_READ_METHODS:
        return allow("Gmail read method")
    return deny(f"google guard: gmail method {method} is blocked; Gmail is read-only here.")


def decide_docs(parts: list[str]) -> Decision:
    if not parts or parts[0] in HELP_FLAGS:
        return allow("Docs help")
    if parts[0] == "+write":
        return deny("google guard: docs +write edits an existing document and is blocked.")
    if parts[:2] in (["documents", "get"], ["documents", "create"]):
        return allow("Docs read/create method")
    return deny("google guard: Docs allows only documents get/create.")


def decide_sheets(parts: list[str]) -> Decision:
    if not parts or parts[0] in HELP_FLAGS:
        return allow("Sheets help")
    if parts[:2] == ["spreadsheets", "create"]:
        return allow("Sheets create method")
    if parts and parts[-1] in {"get", "getByDataFilter", "batchGet", "batchGetByDataFilter"}:
        return allow("Sheets read method")
    return deny("google guard: Sheets allows only create plus read methods.")


def decide_slides(parts: list[str]) -> Decision:
    if not parts or parts[0] in HELP_FLAGS:
        return allow("Slides help")
    if parts[:2] in (["presentations", "create"], ["presentations", "get"]):
        return allow("Slides read/create method")
    return deny("google guard: Slides allows only presentations get/create.")


def decide(args: list[str]) -> Decision:
    if not args or any(arg in HELP_FLAGS | VERSION_FLAGS for arg in args):
        return allow("top-level help/version")

    parts = positionals(args)
    if not parts:
        return allow("top-level help")

    top = parts[0]
    if top == "schema":
        return allow("schema introspection")
    if top == "auth":
        if len(parts) >= 2 and parts[1] == "status":
            return allow("auth status")
        return deny("google guard: auth setup/login/logout/export are not agent actions.")
    if top == "generate-skills":
        return deny("google guard: generate-skills writes local skill files and is blocked.")
    if top not in ALLOWED_SERVICES:
        return deny(f"google guard: service {top} is not enabled in this wrapper.")

    service_parts = parts[1:]
    payload = payload_is_safe(args)
    if not payload.allowed:
        return payload

    if top == "drive":
        return decide_drive(args, service_parts)
    if top == "gmail":
        return decide_gmail(service_parts)
    if top == "docs":
        return decide_docs(service_parts)
    if top == "sheets":
        return decide_sheets(service_parts)
    if top == "slides":
        return decide_slides(service_parts)
    return deny(f"google guard: service {top} has no policy.")


def run_self_tests() -> int:
    allowed = [
        ["drive", "files", "list", "--params", '{"pageSize": 5, "q": "trashed=false"}'],
        ["drive", "files", "create", "--json", '{"name": "draft", "mimeType": "application/vnd.google-apps.document"}'],
        ["drive", "files", "create", "--upload", "draft.md", "--json", '{"name": "draft"}'],
        ["gmail", "+read", "--id", "abc"],
        ["gmail", "users", "messages", "get", "--params", '{"userId": "me", "id": "abc"}'],
        ["docs", "documents", "create", "--json", '{"title": "Draft"}'],
        ["schema", "drive.files.delete"],
        ["auth", "status"],
    ]
    denied = [
        ["drive", "files", "delete", "--params", '{"fileId": "abc"}'],
        ["drive", "files", "update", "--json", '{"trashed": true}'],
        ["drive", "permissions", "create", "--json", '{"role": "reader", "type": "anyone"}'],
        ["gmail", "+send", "--to", "x@example.com", "--body", "hi"],
        ["gmail", "users", "messages", "send", "--json", "{}"],
        ["docs", "+write", "--document", "abc", "--text", "hi"],
        ["calendar", "events", "insert", "--json", "{}"],
        ["auth", "export", "--unmasked"],
    ]
    for command in allowed:
        decision = decide(command)
        assert decision.allowed, (command, decision.reason)
    for command in denied:
        decision = decide(command)
        assert not decision.allowed, command
    print("google-workspace-guard self-test passed")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if "--self-test" in args:
        return run_self_tests()

    dry_run_wrapper = "--dry-run-wrapper" in args
    args = [arg for arg in args if arg != "--dry-run-wrapper"]

    decision = decide(args)
    if dry_run_wrapper:
        print(
            json.dumps(
                {
                    "allowed": decision.allowed,
                    "argv": args,
                    "reason": decision.reason,
                },
                sort_keys=True,
            )
        )
        return 0 if decision.allowed else 64

    if not decision.allowed:
        print(decision.reason, file=sys.stderr)
        return 64

    gws_bin = os.environ.get("GWS_BIN", "gws")
    return subprocess.call([gws_bin, *args])


if __name__ == "__main__":
    raise SystemExit(main())
