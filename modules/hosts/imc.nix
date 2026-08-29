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
  platform = "aarch64-darwin";
  darwinOverlays = import ../darwin/overlays.nix;
in
{
  flake.darwinConfigurations.imc = inputs.nix-darwin.lib.darwinSystem {
    modules = [
      ../darwin/common/activation.nix
      ../darwin/common/nix.nix
      ../darwin/common/sops.nix
      ../darwin/common/ssh.nix
      ../darwin/common/tailscale.nix
      ../darwin/barrett/workstation.nix
      ../barrett/workstation.nix
      ../../hosts/imc/configuration.nix
      {
        nixpkgs.hostPlatform = platform;
        nixpkgs.overlays = overlays ++ darwinOverlays;
        nixpkgs.config.allowUnfreePredicate =
          pkg: builtins.elem (lib.getName pkg) (sharedUnfree ++ [ "google-chrome" ]);
      }
    ];
    specialArgs = {
      isDarwin = true;
      inherit
        inputs
        identity
        palettes
        themeGenerators
        ;
    };
  };
}
