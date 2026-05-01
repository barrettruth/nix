#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

if printf '%s' "$CMD" | grep -qiE 'co-authored-by|signed-off-by'; then
  echo "Blocked: never add Co-Authored-By or Signed-off-by trailers." >&2
  exit 2
fi

GIT_DIR=$(printf '%s' "$CMD" | grep -oP '(?<=cd\s)[^\s;&|]+' | tail -1)
if [ -n "$GIT_DIR" ]; then
  GIT_ROOT=$(git -C "$GIT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  BRANCH=$(git -C "$GIT_DIR" branch --show-current 2>/dev/null || true)
else
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  BRANCH=$(git branch --show-current 2>/dev/null || true)
fi

if printf '%s' "$CMD" | grep -qE '\bgit\s+commit\b'; then
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo "Blocked: cannot commit on $BRANCH. Create a feature branch first:" >&2
    echo "  git checkout -b type/short-description" >&2
    echo "Branch naming: feat/, fix/, refactor/, docs/, test/, perf/, ci/, build/" >&2
    exit 2
  fi
fi

if printf '%s' "$CMD" | grep -qE '\bgit\s+push\b'; then
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo "Blocked: never push directly to $BRANCH." >&2
    exit 2
  fi
  if printf '%s' "$CMD" | grep -qE '\bgit\s+push\b.*\b(main|master)\b'; then
    echo "Blocked: never push to main/master by name." >&2
    exit 2
  fi
  if [ -n "$GIT_ROOT" ] && [ -f "$GIT_ROOT/scripts/ci.sh" ]; then
    CI_OUTPUT=$(cd "$GIT_ROOT" && bash scripts/ci.sh 2>&1) || {
      echo "Blocked: scripts/ci.sh failed. Fix before pushing:" >&2
      echo "$CI_OUTPUT" >&2
      exit 2
    }
  fi
fi

exit 0
