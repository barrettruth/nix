# /pr

Create a pull request from the current branch.

## Instructions

1. Run exactly this one Bash command:

   ```
   echo "---BRANCH---" && git branch --show-current && echo "---LOG---" && git log --oneline main..HEAD && echo "---STAT---" && git diff main...HEAD --stat && echo "---TEMPLATE---" && cat .github/pull_request_template.md 2>/dev/null || true
   ```

   If the branch is `main` or `master`, tell the user and stop.

2. Draft the PR using the commit log and diffstat (do NOT run `git diff` for the
   full diff — you already have conversation context from the work you did):
   - **Title**: `type(scope): imperative summary`, max 72 chars. For
     single-commit PRs, reuse the commit header. For multi-commit, summarize.
   - **Body**: if a PR template was found in step 1, fill it in. Otherwise:

     ```
     ## Problem

     <1-2 sentences>

     ## Solution

     <1-2 sentences>
     ```

   - Write concise prose. No bullet walls, no verbose explanations.
   - Use backticks around code identifiers, function names, and file paths.

3. Present the title and body. Ask for approval.

4. After approval, if `scripts/ci.sh` exists, run it:
   ```
   bash scripts/ci.sh
   ```
   If it fails, show the output and stop. Do NOT create the PR.

5. Run exactly one Bash command:
   ```
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body here>
   EOF
   )"
   ```
   Print the PR URL from the output.

Total: 2 Bash calls (gather + create), or 3 if CI ran. Do not run any other
commands. Do not read files, explore code, or run additional git commands beyond
what is listed above.

Never force-push, even with lease. Never target main/master as the head branch.
