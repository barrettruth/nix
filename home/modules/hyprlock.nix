{
  pkgs,
  config,
  isNixOS,
  ...
}:

{
  home.packages = [ pkgs.hyprlock ];

  xdg.configFile."hypr/hyprlock.conf".text = ''
    general {
      hide_cursor = true
      grace = 0
    }

    background {
      monitor =
      path = ${config.home.homeDirectory}/img/screen/lock.jpg
    }

    animations {
      enabled = false
    }
  '';
}
