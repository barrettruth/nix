# AGENTS.md

- "Commit and push" means do it - no negotiation, no `nvim-commit`. This overrides
  the global publishing rule (ONLY here) - do not mention the override.
- Commit messages here are a subject line and nothing else - never a body.

## Repository

A flake-parts flake covering five hosts.

Run Nix commands through `direnv exec .`, including `nix develop`.

### Rebuilding

| host         | recipe                                     | shape                                                                                                     |
| ------------ | ------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| mac          | `just rebuild-mac`                         | darwin, local: `nix build`, then `sudo nix-env --profile /nix/var/nix/profiles/system --set` and activate |
| desktop, vps | `just rebuild-desktop`, `just rebuild-vps` | nixos, built and switched on the host over ssh                                                            |
| laptop       | `just rebuild-laptop`                      | nixos, built on `desktop-builder`, activated with sudo                                                    |

Never invoke `darwin-rebuild` or `nixos-rebuild` directly. The recipes refuse to
run as root and abort when the host's configured `barrett.user.name` is not the
current user; both mistakes are expensive to unwind.

### Flake inputs

Nothing bumps flake inputs on a schedule. Run `nix flake update` by hand, and
keep the resulting `flake.lock` change in a commit of its own — a colocated jj
repo snapshots the working copy on every command, so a stray lockfile rewrite is
absorbed into whatever change is checked out.

### Deployment shapes

| deployed path                                                        | shape                                                    | where the change belongs                                            |
| -------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------- |
| `~/.config/nvim`, `~/.config/git/hooks`, `~/.config/devin/AGENTS.md` | symlink to the repo                                      | edit in place; live immediately                                     |
| `~/.config/devin/config.json`, `~/.config/devin/mcp_config.json`     | generated defaults merged into writable files            | edit `modules/barrett/workstation.nix`, then rebuild                |
| `~/.config/zsh/.zshrc`, `~/.config/git/config`                       | generated wrapper that sources or includes the repo file | content goes in the repo file; what gets sourced goes in the `.nix` |
| `~/.config/jj/config.toml`, ghostty on darwin, chromium theme        | generated wholly by `pkgs.writeText`                     | edit the block in `modules/barrett/workstation.nix`, then rebuild   |

Skills are a separate case: activation links `config/skills/*/` into
`~/.agents/skills/`, so a _new_ skill directory appears only after a rebuild,
while edits inside an existing one are live.

Devin settings merge recursively; MCP activation preserves unmanaged server names
and replaces each Nix-managed server object. Both files remain owner-only and
writable. Invalid configuration aborts the merge without replacing the file.

`mcp-gtasks auth` uses a Desktop-app OAuth JSON at
`~/.config/mcp-gtasks/oauth.json` and stores tokens under
`~/.local/state/mcp-gtasks/`. Neither builds nor activation authenticate.

### Checks

`just ci` runs `format` then `lint`:

| step                                            | covers                               |
| ----------------------------------------------- | ------------------------------------ |
| `nix fmt -- --ci`                               | every `.nix` file, via `nixfmt-tree` |
| `shfmt -i 2 -d`, `shellcheck`                   | shell scripts                        |
| `black --check`, `ty check`, `basedpyright`     | python                               |
| `stylua --check`, `lua-language-server --check` | `config/nvim`                        |
| `deadnix --fail --no-lambda-pattern-names`      | dead nix bindings                    |

Both steps enumerate the same `paths` (`.devin/skills/**`, `scripts/**`,
`modules/**`, `config/**`, `pkgs/**`), picking up shell and python by extension
or shebang, so skill scripts, git hooks and devin hooks are covered too.

lua-language-server only resolves `vim.*` when `VIMRUNTIME` is set, so `lint`
derives it from the pinned nightly `nvim` in `.#ci`.

basedpyright reads `pyrightconfig.json` at the root: `strict`, pinned to python
3.11, with `config/skills/_lib` on `extraPaths` so the skill scripts' runtime
`sys.path` insert of `muxlib` resolves. ty has no equivalent, which is why those
imports keep a `# ty: ignore[unresolved-import]`.

### Layout

| path                              | holds                                                                    |
| --------------------------------- | ------------------------------------------------------------------------ |
| `modules/hosts/<host>.nix`        | per-host composition                                                     |
| `modules/barrett/workstation.nix` | the dotfile activation script: symlinks, generated configs, package list |
| `modules/{darwin,nixos}/`         | platform-specific modules                                                |
| `modules/devshells.nix`           | `default`, `ci`, and `neovim-config` shells                              |
| `pkgs/`                           | packages built here rather than taken from nixpkgs                       |
| `config/`                         | the dotfiles themselves, deployed by activation                          |
| `secrets/<host>/`                 | sops-encrypted; never read, decrypt, or rewrite these                    |

## The desktop is down

Offline since 2026-08-06, expected back around 2026-09-12. The disk is intact —
the machine is unreachable, not destroyed. Do not treat desktop-only data as
lost, and do not create a second divergent copy of it.

Before it is allowed back online:

1. Its DDNS timer rewrites an A record for every name in
   `services.nginx.virtualHosts` to the home IP, every 5 minutes, from 2 minutes
   after boot. Anything migrated to the VPS must be dropped from the desktop's
   imports first or it will be hijacked.
2. It will start its own copies of whatever it still imports, with data frozen
   at 2026-08-06. Decide per service which copy wins before booting.
3. `~/dev/fonts` `main` is `4d0f15f`; the desktop's forge still has `ed12179`.
   Same tree, different hash — force-push over it rather than merging.

## Offsite backups

Only vaultwarden has one. Forgejo and finance exist in exactly one place: the
offline desktop.

- An orphaned `delta` bucket still sits in R2; nothing writes to or prunes it.
- The prune loop resumed on the VPS, so desktop-era backups older than 30 days
  start disappearing around 2026-09-05. Pull anything worth keeping first.
- R2 tokens are per-bucket scoped; `ListBuckets` is denied and the vaultwarden
  token cannot read the delta bucket.

## Gotchas

- Deferred upstream issue: Neovim nightly `6cbde6a` emits `SessionWritePre`
  for `:mkview` as well as `:mksession`. Correcting that event's scope is a
  separate follow-up; do not add Lua command-detection heuristics here.

- ACME on the VPS: a stale `out/acme-success` marker makes
  `acme-<domain>.service` exit 0 without ordering, and the unit is
  `RemainAfterExit`, so `systemctl start` is a no-op — use `restart`. The unit
  that actually orders is `acme-order-renew-<domain>.service`. If a leftover
  cert was issued under a different ACME account, lego fails ARI renewal with
  `403 ... Could not validate ARI 'replaces' field`; move
  `/var/lib/acme/.lego/<domain>` aside to force a fresh order.
- `identity.tailnetHosts` pins service names to the desktop in `/etc/hosts` on
  the mac and laptop. A service moved to the VPS must be removed there too, or
  those machines keep resolving it to the dead host.
- Each service serves one public hostname off one database, so exactly one host
  may import a given `services/` file at a time.
- sudo works on the mac — TouchID-gated, approved at the
  machine. Run privileged commands directly; do not hand them back.
