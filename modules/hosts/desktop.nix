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
      inputs.disko.nixosModules.disko
      ../../hosts/desktop/configuration.nix
      ../nixos/barrett
      ../nixos/common/nix.nix
      ../nixos/common/nix-ld.nix
      ../nixos/common/ssh.nix
      ../nixos/common/sops.nix
      ../nixos/common/tailscale.nix
      (
        { ... }:
        {
          barrett.workstation.enable = true;
          barrett.ui.enable = false;
          barrett.whisper.enable = true;
          nixpkgs.hostPlatform = platform;
          nixpkgs.overlays = overlays;
          nixpkgs.config.allowUnfreePredicate =
            pkg:
            builtins.elem (lib.getName pkg) (
              sharedUnfree
              ++ [
                "nvidia-x11"
                "nvidia-kernel-modules"
                "cuda_cccl"
                "cuda_cudart"
                "cuda_nvrtc"
                "libcublas"
                "cuda_nvcc"
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
