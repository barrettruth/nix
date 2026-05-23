# Delta CLI Safety

Use this when a `delta` command is sensitive, mutating, or not clearly covered
by `SKILL.md`. The goal is fast operator judgment: use the CLI as source of
truth, choose minimal commands, and ask before risky actions.

Prefer `--json` for structured reads when the command supports it. Do not use
Codex memory for live Delta state. Do not use `--debug` unless Barrett
explicitly approves it.

## Allowed Reads

These are allowed without asking:

| Command | Notes |
| --- | --- |
| `delta --version` | Local CLI version. |
| `delta --help` | Local command help. |
| `delta help <topic>` | Local help topic. |
| `delta completion bash|zsh|fish` | Local shell completion text. |
| `delta task list --json` | Read pending tasks by default. Add explicit filters for other states. |
| `delta task dep list <id> --json` | Read dependencies for one task. |
| `delta cat --json` | Read categories and counts. |
| `delta config` | Read local Delta config. |
| `delta config get <key>` | Read one local config key. |
| `delta integration list --json` | Read configured integrations. |
| `delta auth status` | Read auth state. Does not print the token. |

## Contextual Reads

These are allowed when the user asks for the relevant data. Summarize output
unless the user asks for raw data:

| Command | Notes |
| --- | --- |
| `delta feed` | Prints a calendar feed URL. Treat it as private. |
| `delta export ...` | Prints iCal data. Treat it as private calendar data. |
| `delta export --id <id>` | Prints iCal data for one item. Treat it as private. |

## Allowed From Clear Intent

These are allowed only when the user clearly asks for the action:

| Command | Notes |
| --- | --- |
| `delta task add ...` | Simple task creation. Use only details the user supplied. |
| `delta auth login` | Auth setup. Never echo, log, invent, or reveal the token. |

Simple task creation means adding a task from user-supplied details. Do not
infer recurrence, dependencies, non-default status, or bulk creation unless the
user clearly asks for them.

For auth setup, guide Barrett to copy or regenerate the Delta API key from
`https://delta.barrettruth.com/settings` -> account -> API access. Prefer:

```sh
read -rs token
printf '%s\n' "$token" | delta auth login --token
unset token
delta auth status
```

Do not ask Barrett to paste a token into chat. This is a Delta API key, not an
npm token.

## Approval Required

Ask Barrett before these commands:

| Command | Why |
| --- | --- |
| `delta task edit ...` | Changes an existing task. |
| `delta task done ...` | Changes task status. |
| `delta task delete ...` | Deletes task state. |
| `delta task wip|block|pending ...` | Changes task status. |
| `delta task dep add|rm ...` | Changes dependency state. |
| `delta import ...` | Imports external events into Delta. |
| `delta feed generate` | Creates or replaces a durable feed token. |
| `delta feed revoke` | Revokes a feed token. |
| `delta config set ...` | Writes local config. |
| `delta auth logout` | Removes local auth. |
| `delta auth token` | Prints a token. |
| `delta auth token --unmask` | Prints the full token. |
| `delta auth token regenerate` | Invalidates the old server token. |
| `delta integration test ...` | May transmit API keys or provider settings. |
| any `delta --debug ...` | Can print request bodies, responses, and sensitive data. |

If a command combines a safe command with `--debug`, treat it as ask-first.

## Operating Rules

- State the query scope actually checked. Do not infer that WIP, blocked, done,
  or cancelled tasks are absent from the default pending-only
  `delta task list`.
- Never include tokens in final output.
- Avoid raw iCal or feed URLs unless the user asks for them.
- For task lists, summarize counts, blocked work, due work, and notable WIP.
- After one CLI syntax failure, verify help or the local command definition
  once. If the correction is not clear, report the mismatch and stop.
- Avoid redundant help, source, memory, and command-permutation loops.
