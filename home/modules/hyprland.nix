{
  pkgs,
  lib,
  config,
  hostConfig,
  ...
}:

let
  mkHyprTheme = palette: ''
    general {
        col.active_border = rgb(${builtins.substring 1 6 palette.fg})
        col.inactive_border = rgb(${builtins.substring 1 6 palette.bg})
    }
  '';

  cursor = config.home.pointerCursor;

  cursorEnv = lib.optionalString (cursor != null) ''
    env = XCURSOR_SIZE,${toString cursor.size}
    env = HYPRCURSOR_SIZE,${toString cursor.size}
    env = HYPRCURSOR_THEME,${cursor.name}
  '';

  nvidiaEnv = lib.optionalString (hostConfig.gpu == "nvidia") ''
    env = LIBVA_DRIVER_NAME,nvidia
    env = __GLX_VENDOR_LIBRARY_NAME,nvidia
    env = NVD_BACKEND,direct
    env = GBM_BACKEND,nvidia-drm
    env = GSK_RENDERER,ngl
    env = __NV_PRIME_RENDER_OFFLOAD,1
    env = __VK_LAYER_NV_optimus,NVIDIA_only
  '';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = lib.mkIf (!hostConfig.isNixOS) null;
    portalPackage = lib.mkIf (!hostConfig.isNixOS) null;
    systemd.enable = hostConfig.isNixOS;

    extraConfig = ''
      ${cursorEnv}${nvidiaEnv}
      source = $XDG_CONFIG_HOME/nix/config/hypr/hyprland.conf
    '';
  };

  home.packages =
    lib.optionals hostConfig.isNixOS [
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
      path = ${config.xdg.userDirs.pictures}/Screensavers/wallpaper.jpg
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
      path = ${config.xdg.userDirs.pictures}/Screensavers/lock.jpg
    }

    animations {
      enabled = false
    }
  '';

  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
      lock_cmd = ctl wallpaper lock && hyprlock
      after_sleep_cmd = hyprctl dispatch dpms on
    }

    listener {
      timeout = 300
      on-timeout = ctl wallpaper lock && hyprlock
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
