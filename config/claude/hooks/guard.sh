#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

if printf '%s' "$CMD" | grep -qE '\bgh\b.*\s(-R|--repo)\b'; then
  echo "Blocked: do not target other repos with -R/--repo. Run gh commands against the current repo only." >&2
  exit 2
fi

if printf '%s' "$CMD" | grep -qE '\bgh\s+issue\s+create\b'; then
  echo "Blocked: gh issue create must be run manually or explicitly approved." >&2
  exit 2
fi

if printf '%s' "$CMD" | grep -qE '\bgit\s+push\b'; then
  BRANCH=$(git branch --show-current 2>/dev/null || true)
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo "Blocked: never push directly to $BRANCH. Use a feature branch." >&2
    exit 2
  fi
fi

exit 0
