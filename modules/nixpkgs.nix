{ lib, inputs, ... }:
let
  neovimChannel = "nightly";

  overlays = [
    (_final: prev: {
      "neovim-main-unwrapped" = prev.neovim-unwrapped;
    })
    inputs.neovim-nightly.overlays.default
    inputs.codex.overlays.default
    inputs.devin.overlays.default
    (
      final: prev:
      let
        system = final.stdenv.hostPlatform.system;
        neovimPackages = {
          main = final."neovim-main-unwrapped";
          nightly = prev.neovim;
        };
      in
      {
        barrett-fonts = inputs.fonts.packages.${system}.desktop;
        barrett-webfonts = inputs.fonts.packages.${system}.web;
        delta-software-sync = final.callPackage ../pkgs/delta-software-sync { };
        delta-cli = inputs.delta.packages.${system}.cli;
        direnv-instant = inputs.direnv-instant.packages.${system}.direnv-instant.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ../pkgs/direnv-instant-mux-nvim.patch ];
        });
        google-workspace-cli = inputs.googleworkspace-cli.packages.${system}.default;
        google-workspace-guard = final.callPackage ../pkgs/google-workspace-guard {
          gws = final.google-workspace-cli;
        };
        neovim = final.callPackage ../pkgs/neovim {
          neovimPackage = neovimPackages.${neovimChannel};
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
          neovim
          ;
      };
    };
}
