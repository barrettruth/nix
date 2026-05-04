{ lib, inputs, ... }:
let
  overlays = [
    inputs.claude-code.overlays.default
    inputs.codex.overlays.default
    inputs.devin-cli-overlay.overlays.default
    (final: prev: {
      tmux = prev.tmux.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../pkgs/tmux-copy-mode-line-numbers.patch
        ];
      });

      tmuxPlugins = prev.tmuxPlugins // {
        mosaic = inputs.tmux-mosaic.packages.${final.system}.default;
      };
    })
  ];

  sharedUnfree = [
    "slack"
    "apple_cursor"
    "claude-code"
    "claude"
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
