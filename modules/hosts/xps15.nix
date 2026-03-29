{ inputs, lib, overlays, sharedUnfree, palettes, themeGenerators, ... }:
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
      inputs.determinate.nixosModules.default
      inputs.nixos-hardware.nixosModules.dell-xps-15-9500-nvidia
      inputs.hyprland.nixosModules.default
      ../../hosts/xps15/configuration.nix
      ../nixos/packages.nix
      ../nixos/environment.nix
      ../nixos/services.nix
      ../nixos/activation.nix
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
    ];
    specialArgs = {
      nixpkgs = inputs.nixpkgs;
      inherit (inputs) zen-browser hyprland;
      inherit palettes themeGenerators hostConfig;
    };
  };
}
