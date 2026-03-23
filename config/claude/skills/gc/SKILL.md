# /gc

Create a conventional commit from staged or unstaged changes.

## Instructions

1. Run exactly this one Bash command:

   ```
   echo "---BRANCH---" && git branch --show-current && echo "---STATUS---" && git status --short && echo "---DIFF---" && git diff --cached && echo "---LOG---" && git log --oneline -5
   ```

2. **If on `main` or `master`**: create a feature branch before anything else.
   Infer the branch name from the staged diff or status (e.g. `fix/off-by-one`,
   `feat/add-filter`). Run:

   ```
   git checkout -b type/short-description
   ```

   Use the standard type prefixes: feat/, fix/, refactor/, docs/, test/, perf/,
   ci/, build/.

3. If the diff section is empty (nothing staged), ask the user which files to
   stage from the status list. Then run exactly one Bash command:

   ```
   git add <files> && git diff --cached
   ```

   Do NOT re-run status or log — you already have them.

4. Draft the commit message. Rules:
   - Header: `type(scope): imperative summary` — max 72 chars, lowercase after
     colon, no trailing period.
   - Valid types: `feat` `fix` `docs` `refactor` `perf` `test` `ci` `build` `revert`
   - Scope is optional, lowercase.
   - Non-trivial changes require a body with `Problem:` / `Solution:` sections,
     wrapped at 72 chars, separated from header by a blank line.
   - Keep the body tight: 2-3 sentences per section, max.
   - Trivial one-liners: header alone is fine.
   - Use backticks around code identifiers, function names, and file paths
     (e.g. `setup()`, `lua/pending/store.lua`).
   - Match the style of the recent commits from step 1.

5. Present the full message and ask for approval.

6. After approval, run exactly one Bash command:
   ```
   git commit -m "$(cat <<'EOF'
   <message here>
   EOF
   )"
   ```

Total: 2-4 Bash calls (gather, maybe branch, maybe stage, commit). Do not run
any other commands. Do not read files, explore code, or run additional git
commands beyond what is listed above.

Never amend. Never sign as co-author. Never push.
