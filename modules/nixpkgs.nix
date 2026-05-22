{ lib, inputs, ... }:
let
  overlays = [
    inputs.codex.overlays.default
    (final: prev: {
      delta-cli = inputs.delta.packages.${final.system}.cli;
      google-workspace-cli = inputs.googleworkspace-cli.packages.${final.system}.default;
      google-workspace-guard = final.callPackage ../pkgs/google-workspace-guard {
        gws = final.google-workspace-cli;
      };
    })
    (final: prev: {
      tmuxPlugins = prev.tmuxPlugins // {
        mosaic = inputs.tmux-mosaic.packages.${final.system}.default;
      };
    })
  ];

  sharedUnfree = [
    "slack"
    "apple_cursor"
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
