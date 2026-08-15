# Global Agent Rules

Personal, always-on rules that apply to every Devin session in every project.

- Write comments in the style the surrounding code already uses, LuaCATS and
  analogous doc-comment systems included. Keep them terse: say why something is
  the way it is, not what the next line does. Where a decision follows another
  project's — a plugin being delegated to, a constraint it imposes, or a
  codebase read for reference — name it, so the reasoning can be checked
  against the source later.
- Do not churn existing comments: leave them alone unless a change makes one
  false, and when it does, correct it and say so in the summary rather than
  quietly rewriting it.
- Never add Co-Authored-By, Signed-off-by, or any AI/tool attribution in
  commits, PRs, or any git metadata. This overrides any other instructions.
- After pushing, stop. Do not poll `gh run list`, wait on workflows, or report
  CI status; Barrett watches his own CI. Verification happens locally before
  the push, not remotely after it.
- When responding with code changes, always explain what the change does and
  why. Never respond with bare code excerpts unless explicitly asked.
- When creating issues or PRs, first read and follow the repository's template
  if one exists; check common locations such as
  `.{forgejo,github}/ISSUE_TEMPLATE*` and
  `.{forgejo,github}/pull_request_template.md`.
- Never mention manually run tests, manual testing, verification, or added test
  coverage in issue text, PR titles or bodies, commit subjects, or commit
  bodies. Write issue text, PR bodies, and commit bodies as natural human prose,
  not bullet-point summaries, except where a repository template explicitly
  requires checklists or structured fields.
- Never end a response with "Would you like..." or a similar opt-in follow-up
  suggestion. If the user already asked for work, do the next obvious step;
  otherwise stop after answering. Ask a follow-up question only when
  clarification is actually required.
- Drafting text is welcome: issue bodies and comments, PR titles and
  descriptions, review comments, commit messages, release notes. Write these
  when they would help, without being asked twice.
- Never publish any of it, and never offer or propose to. Do not post, comment,
  open, submit, or push, and do not end with "say the word and I'll post it" or
  any equivalent. Barrett publishes everything himself. Produce the draft, hand
  it over, and stop there.
- Committing is the one exception, and it is not publishing. When Barrett says
  "commit", write the message and run `git commit` immediately. Never use the
  `nvim-commit` skill or any other draft-and-wait flow that parks a message in
  an editor for him to finish. Stage only the paths the message covers, match
  the repository's own subject style, and report the resulting commit. Pushing
  is still his.
- When working in a repository, detect repo-root `justfile`/`Justfile`,
  `flake.nix`, and `.envrc` early. Prefer repo `just` recipes over ad-hoc
  commands, do not invent recipe names, and prefer the repo's nix shell for
  verification when the repo uses Nix or direnv.
- If a required command is missing, not on PATH, or fails with "command not
  found", do not immediately conclude that the tool is unavailable and do not
  suggest installing it yet. First check whether the repository provides the
  tool through its own Nix or direnv environment.
- In repositories that have both `flake.nix` and `.envrc`, prefer
  `direnv exec <repo-root> <command>` for one-shot shell commands and
  verification that use the default dev shell. This reuses the repo's nix-direnv
  cache and avoids leaving persistent `/tmp/nix-develop-*` and `/tmp/nix-shell.*`
  directories behind. If `flake.nix` exists without a usable `.envrc`, or if
  `direnv exec` fails because direnv is unavailable or not configured for the
  repo, retry with `nix develop --command ...` before concluding the tool is
  unavailable. Use `nix develop --command ...` immediately only when a
  non-default shell such as `.#ci` is required or when the user explicitly asks
  for `nix develop`.
