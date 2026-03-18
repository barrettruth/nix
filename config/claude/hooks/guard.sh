#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

if printf '%s' "$CMD" | grep -qiE 'co-authored-by|signed-off-by'; then
  echo "Blocked: never add Co-Authored-By or Signed-off-by trailers. See CLAUDE.md line 11." >&2
  exit 2
fi

if printf '%s' "$CMD" | grep -qE '\bgit\s+push\b'; then
  BRANCH=$(git branch --show-current 2>/dev/null || true)
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo "Blocked: never push directly to $BRANCH. Use a feature branch." >&2
    exit 2
  fi
  if printf '%s' "$CMD" | grep -qE '\bgit\s+push\b.*\b(main|master)\b'; then
    echo "Blocked: never push to main/master by name. Use a feature branch." >&2
    exit 2
  fi
fi

exit 0
