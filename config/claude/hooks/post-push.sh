#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

if ! printf '%s' "$CMD" | grep -qE '\bgit\s+push\b|gh\s+pr\s+create\b'; then
  exit 0
fi

if printf '%s' "$CMD" | grep -qE 'gh\s+pr\s+create'; then
  echo "--- POST-PR CHECKS ---" >&2

  git fetch origin main --quiet 2>/dev/null || git fetch origin master --quiet 2>/dev/null || true
  BASE=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null || true)
  if [ -n "$BASE" ]; then
    CONFLICTS=$(git merge-tree "$BASE" HEAD origin/main 2>/dev/null || git merge-tree "$BASE" HEAD origin/master 2>/dev/null || true)
    if printf '%s' "$CONFLICTS" | grep -q "changed in both"; then
      echo "WARNING: Merge conflicts detected with main. Rebase needed." >&2
      printf '%s' "$CONFLICTS" | head -10 >&2
    else
      echo "No merge conflicts with main." >&2
    fi
  fi

  ISSUES=$(gh issue list --state open --limit 10 2>/dev/null || true)
  if [ -n "$ISSUES" ]; then
    echo "Open issues (check if any should be linked/closed by this PR):" >&2
    echo "$ISSUES" >&2
  fi
fi

if printf '%s' "$CMD" | grep -qE '\bgit\s+push\b' && ! printf '%s' "$CMD" | grep -qE 'gh\s+pr\s+create'; then
  git fetch origin main --quiet 2>/dev/null || git fetch origin master --quiet 2>/dev/null || true
  BASE=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null || true)
  if [ -n "$BASE" ]; then
    CONFLICTS=$(git merge-tree "$BASE" HEAD origin/main 2>/dev/null || git merge-tree "$BASE" HEAD origin/master 2>/dev/null || true)
    if printf '%s' "$CONFLICTS" | grep -q "changed in both"; then
      echo "WARNING: Branch has conflicts with main. Rebase before creating PR." >&2
    fi
  fi
fi

exit 0
