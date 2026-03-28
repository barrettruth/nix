{ lib, inputs, ... }:
let
  overlays = [
    inputs.claude-code.overlays.default
    inputs.neovim-nightly.overlays.default
  ];

  sharedUnfree = [
    "slack"
    "claude-code"
    "claude"
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
