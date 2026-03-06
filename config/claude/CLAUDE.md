# Global Claude Code User Preferences

Never, under any circumstances, generate code containing new, non-preexisting comments.

Never, under any circumstances, respond with excerpts of code with no
explanation unless explicitly specified.

Never, under any circumstances, create commits, stage files, or create pull
requests unless explicitly specified.

If given express permission to use git, NEVER sign yourself as a contributor OR mention yourself in the PR.

If given express permission to use git, NEVER push to a main/master branch. This applies whether pushing by current branch name, by explicit refspec (e.g. `git push origin main`), or via `HEAD:main`. The hook will block you — do not attempt workarounds.

If given express permission to use git, if GPG signing fails for any reason, always retry with `--no-gpg-sign` rather than stopping or asking.

If given express permission to use git, NEVER commit ai-related files (e.g. CLAUDE.md).

If given express permission to use git, ALWAYS work on a feature branch. If on
`main` or `master`, create and switch to a branch before making changes. Branch
naming: `type/short-description` (e.g. `fix/diagnostic-range`).

If given express permission to use git, ALWAYS use this commit message format:

    type(scope): imperative summary

- Valid types: `feat` `fix` `docs` `refactor` `perf` `test` `ci` `build` `revert`
- Scope is optional, lowercase. Subject: lowercase after colon, no trailing period, max 72 chars.
- Body required for non-trivial commits, using `Problem:` / `Solution:` format.
  Keep each section to 2-3 sentences.
- One logical change per commit. Refactors, formatting, and features must be separate commits.
- Use backticks around code identifiers, function names, and file paths in
  commit messages and PR descriptions (e.g. `setup()`, `lua/oil/view.lua`).

If given express permission to use git, ALWAYS check for a PR template at
`.github/pull_request_template.md` and follow it. If none exists, use
Problem/Solution format as described in `~/.config/claude/rules/git.md`.

Never, under any circumstances, assume or fabricate APIs for
unknown/lesser-known services and APIs, such as NeoVim, NixOS, or other obscure
packages-always do your research first.
