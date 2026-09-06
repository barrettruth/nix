---
name: cp
description: Complete a natural-language request and copy its text result to the system clipboard. Use for `/cp`, `$cp`, or an explicit request to copy an agent-produced result to the clipboard.
---

# cp

Complete the request normally, including any investigation or tool use it needs.
The request still has the same authorization and safety boundaries as it would
without this skill.

Determine the exact text that is the requested deliverable, then pass only that
text on standard input to:

```sh
~/.agents/skills/cp/scripts/copy.sh
```

Do not copy the user's query, reasoning, progress updates, or conversational
framing unless the request asks for them. Run the helper on the local machine
after producing the result, even when gathering that result involves a remote
host. The helper accepts text on standard input; do not pass the text as command
arguments.

On success, reply only with a brief confirmation. On failure, report the
helper's error and do not claim that anything was copied.
