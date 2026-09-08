{ lib, inputs, ... }:
let
  overlays = [
    inputs.devin.overlays.default
    (final: _: {
      neovim = final.callPackage ../pkgs/neovim {
        neovimPackage = inputs.neovim-nightly.packages.${final.stdenv.hostPlatform.system}.neovim;
      };
      direnv-instant =
        inputs.direnv-instant.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
          (old: {
            patches = (old.patches or [ ]) ++ [ ../pkgs/direnv-instant-mux-nvim.patch ];
          });
      mcp-gdrive = final.callPackage ../pkgs/mcp-gdrive { };
      barrett-berkeley-mono = final.callPackage ../pkgs/berkeley-mono.nix {
        src = inputs.font-berkeley-mono;
      };
    })
  ];

  sharedUnfree = [
    "apple_cursor"
    "barrett-berkeley-mono"
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
          barrett-berkeley-mono
          direnv-instant
          mcp-gdrive
          neovim
          ;
      };
    };
}
