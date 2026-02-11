{
  lib,
  ...
}:

let
  isNixOS = builtins.pathExists /etc/NIXOS;
in
{
  services.hyprpaper = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    settings = {
      wallpaper = [ ",~/img/screen/wallpaper.jpg" ];
      splash = false;
    };
  };
}
