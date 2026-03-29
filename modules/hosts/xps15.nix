{
  inputs,
  lib,
  overlays,
  sharedUnfree,
  palettes,
  themeGenerators,
  ...
}:
let
  username = "barrett";
  homeDirectory = "/home/${username}";
  hostConfig = {
    inherit username homeDirectory;
    XDG_CONFIG_HOME = "${homeDirectory}/.config";
    XDG_DATA_HOME = "${homeDirectory}/.local/share";
    XDG_STATE_HOME = "${homeDirectory}/.local/state";
    XDG_CACHE_HOME = "${homeDirectory}/.cache";
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
      inputs.direnv-instant.nixosModules.direnv-instant
      ../../hosts/xps15/configuration.nix
      ../nixos/packages.nix
      ../nixos/environment.nix
      ../nixos/services.nix
      ../nixos/activation.nix
      {
        programs.direnv-instant.enable = true;
        programs.direnv.nix-direnv.enable = true;
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
      inherit (inputs) nixpkgs;
      inherit (inputs) zen-browser hyprland;
      inherit palettes themeGenerators hostConfig;
    };
  };
}
