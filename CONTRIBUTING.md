# Contributing

Development, issues, and pull requests happen on
[Forgejo](https://git.barrettruth.com/barrettruth/nix).

## Scope

nix is Barrett's NixOS, desktop, tooling, and service configuration. It is not
a reusable Nix framework, public module collection, or general-purpose dotfiles
template.

## Pull Requests

Bug fixes, documentation fixes, and configuration fixes are welcome.
AI-generated contributions are not accepted.

For new behavior, open an issue first unless the change is small and already
fits the repository's scope.

Behavior or configuration changes should update relevant Markdown or other
documentation when appropriate.

## Development

It is preferred to use the Nix development shell, which bundles all necessary
tools:

```sh
nix develop
```

## Checks

Run the relevant local checks before opening a pull request. For broad changes,
use the existing recipes:

```sh
nix develop --command just format
nix develop --command just lint
```

When unrelated formatting drift is already present, use targeted verification
for the files you changed and note the skipped full check in the pull request.
