# /pr

Create a pull request from the current branch.

## Instructions

1. Run exactly this one Bash command:

   ```
   echo "---BRANCH---" && git branch --show-current && echo "---LOG---" && git log --oneline main..HEAD 2>/dev/null && echo "---STAT---" && git diff main...HEAD --stat 2>/dev/null && echo "---TEMPLATE---" && cat .github/pull_request_template.md 2>/dev/null || true
   ```

   **If on `main` or `master`, stop immediately.** Tell the user: "You're on
   main. Use /gc to commit first (it will auto-create a branch), then run /pr."
   Do NOT attempt to create a branch or commit here — that is /gc's job.

   **If there are no commits ahead of main**, stop. Nothing to PR.

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

5. Push and create the PR in one step. Run exactly one Bash command:

   ```
   git push -u origin HEAD && gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body here>
   EOF
   )"
   ```

   If GPG signing fails, retry with `--no-gpg-sign`.
   Print the PR URL from the output.

6. **Post-PR conflict check.** Run exactly one Bash command:

   ```
   git fetch origin main && git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main 2>/dev/null | head -20
   ```

   If the output contains conflict markers, tell the user there are merge
   conflicts and offer to rebase.

7. **Issue check.** Run exactly one Bash command:

   ```
   gh issue list --state open --limit 10
   ```

   If any open issues are related to this PR's changes, mention them and ask
   if any should be linked or closed.

Total: 3-5 Bash calls. Do not run any other commands beyond what is listed.

Never force-push. Never target main/master as the head branch.
