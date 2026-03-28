{ inputs, lib, overlays, sharedUnfree, ... }:
let
  hostConfig = {
    isNixOS = true;
    isLinux = true;
    isDarwin = false;
    gpu = "nvidia";
    backlightDevice = "intel_backlight";
    platform = "x86_64-linux";
  };
in
{
  flake.nixosConfigurations.xps15 = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.nixos-hardware.nixosModules.dell-xps-15-9500-nvidia
      inputs.hyprland.nixosModules.default
      ../../hosts/xps15/configuration.nix
      {
        nixpkgs.hostPlatform = hostConfig.platform;
        nixpkgs.overlays = overlays;
        nixpkgs.config.allowUnfreePredicate =
          pkg:
          builtins.elem (lib.getName pkg) (
            sharedUnfree
            ++ [
              "nvidia-x11"
              "nvidia-settings"
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
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.sharedModules = [ inputs.direnv-instant.homeModules.direnv-instant ];
        home-manager.users.barrett = import ../../home/home.nix;
        home-manager.extraSpecialArgs = {
          inherit (inputs) zen-browser hyprland;
          inherit hostConfig;
        };
      }
    ];
    specialArgs = {
      nixpkgs = inputs.nixpkgs;
    };
  };
}
