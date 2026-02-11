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

     <why this change is needed>

     ## Solution

     <what the change does>
     ```
   - Write in plain prose. No bullet walls, no AI markdown soup.

3. Present the title and body. Ask for approval.

4. After approval, run exactly one Bash command (push + create chained):
   ```
   git push -u origin <branch> && gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body here>
   EOF
   )"
   ```
   Print the PR URL from the output.

Total: 2 Bash calls (gather + push/create). Do not run any other commands. Do
not read files, explore code, or run additional git commands beyond what is
listed above.

Never force-push, even with lease. Never target main/master as the head branch.
