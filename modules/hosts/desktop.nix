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
      {
        barrett.ui.enable = true;
        barrett.ui.gpu = "generic";
        nixpkgs.hostPlatform = "x86_64-linux";
        nixpkgs.overlays = overlays;
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) sharedUnfree;
      }
    ];
    specialArgs = {
      inherit
        identity
        inputs
        palettes
        themeGenerators
        ;
    };
  };
}
