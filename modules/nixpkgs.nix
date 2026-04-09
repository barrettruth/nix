{ lib, inputs, ... }:
let
  overlays = [
    inputs.claude-code.overlays.default
    inputs.codex.overlays.default
  ];

  sharedUnfree = [
    "slack"
    "claude-code"
    "claude"
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
