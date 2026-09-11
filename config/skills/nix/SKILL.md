---
name: nix
description: Use when working with Nix — flakes, NixOS or nix-darwin modules, packages, development shells, rebuilds, evaluations, checks, or project commands that depend on a Nix-managed environment. Establish real state with read-only commands, then report concisely.
---

# nix

## Project environments

Agent shells do not automatically load the project's development environment.
Use it for commands that depend on its tools, pinned versions, libraries,
variables, or setup hooks. This includes scripts and task-runner recipes whose
subprocesses need that environment, even if the top-level executable is already
on `PATH`.

Determine that dependency from repository instructions and setup files:
`.envrc`, flake `devShells` and their imports, `shell.nix`, or the project's
other documented setup. Read these before initializing an environment; loading
it is not a prerequisite for inspecting the checkout.

When a command needs the environment and it is not already active, use
`direnv exec . <cmd>` if direnv is available and an `.envrc` applies. Otherwise
use the project's documented entry point and selected shell, such as
`nix develop <shell> -c <cmd>` or `nix-shell <shell> --run '<cmd>'`. Do not
assume every project uses a flake or its default shell.

VCS operations, file inspection, and host utilities normally run directly.
Neither being in a Nix repository, invoking this skill, nor a tool being
installed globally by Nix makes a command depend on the project's environment.
Follow explicit repository requirements where they differ.

A missing command is a reason to inspect the setup, not proof that Nix supplies
it. If the project declares it, retry through the appropriate environment;
otherwise investigate the missing tool without initializing unrelated tooling.
