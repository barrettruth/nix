# /commit

Create a conventional commit from staged or unstaged changes.

## Instructions

1. Run exactly this one Bash command:
   ```
   git status --short && echo "---DIFF---" && git diff --cached && echo "---LOG---" && git log --oneline -5
   ```

2. If the diff section is empty (nothing staged), ask the user which files to
   stage from the status list. Then run exactly one Bash command:
   ```
   git add <files> && git diff --cached
   ```
   Do NOT re-run status or log — you already have them.

3. Draft the commit message. Rules:
   - Header: `type(scope): imperative summary` — max 72 chars, lowercase after
     colon, no trailing period.
   - Valid types: `feat` `fix` `docs` `refactor` `perf` `test` `ci` `build` `revert`
   - Scope is optional, lowercase.
   - Non-trivial changes require a body with `Problem:` / `Solution:` sections,
     wrapped at 72 chars, separated from header by a blank line.
   - Trivial one-liners: header alone is fine.
   - Match the style of the recent commits from step 1.

4. Present the full message and ask for approval.

5. After approval, run exactly one Bash command:
   ```
   git commit -m "$(cat <<'EOF'
   <message here>
   EOF
   )"
   ```

Total: 2 Bash calls (gather + commit), or 3 if staging was needed. Do not run
any other commands. Do not read files, explore code, or run additional git
commands beyond what is listed above.

Never amend. Never sign as co-author. Never push.
