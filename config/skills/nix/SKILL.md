---
name: nix
description: Use when working with Nix — flakes, NixOS or nix-darwin modules, packages, development shells, rebuilds, evaluations, and checks. Establish real state with read-only commands, then report concisely.
---

# nix

Agent shells do not load direnv environments automatically. Whenever this skill
is invoked in a repository, run commands through `direnv exec . <cmd>` if
direnv is available and an `.envrc` applies. Otherwise use the repository's
documented environment entry point.
