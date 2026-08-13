# nix

My personal nix configuration leveraging:

> [!NOTE]
> Due to GitHub's historic unreliability, active development is hosted on
> [Forgejo](https://forge.barrettruth.com/barrettruth/nix).
> GitHub is maintained as a read-only mirror.

- [NixOS](https://nixos.org/)
- [Determinate Nix](https://github.com/DeterminateSystems/determinate)
- [Dendritic Nix](https://github.com/DeterminateSystems/detsys-ts/wiki/Dendritic-Nix)
- [flakes](https://wiki.nixos.org/wiki/Flakes) & [flake-parts](https://github.com/hercules-ci/flake-parts)
- [nix-darwin](https://github.com/nix-darwin/nix-darwin)

Hosts a Dell XPS 9500 laptop, a NixOS PC, a NixOS VPS, and an Apple silicon
MacBook.

## Configuration Structure

```
flake.nix
hosts/
modules/
  hosts/{desktop,imc,laptop,mac,vps}
  barrett/                       cross-platform workstation
  darwin/                        nix-darwin modules
  nixos/
  devshells.nix                  project-specific development shells
  theme.nix                      central palette definition
config/                          app configs (symlinked into XDG dirs)
services/                        services a host can adopt, see below
scripts/                         runtime scripts
secrets/                         sops-encrypted secrets
pkgs/                            custom derivations
```

## Moving a service between hosts

Anything under `services/` is host-agnostic: it names its secrets through
`mkSecret`, which each host binds to its own `mkVpsSecret`/`mkDesktopSecret` in
`hosts/<host>/configuration.nix`. These services serve a single public hostname
off a single database, so exactly one host may import a given one at a time.

To hand a service to another host, move its import line between the two
`configuration.nix` files, `git mv` its secrets into the new host's
`secrets/<host>/` and `sops updatekeys` them, and repoint the DNS record. The
desktop's DDNS derives its record list from `services.nginx.virtualHosts`, so
dropping the import is also what stops the desktop reclaiming the name.

## Hosts

- **laptop**: Dell XPS 9500 workstation.
- **desktop**: headless NixOS server and remote build host. Forgejo at [`forge.barrettruth.com`](https://forgejo.org/) and `finance.barrettruth.com`. Runs no compositor: `barrett.ui.enable` is off, so the Hyprland stack, desktop applications and fonts are absent and only the terminal development environment is installed.
- **vps**: NixOS VPS. [Vaultwarden](https://github.com/dani-garcia/vaultwarden) at `vault.barrettruth.com`, [Authelia](https://www.authelia.com/) at `auth.barrettruth.com`, [Headscale](https://headscale.net/) at `headscale.barrettruth.com`, and the static sites (`barrettruth.com`, `barrettruth.sh`, `philipmruth.com`, `vimdoc-language-server.com`, `ts.barrettruth.com`). `forge.barrettruth.com` and `git.barrettruth.com` redirect to GitHub.
- **mac**: Apple silicon MacBook, built from `.#darwinConfigurations.mac` with `just rebuild-mac`.
- **imc**: work MacBook, built with `just rebuild-imc`. Shares
  `modules/darwin/barrett` with the mac and differs by what it leaves out:
  the machine is enrolled in an MDM, so nothing here writes to
  `/Library/Managed Preferences` or sets `networking.computerName`, and
  neither sops nor tailscale is imported.

One thing on the mac is set once per machine and cannot be declared: **a still
image has to be chosen as the wallpaper** in Settings > Wallpaper. macOS ships
a dynamic wallpaper, and while one is active `WallpaperAgent` renders over
anything `NSWorkspace.setDesktopImageURL` sets, so `ctl wallpaper gen` reports
success and changes nothing.

The baremak layout is installed to `/Library/Keyboard Layouts` and enabled
through `AppleEnabledInputSources`, so it needs no setup, but a newly enabled
input source only reaches the menu bar after a logout.

