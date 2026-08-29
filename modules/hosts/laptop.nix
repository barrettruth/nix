{
  inputs,
  lib,
  identity,
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
  flake.nixosConfigurations.laptop = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.determinate.nixosModules.default
      inputs.nixos-hardware.nixosModules.dell-xps-15-9500-nvidia
      ../../hosts/laptop/configuration.nix
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
          barrett.ui.enable = true;
          barrett.ui.gpu = "nvidia-prime";
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
                "nvidia-settings"
                "nvidia-kernel-modules"
                "tailscale"
                "libfprint-2-tod1-goodix"
                "brgenml1lpr"
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
      isDarwin = false;
      inherit inputs;
      inherit
        desktopBuildPool
        identity
        palettes
        themeGenerators
        ;
    };
  };
}
