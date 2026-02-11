{
  lib,
  ...
}:

let
  isNixOS = builtins.pathExists /etc/NIXOS;
in
{
  programs.hyprlock = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    settings = {
      general = {
        hide_cursor = true;
        grace = 0;
      };
      background = [
        {
          monitor = "";
          path = "~/img/screen/lock.jpg";
        }
      ];
      animations.enabled = false;
    };
  };
}
