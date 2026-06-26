{ lib, ... }:
{
  imports = [
    ./ui.nix
    ./workstation.nix
  ];

  options.barrett.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "barrett";
    };
    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/barrett";
    };
  };
}
