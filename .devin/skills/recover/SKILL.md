---
name: recover
description: Recover an exact local Codex or Devin CLI session that cannot resume because it is still in use by an abandoned process.
allowed-tools:
  - exec
permissions:
  allow:
    - Exec(codex resume)
    - Exec(devin list)
    - Exec(recover)
triggers:
  - user
  - model
---

# recover

Recover one exact local Codex or Devin CLI session without disturbing other CLI processes.

## Flow

1. Resolve the target to one exact session ID. Use an ID supplied directly. Codex IDs are UUIDs. If only a Devin title or description is supplied, run `devin list --format json` and continue only when it identifies one unique session; otherwise ask which session is meant.
2. Inspect the exact session lock:

```sh
recover status <session-id> --json
```

3. If asked to inspect only, report the status without releasing it. If asked to recover, kill, unlock, or resume that exact session, run:

```sh
recover release <session-id> --json
```

4. If release succeeds, respond with the returned slash command so you can switch the current CLI to the recovered session:

```text
/resume <session-id>
```

A skill cannot replace the interactive Codex or Devin process that is currently executing it. Do not run a CLI's resume command through `exec`; that creates a hidden nested CLI and makes the session busy again. From a normal shell, `recover resume <session-id>` safely releases and then replaces the shell process with the matching CLI.

## Rules

- Operate only on the lock for the exact requested session.
- Trust the helper's exact lock-holder validation; never infer ownership from a broad process-name search.
- Never use `pkill`, `killall`, `fuser -k`, `/rm-session`, or direct PID signals.
- Never delete lock files or edit the sessions database.
- Never release the session executing this skill. The helper detects and refuses that case.
- The helper sends `TERM`, waits for the lock to release, and uses `KILL` only when the same validated process still owns the same lock.
- If the lock is already available, do not kill anything; return the resume command.
- Report validation failures as-is instead of trying another process.
