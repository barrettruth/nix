{
  pkgs,
  lib,
  config,
  hostConfig,
  ...
}:

let
  hex = color: builtins.substring 1 6 color;

  mkHyprTheme = palette: ''
    general {
        col.active_border = rgb(${hex palette.fg})
        col.inactive_border = rgb(${hex palette.bg})
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

  xdg.configFile."hypr/hyprlock.conf".text = let c = config.colors; in ''
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

    label {
      monitor =
      text = $TIME
      font_size = 64
      font_family = Berkeley Mono
      color = rgb(${hex c.fg})
      position = 0, 200
      halign = center
      valign = center
    }

    label {
      monitor =
      text = cmd[86400] date '+%A, %d %b'
      font_size = 20
      font_family = Berkeley Mono
      color = rgb(${hex c.fgAlt})
      position = 0, 120
      halign = center
      valign = center
    }

    input-field {
      monitor =
      size = 300, 50
      outline_thickness = 2
      dots_size = 0.25
      dots_spacing = 0.3
      dots_center = true
      outer_color = rgb(${hex c.border})
      inner_color = rgb(${hex c.bgAlt})
      font_color = rgb(${hex c.fg})
      font_family = Berkeley Mono
      fade_on_empty = true
      placeholder_text =
      position = 0, -20
      halign = center
      valign = center
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
