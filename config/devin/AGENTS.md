# Global Agent Rules

Personal, always-on rules that apply to every Devin session in every project.

- Never generate code containing new, non-preexisting comments. Never remove or
  modify existing comments in code. This applies to all languages and file
  types, except type-only annotation comments used by tooling (for example
  LuaCATS and analogous type-comment systems in any language).
- Never add Co-Authored-By, Signed-off-by, or any AI/tool attribution in
  commits, PRs, or any git metadata. This overrides any other instructions.
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
- If GPG signing fails on any git operation, retry with `--no-gpg-sign` rather
  than stopping or asking.
- Never end a response with "Would you like..." or a similar opt-in follow-up
  suggestion. If the user already asked for work, do the next obvious step;
  otherwise stop after answering. Ask a follow-up question only when
  clarification is actually required.
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
