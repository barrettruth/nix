{ lib, inputs, ... }:
let
  overlays = [
    inputs.codex.overlays.default
    inputs.devin.overlays.default
    (
      final: _prev:
      let
        system = final.stdenv.hostPlatform.system;
      in
      {
        barrett-fonts = inputs.fonts.packages.${system}.desktop;
        barrett-webfonts = inputs.fonts.packages.${system}.web;
        delta-software-sync = final.callPackage ../pkgs/delta-software-sync { };
        delta-cli = inputs.delta.packages.${system}.cli;
        google-workspace-cli = inputs.googleworkspace-cli.packages.${system}.default;
        google-workspace-guard = final.callPackage ../pkgs/google-workspace-guard {
          gws = final.google-workspace-cli;
        };
      }
    )
    (
      final: prev:
      let
        system = final.stdenv.hostPlatform.system;
      in
      {
        tmuxPlugins = prev.tmuxPlugins // {
          mosaic = inputs.tmux-mosaic.packages.${system}.default;
        };
      }
    )
  ];

  sharedUnfree = [
    "slack"
    "apple_cursor"
    "devin"
  ];
in
{
  _module.args = {
    inherit overlays sharedUnfree;
  };

  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) sharedUnfree;
      };
    in
    {
      _module.args.pkgs = pkgs;
      packages = {
        inherit (pkgs)
          barrett-fonts
          barrett-webfonts
          delta-software-sync
          ;
      };
    };
}
