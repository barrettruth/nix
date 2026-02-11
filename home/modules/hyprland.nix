{
  pkgs,
  lib,
  config,
  isNixOS,
  ...
}:

let
  mkHyprTheme = palette: ''
    general {
        col.active_border = rgb(${builtins.substring 1 6 palette.fg})
        col.inactive_border = rgb(${builtins.substring 1 6 palette.bg})
    }
  '';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    portalPackage = lib.mkIf (!isNixOS) null;
    systemd.enable = isNixOS;

    extraConfig = ''
      source = $XDG_CONFIG_HOME/nix/config/hypr/hyprland.conf
    '';
  };

  home.packages =
    lib.optionals isNixOS [
      pkgs.xdg-desktop-portal-gtk
      pkgs.hyprpaper
    ]
    ++ [
      pkgs.hyprlock
      pkgs.hypridle
    ];

  xdg.configFile."hypr/themes/midnight.conf".text = mkHyprTheme config.palettes.midnight;
  xdg.configFile."hypr/themes/daylight.conf".text = mkHyprTheme config.palettes.daylight;

  xdg.configFile."hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor =
      path = ${config.home.homeDirectory}/img/screen/wallpaper.jpg
    }

    splash = false
  '';

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

  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
      lock_cmd = wp lock && hyprlock
      after_sleep_cmd = hyprctl dispatch dpms on
    }

    listener {
      timeout = 300
      on-timeout = wp lock && hyprlock
    }

    listener {
      timeout = 600
      on-timeout = hyprctl dispatch dpms off
      on-resume = hyprctl dispatch dpms on
    }

    listener {
      timeout = 1800
      on-timeout = systemctl suspend
    }
  '';
}
