{
  pkgs,
  lib,
  config,
  isNixOS,
  ...
}:

{
  home.packages = lib.mkIf isNixOS [ pkgs.hyprpaper ];

  xdg.configFile."hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor =
      path = ${config.home.homeDirectory}/img/screen/wallpaper.jpg
    }

    splash = false
  '';
}
