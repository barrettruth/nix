# /qpr

Create a pull request immediately, no approval step.

## Instructions

1. Run exactly this one Bash command:

   ```
   echo "---BRANCH---" && git branch --show-current && echo "---LOG---" && git log --oneline main..HEAD 2>/dev/null && echo "---STAT---" && git diff main...HEAD --stat 2>/dev/null && echo "---TEMPLATE---" && cat .github/pull_request_template.md 2>/dev/null || true
   ```

   **If on `main` or `master`, stop immediately.** Tell the user: "You're on
   main. Use /gc to commit first (it will auto-create a branch), then run /qpr."

   **If there are no commits ahead of main**, stop. Nothing to PR.

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

   Push and create in one step:

   ```
   git push -u origin HEAD && gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body here>
   EOF
   )"
   ```

   Print the PR URL from the output.

4. **Post-PR conflict check.** Run exactly one Bash command:

   ```
   git fetch origin main && git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main 2>/dev/null | head -20
   ```

   If conflicts exist, warn the user and offer to rebase.

Total: 2-4 Bash calls. Do not run any other commands.

Never force-push. Never target main/master as the head branch.
