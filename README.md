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

Hosts a Dell XPS 9500 laptop, a NixOS PC, a NixOS VPS, and two Apple silicon
MacBooks.

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

## Hosts

- **laptop**: Dell XPS 9500 workstation.
- **desktop**: headless NixOS server and remote build host. Forgejo at [`forge.barrettruth.com`](https://forgejo.org/) and `finance.barrettruth.com`. Runs no compositor: `barrett.ui.enable` is off, so the Hyprland stack, desktop applications and fonts are absent and only the terminal development environment is installed.
- **vps**: NixOS VPS. [Vaultwarden](https://github.com/dani-garcia/vaultwarden) at `vault.barrettruth.com`, [Authelia](https://www.authelia.com/) at `auth.barrettruth.com`, [Headscale](https://headscale.net/) at `headscale.barrettruth.com`, and the static sites (`barrettruth.com`, `barrettruth.sh`, `philipmruth.com`, `vimdoc-language-server.com`, `ts.barrettruth.com`). `forge.barrettruth.com` and `git.barrettruth.com` redirect to GitHub.
- **mac**: Apple silicon MacBook
- **imc**: work MacBook at [IMC](https://imc.com)
