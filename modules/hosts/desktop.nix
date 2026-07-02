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
      inputs.direnv-instant.nixosModules.direnv-instant
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
          barrett.ui.gpu = "nvidia";
          programs.direnv.enable = true;
          programs.direnv.enableZshIntegration = false;
          programs.direnv.nix-direnv.enable = true;
          programs.direnv.settings.global = {
            hide_env_diff = true;
            log_filter = "^direnv: ((loading|using flake|export )|nix-direnv: Using cached dev shell)";
          };
          programs.direnv-instant = {
            enable = true;
            package = pkgs.direnv-instant;
            enableBashIntegration = false;
            enableFishIntegration = false;
            enableZshIntegration = true;
          };
          nixpkgs.hostPlatform = platform;
          nixpkgs.overlays = overlays;
          nixpkgs.config.allowUnfreePredicate =
            pkg:
            builtins.elem (lib.getName pkg) (
              sharedUnfree
              ++ [
                "nvidia-x11"
                "nvidia-settings"
                "nvidia-kernel-modules"
                "cuda_cccl"
                "cuda_cudart"
                "libcublas"
                "cuda_nvcc"
              ]
            );
        }
      )
    ];
    specialArgs = {
      inherit
        desktopBuildPool
        identity
        inputs
        palettes
        themeGenerators
        ;
      whisperPkgs = import inputs.nixpkgs-whisper {
        system = platform;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (lib.getName pkg) [
            "cuda_cccl"
            "cuda_cudart"
            "libcublas"
            "cuda_nvcc"
          ];
      };
    };
  };
}
