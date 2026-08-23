---
name: nix
description: Use when working in the nix configuration at ~/.config/nix — rebuilding a host, editing a module or package, running the repo's checks, or when an edit to a dotfile appears to have had no effect. Establish real state with read-only commands, then report concisely.
---

# nix

A flake-parts flake at `~/.config/nix` covering five hosts. The CI toolchain is
installed globally by the same configuration it builds, so recipes run bare;
`nix develop -c <cmd>` is the fallback when something is missing.

## Rebuilding

| host | recipe | shape |
|---|---|---|
| mac, imc | `just rebuild-mac`, `just rebuild-imc` | darwin, local: `nix build`, then `sudo nix-env --profile /nix/var/nix/profiles/system --set` and activate |
| desktop, vps | `just rebuild-desktop`, `just rebuild-vps` | nixos, built and switched on the host over ssh |
| laptop | `just rebuild-laptop` | nixos, built on `desktop-builder`, activated with sudo |

Never invoke `darwin-rebuild` or `nixos-rebuild` directly. The recipes refuse to
run as root and abort when the host's configured `barrett.user.name` is not the
current user; both mistakes are expensive to unwind.

Nothing bumps flake inputs on a schedule. Run `nix flake update` by hand, and
keep the resulting `flake.lock` change in a commit of its own — a colocated jj
repo snapshots the working copy on every command, so a stray lockfile rewrite is
absorbed into whatever change is checked out.

## When an edit appears to do nothing

Three deployment shapes, and the fix differs by shape:

| deployed path | shape | where the change belongs |
|---|---|---|
| `~/.config/nvim`, `~/.config/git/hooks`, `~/.config/devin/*` | symlink to the repo | edit in place; live immediately |
| `~/.config/zsh/.zshrc`, `~/.config/git/config` | generated wrapper that sources or includes the repo file | content goes in the repo file; what gets sourced goes in the `.nix` |
| `~/.config/jj/config.toml`, aws, ghostty on darwin, chromium theme | generated wholly by `pkgs.writeText` | edit the block in `modules/barrett/workstation.nix`, then rebuild |

Skills are a fourth case: activation links `config/skills/*/` into
`~/.agents/skills/`, so a *new* skill directory appears only after a rebuild,
while edits inside an existing one are live.

## Checks

`just ci` runs `format` then `lint`:

| step | covers |
|---|---|
| `nix fmt -- --ci` | every `.nix` file, via `nixfmt-tree` |
| `shfmt -i 2 -d`, `shellcheck` | shell scripts |
| `black --check`, `ty check`, `basedpyright` | python |
| `stylua --check`, `lua-language-server --check` | `config/nvim` |
| `deadnix --fail --no-lambda-pattern-names` | dead nix bindings |

Both steps enumerate the same `paths` (`scripts/**`, `modules/**`, `config/**`,
`pkgs/**`), picking up shell and python by extension or shebang, so skill
scripts, git hooks and devin hooks are covered too.

basedpyright reads `pyrightconfig.json` at the root: `strict`, pinned to python
3.11, with `config/skills/_lib` on `extraPaths` so the skill scripts' runtime
`sys.path` insert of `muxlib` resolves. ty has no equivalent, which is why those
imports keep a `# ty: ignore[unresolved-import]`.

## Layout

| path | holds |
|---|---|
| `modules/hosts/<host>.nix` | per-host composition |
| `modules/barrett/workstation.nix` | the dotfile activation script: symlinks, generated configs, package list |
| `modules/{darwin,nixos}/` | platform-specific modules |
| `modules/devshells.nix` | `default`, `ci`, `neovim`, `neovim-src` shells |
| `pkgs/` | packages built here rather than taken from nixpkgs |
| `config/` | the dotfiles themselves, deployed by activation |
| `secrets/<host>/` | sops-encrypted; never read, decrypt, or rewrite these |
