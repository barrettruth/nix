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
      inputs.determinate.darwinModules.default
      ../darwin/common/activation.nix
      ../darwin/common/keylayout.nix
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
