---
name: delta
description: "Use when Barrett asks Codex or subagents to inspect or operate the Delta productivity platform through the delta CLI, including tasks, categories, feeds, exports, config, auth status, and integration status. Use for CLI/product operation, not for changing the Delta codebase."
---

# Delta

Use `$delta` to inspect or operate Delta through the installed `delta` CLI.

This skill is for product/operator work only. It is not for changing the Delta
codebase, opening PRs, deployments, releases, or repo maintenance.

## Operating Loop

1. State the product scope you are checking, such as pending tasks, blocked
   work, categories, auth, integrations, feed, or export.
2. Choose the fewest CLI commands that can answer the request. Prefer `--json`
   for tasks, categories, dependencies, and integrations.
3. Treat the CLI and server response as the source of truth for live Delta
   state. Do not search Codex memory for current tasks, auth state,
   integrations, feeds, exports, or categories.
4. Check `delta auth status` only when auth may affect the request, the user
   asks about auth, or another command reports an auth problem.
5. Summarize results concisely. State exactly what scope and filters were
   queried. Do not dump raw JSON, iCal, feed URLs, or tokens unless the user
   explicitly asks and the safety policy allows it.

Stop once the answer is supported. Avoid redundant help, source, memory, and
retry loops.

## Command Planning

- Current pending work: `delta task list --json`.
- Other task states: add explicit filters such as `status:wip`,
  `status:blocked`, or `status:done`. Do not infer those states from the
  default pending-only list.
- Categories: `delta cat --json`.
- Dependencies: `delta task dep list <id> --json`.
- Config, integrations, and auth: use `delta config`, `delta config get <key>`,
  `delta integration list --json`, and `delta auth status` as needed.
- Feed or export data can contain private calendar details. Summarize by
  default.

Use `delta --help` or `delta help <topic>` when planning a command shape is
actually uncertain. Do not read help as a ritual before ordinary known reads.

## Safety Policy

Allowed without asking: read-only CLI metadata, help, completion output, task
lists, dependency lists, categories, config reads, integration list, and auth
status.

Allowed when directly relevant to the user's request: `delta feed`,
`delta export ...`, and `delta export --id <id>`. Treat feed URLs and iCal as
private.

Allowed from clear user intent: simple `delta task add ...` using only details
the user supplied, and `delta auth login` for auth setup. Never ask Barrett to
paste a token into chat, and never echo a token.

Ask Barrett before every other mutation, including task edits, status changes,
dependency changes, deletes, imports, feed changes, config writes, auth logout,
and token regeneration.

Ask Barrett before sensitive read-adjacent commands: `delta auth token`,
`delta auth token --unmask`, any `delta --debug ...`, and
`delta integration test ...`.

If a command is not clearly covered here, read `references/cli-safety.md` once.
When still unsure, ask first.

## Product Interpretation

- Treat `pending`, `wip`, `blocked`, and `done` as task states.
- Treat categories as task grouping labels.
- Treat dependencies as ordering/blocking relationships between tasks.
- For task summaries, call out blocked work, due work, and stale WIP when that
  is visible from CLI output.

## Failure Handling

- If the CLI is not installed, report `delta` missing from `PATH`.
- If auth is missing, explain how to fix it. Tell Barrett to open
  `https://delta.barrettruth.com/settings`, go to account -> API access, copy
  or regenerate the Delta API key, then run:

  ```sh
  read -rs token
  printf '%s\n' "$token" | delta auth login --token
  unset token
  delta auth status
  ```

  Make clear that this is a Delta API key, not an npm token. Do not ask Barrett
  to paste the token into chat.
- If the server is unreachable, report the command and the error message.
- If one command fails because a subcommand, flag, argument shape, or filter
  syntax is wrong, document the failed command and error, then verify syntax
  once with CLI help or the local command definition. Run one corrected command
  only if the fix is clear.
- If help or source disagrees with this skill, or the correction is still
  unclear, report the mismatch and stop instead of trying permutations.
- Do not retry commands with `--debug` unless Barrett explicitly approves it.
