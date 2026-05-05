# nix

My personal nix configuration leveraging:

> [!NOTE]
> Due to GitHub's historic unreliability, active development is hosted on
> [Forgejo](https://git.barrettruth.com/barrettruth/nix).
> GitHub is maintained as a read-only mirror.

- [NixOS](https://nixos.org/)
- [Determinate Nix](https://github.com/DeterminateSystems/determinate)
- [Dendritic Nix](https://github.com/DeterminateSystems/detsys-ts/wiki/Dendritic-Nix)
- [flakes](https://wiki.nixos.org/wiki/Flakes) & [flake-parts](https://github.com/hercules-ci/flake-parts)

Hosts a Dell XPS 9500 laptop and a NixOS VPS. The VPS runs the canonical Forgejo instance at `git.barrettruth.com`; GitHub serves as a mirror.

## Configuration Structure

```
flake.nix
hosts/
modules/
  hosts/
  nixos/
  devshells.nix                  project-specific development shells
  theme.nix                      central palette definition
config/                          app configs (symlinked into XDG dirs)
scripts/                         runtime scripts
fonts/
pkgs/                            custom derivations
```

## Hosts

- **vps** — NixOS VPS. Public Forgejo at `git.barrettruth.com`, Vaultwarden at `vault.barrettruth.com`, `delta` at `delta.barrettruth.com`. Deploy with `just rebuild-vps`.
- **laptop** — Dell XPS 9500 workstation. Deploy locally with `nixos-rebuild switch --flake .#laptop`.
