# nix

My personal nix configuration leveraging:

- [NixOS](https://nixos.org/)
- [Determinate Nix](https://github.com/DeterminateSystems/determinate)
- [Dendritic Nix](https://github.com/DeterminateSystems/detsys-ts/wiki/Dendritic-Nix)
- [flakes](https://wiki.nixos.org/wiki/Flakes) & [flake-parts](https://github.com/hercules-ci/flake-parts)

Hosts a Dell XPS 9500 Laptop and NetCup NixOS VPS.

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
