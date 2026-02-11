{
  pkgs,
  lib,
  ...
}:

let
  isNixOS = builtins.pathExists /etc/NIXOS;
in
{
  home.packages = lib.mkIf isNixOS [ pkgs.hyprpaper ];

  services.hyprpaper = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    settings = {
      preload = [ "~/img/screen/wallpaper.jpg" ];
      wallpaper = [ ",~/img/screen/wallpaper.jpg" ];
      splash = false;
    };
  };
}
