---
name: just-nix
description: Prefer repo justfile recipes and nix shells when a repository uses them
user-invocable: true
version: 1.0.0
---

# /just-nix

Use a repository's existing `justfile` and Nix shell as the primary command and
verification surface.

## Detection

At the repo root, inspect:

- `justfile` / `Justfile`
- `flake.nix`
- `.envrc`
- `scripts/ci.sh`
- repo guidance files (`CLAUDE.md`, `AGENTS.md`, `.devin/AI_AGENTS.md`)

If a `justfile` exists, run `just --summary` before using any recipe names.

## Preferred command surface

- If the repo root has `justfile`, use `just` recipes instead of raw ad-hoc
  commands for recurring tasks like `run`, `build`, `test`, `lint`, `format`,
  and `ci`.
- Do not invent recipe names. Only use recipes returned by `just --summary`.
- If both `justfile` and `scripts/ci.sh` exist and the repo defines `ci`,
  prefer `just ci` as the canonical workflow and treat `scripts/ci.sh` as a
  compatibility shim unless repo docs explicitly say otherwise.

## Preferred environment surface

- If the repo has `flake.nix` or `.envrc`, assume commands may need the repo's
  Nix shell.
- If the repo has `.envrc` and `direnv` is available, prefer
  `direnv exec <repo-root> <command>` for one-shot commands that should use the
  default dev shell. This reuses nix-direnv's cached environment and avoids the
  persistent `/tmp/nix-develop-*` and `/tmp/nix-shell.*` churn caused by
  repeated `nix develop --command ...`.
- For CI-like verification, prefer `nix develop .#ci --command just ci` when
  the repo defines both `.#ci` and `ci`.
- Otherwise use the narrowest documented shell entrypoint, such as
  `nix develop --command just test` or the repo's existing shell-wrapped
  command.
- Use plain `just` for quick discovery only when the needed tooling is already
  available in the current shell or repo docs explicitly say that is the normal
  flow.

## Verification order

Before finishing work, run the narrowest available repo checks first:

1. `just format`
2. `just lint`
3. `just test`
4. `just ci`

Only run what the repo actually defines.

## Fallbacks

If no `justfile` exists, use the repo's existing command surface
(`scripts/ci.sh`, package-manager scripts, `make`, `cargo`, etc.) while still
respecting `flake.nix` / `.envrc`.
