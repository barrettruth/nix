# /qpr

Create a pull request immediately, no approval step.

## Instructions

1. Run exactly this one Bash command:

   ```
   echo "---BRANCH---" && git branch --show-current && echo "---LOG---" && git log --oneline main..HEAD && echo "---STAT---" && git diff main...HEAD --stat && echo "---TEMPLATE---" && cat .github/pull_request_template.md 2>/dev/null || true
   ```

   If the branch is `main` or `master`, tell the user and stop.

2. If `scripts/ci.sh` exists, run it:

   ```
   bash scripts/ci.sh
   ```

   If it fails, show the output and stop.

3. Draft the PR (do NOT present for approval — create it immediately):
   - **Title**: `type(scope): imperative summary`, max 72 chars.
   - **Body**: if a PR template was found, fill it in. Otherwise:

     ```
     ## Problem

     <1-2 sentences>

     ## Solution

     <1-2 sentences>
     ```

   - Use backticks around code identifiers, function names, and file paths.

   Run exactly one Bash command:

   ```
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body here>
   EOF
   )"
   ```

   Print the PR URL from the output.

Total: 2-3 Bash calls. Do not run any other commands.

Never force-push. Never target main/master as the head branch.
