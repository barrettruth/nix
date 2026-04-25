{ lib, inputs, ... }:
let
  overlays = [
    inputs.codex.overlays.default
    inputs.devin.overlays.default
    (final: prev: {
      tmuxPlugins = prev.tmuxPlugins // {
        mosaic = inputs.tmux-mosaic.packages.${final.system}.default;
      };
    })
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
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) sharedUnfree;
      };
    };
}
