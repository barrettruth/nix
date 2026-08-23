{
  inputs,
  identity,
  lib,
  overlays,
  sharedUnfree,
  palettes,
  themeGenerators,
  ...
}:
let
  platform = "x86_64-linux";
  desktopBuildPool = import ./desktop-build-pool.nix;
in
{
  flake.nixosConfigurations.desktop = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.determinate.nixosModules.default
      inputs.disko.nixosModules.disko
      ../../hosts/desktop/configuration.nix
      ../nixos/barrett
      ../nixos/common/nix.nix
      ../nixos/common/nix-ld.nix
      ../nixos/common/ssh.nix
      ../nixos/common/sops.nix
      ../nixos/common/tailscale.nix
      (
        { pkgs, ... }:
        {
          barrett.workstation.enable = true;
          barrett.ui.enable = false;
          programs.direnv.enable = true;
          programs.direnv.enableZshIntegration = false;
          programs.direnv.nix-direnv.enable = true;
          programs.direnv.settings.global = {
            hide_env_diff = true;
            log_filter = "^direnv: ((loading|using flake|export )|nix-direnv: Using cached dev shell)";
          };
          nixpkgs.hostPlatform = platform;
          nixpkgs.overlays = overlays;
          nixpkgs.config.allowUnfreePredicate =
            pkg:
            builtins.elem (lib.getName pkg) (
              sharedUnfree
              ++ [
                "nvidia-x11"
                "nvidia-kernel-modules"
              ]
            );
        }
      )
    ];
    specialArgs = {
      isDarwin = false;
      inherit
        desktopBuildPool
        identity
        inputs
        palettes
        themeGenerators
        ;
    };
  };
}
