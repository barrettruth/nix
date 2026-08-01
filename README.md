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
  hosts/{desktop,laptop,mac,vps}
  darwin/                        nix-darwin modules
  nixos/
  devshells.nix                  project-specific development shells
  theme.nix                      central palette definition
config/                          app configs (symlinked into XDG dirs)
scripts/                         runtime scripts
secrets/                         sops-encrypted secrets
pkgs/                            custom derivations
```

## Hosts

- **laptop**: Dell XPS 9500 workstation.
- **desktop**: NixOS workstation, primary self-host. [Forgejo](https://forgejo.org/) at `forge.barrettruth.com`, Vaultwarden at [`vault.barrettruth.com`](https://github.com/dani-garcia/vaultwarden), [delta](https://forge.barrettruth.com/barrettruth/delta) at `delta.barrettruth.com`, `finance.barrettruth.com`, and static sites (`barrettruth.com`, `barrettruth.sh`, `philipmruth.com`, `vimdoc-language-server.com`, `ts.barrettruth.com`).
- **vps**: NixOS VPS. [Authelia](https://www.authelia.com/) at `auth.barrettruth.com` and [Headscale](https://headscale.net/) at `headscale.barrettruth.com`.
- **mac**: Apple silicon MacBook, built from `.#darwinConfigurations.mac` with `just rebuild-mac`.

One thing on the mac is set once per machine and cannot be declared: **a still
image has to be chosen as the wallpaper** in Settings > Wallpaper. macOS ships
a dynamic wallpaper, and while one is active `WallpaperAgent` renders over
anything `NSWorkspace.setDesktopImageURL` sets, so `ctl wallpaper gen` reports
success and changes nothing.

The baremak layout is installed to `/Library/Keyboard Layouts` and enabled
through `AppleEnabledInputSources`, so it needs no setup, but a newly enabled
input source only reaches the menu bar after a logout.

