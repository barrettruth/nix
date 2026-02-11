{
  pkgs,
  lib,
  config,
  ...
}:

let
  isNixOS = builtins.pathExists /etc/NIXOS;
  c = config.colors;

  nvidia = true;
  backlightDevice = "intel_backlight";

  mkWaybarTheme = palette: ''
    * { color: ${palette.fg}; }
    #waybar { background: ${palette.bg}; }
    #workspaces button { color: ${palette.fg}; }
    #workspaces button.focused,
    #workspaces button.active { background: ${palette.bgAlt}; color: ${palette.fg}; }
    tooltip { color: ${palette.fg}; background-color: ${palette.bgAlt}; }
    tooltip * { color: ${palette.fg}; }
  '';
in
{
  home.sessionVariables = {
    XINITRC = "${config.xdg.configHome}/X11/xinitrc";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
  };

  home.packages = with pkgs; [
    wl-clipboard
    cliphist
    grim
    slurp
    libnotify
    brightnessctl
    pamixer
    socat
    (python3.withPackages (ps: [ ps.pillow ]))
    xinit
    xmodmap
    xrdb
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    portalPackage = lib.mkIf (!isNixOS) null;
    systemd.enable = isNixOS;

    extraConfig = ''
      exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland THEME
      exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland THEME

      monitor=,preferred,auto,1

      env = XDG_CURRENT_DESKTOP,Hyprland
      env = XDG_SESSION_TYPE,wayland
      env = ELECTRON_OZONE_PLATFORM_HINT,wayland
      env = GTK_USE_PORTAL,1
      env = OZONE_PLATFORM,wayland
      env = QT_QPA_PLATFORM,wayland
      env = GDK_BACKEND,wayland,x11
      env = SDL_VIDEODRIVER,wayland
    ''
    + lib.optionalString nvidia ''
      env = LIBVA_DRIVER_NAME,nvidia
      env = __GLX_VENDOR_LIBRARY_NAME,nvidia
      env = NVD_BACKEND,direct
      env = GBM_BACKEND,nvidia-drm
      env = GSK_RENDERER,ngl
      env = __NV_PRIME_RENDER_OFFLOAD,1
      env = __VK_LAYER_NV_optimus,NVIDIA_only
    ''
    + ''

      env = XCURSOR_SIZE,24
      env = HYPRCURSOR_SIZE,24
    ''
    + lib.optionalString nvidia ''
      cursor {
          no_hardware_cursors = true
      }
    ''
    + ''

      general {
          gaps_in = 0
          gaps_out = 0
          border_size = 5
          col.active_border = rgb(${builtins.substring 1 6 c.fg})
          col.inactive_border = rgb(${builtins.substring 1 6 c.bg})
          layout = master
          resize_on_border = true
      }

      master {
          new_status = slave
          new_on_top = false
          mfact = 0.50
      }

      decoration {
          rounding = 0
          active_opacity = 1.0
          inactive_opacity = 1.0
          blur {
              enabled = false
          }
      }

      animations {
          enabled = false
      }

      input {
          kb_layout = us,us
          kb_variant = ,colemak
          follow_mouse = 1
          sensitivity = 0
          touchpad {
              tap-to-click = false
          }
          repeat_delay = 300
          repeat_rate = 50
      }

      exec-once = dunst
      exec-once = wl-paste --watch cliphist store
      exec-once = hyprpaper
      exec-once = hypridle
      exec-once = hypr spawnfocus --ws 1 $TERMINAL -e mux
      exec-once = hypr spawnfocus --ws 2 $BROWSER

      bindul = , XF86AudioRaiseVolume, exec, hypr volume up
      bindul = , XF86AudioLowerVolume, exec, hypr volume down
      bindul = , XF86AudioMute, exec, hypr volume toggle

      bindul = , XF86MonBrightnessUp, exec, hypr brightness up
      bindul = , XF86MonBrightnessDown, exec, hypr brightness down

      bindu = ALT, SPACE, exec, rofi -show run
      bindu = ALT, TAB, workspace, previous
      bindu = ALT, A, cyclenext
      bindu = ALT, B, exec, pkill -USR1 waybar || waybar
      bindu = ALT, D, layoutmsg, swapprev
      bindu = ALT, F, cyclenext, prev
      bindu = ALT, H, resizeactive, -15 0
      bindu = ALT, J, resizeactive, 0 15
      bindu = ALT, K, resizeactive, 0 -15
      bindu = ALT, L, resizeactive, 15 0
      bindu = ALT, Q, killactive,
      bindu = ALT, U, layoutmsg, swapnext

      bindu = ALT CTRL, B, exec, hypr pull bitwarden-desktop
      bindu = ALT CTRL, C, exec, hypr pull $BROWSER
      bindu = ALT CTRL, D, exec, hypr pull discord
      bindu = ALT CTRL, S, exec, hypr pull signal-desktop
      bindu = ALT CTRL, T, exec, hypr pull Telegram
      bindu = ALT CTRL, V, exec, hypr pull vesktop
      bindu = ALT CTRL, Y, exec, hypr pull sioyek

      bindu = ALT SHIFT, RETURN, exec, hypr spawnfocus --ws 1 $TERMINAL
      bindu = ALT SHIFT, B, exec, hypr spawnfocus --ws 9 bitwarden-desktop
      bindu = ALT SHIFT, C, exec, hypr spawnfocus --ws 2 $BROWSER --ozone-platform=wayland
      bindu = ALT SHIFT, D, exec, hypr spawnfocus --ws 5 discord
      bindu = ALT SHIFT, F, togglefloating
      bindu = ALT SHIFT, G, exec, hypr pull $TERMINAL
      bindu = ALT SHIFT, Q, exec, hypr exit
      bindu = ALT SHIFT, R, exec, hyprctl reload && notify-send -u low 'hyprland reloaded'
      bindu = ALT SHIFT, S, exec, hypr spawnfocus --ws 6 signal-desktop
      bindu = ALT SHIFT, T, exec, hypr spawnfocus --ws 6 Telegram
      bindu = ALT SHIFT, V, exec, hypr spawnfocus --ws 5 vesktop
      bindu = ALT SHIFT, Y, exec, hypr spawnfocus --ws 3 sioyek

      bind = , XF86Tools, submap, scripts
      submap = scripts

      bind = , A, exec, ctl audio out
      bind = , C, exec, bash -lc 'cliphist list | rofi -dmenu -p "copy to clipboard" --lines 15 | cliphist decode | wl-copy'
      bind = , F, exec, [float; fullscreen] ghostty -e lf
      bind = , K, exec, ctl keyboard toggle
      bind = , O, exec, ctl ocr
      bind = , P, exec, hypr pull
      bind = , S, exec, ctl screenshot
      bind = , T, exec, theme

      bind = , catchall, submap, reset
      submap = reset

      misc {
          force_default_wallpaper = 0
          disable_hyprland_logo = true
      }

      bindu = ALT, 1, workspace, 1
      bindu = ALT, 2, workspace, 2
      bindu = ALT, 3, workspace, 3
      bindu = ALT, 4, workspace, 4
      bindu = ALT, 5, workspace, 5
      bindu = ALT, 6, workspace, 6
      bindu = ALT, 7, workspace, 7
      bindu = ALT, 8, workspace, 8
      bindu = ALT, 9, workspace, 9

      bindu = ALT SHIFT, 1, movetoworkspace, 1
      bindu = ALT SHIFT, 2, movetoworkspace, 2
      bindu = ALT SHIFT, 3, movetoworkspace, 3
      bindu = ALT SHIFT, 4, movetoworkspace, 4
      bindu = ALT SHIFT, 5, movetoworkspace, 5
      bindu = ALT SHIFT, 6, movetoworkspace, 6
      bindu = ALT SHIFT, 7, movetoworkspace, 7
      bindu = ALT SHIFT, 8, movetoworkspace, 8
      bindu = ALT SHIFT, 9, movetoworkspace, 9

      bindu = ALT CTRL, 1, movetoworkspacesilent, 1
      bindu = ALT CTRL, 2, movetoworkspacesilent, 2
      bindu = ALT CTRL, 3, movetoworkspacesilent, 3
      bindu = ALT CTRL, 4, movetoworkspacesilent, 4
      bindu = ALT CTRL, 5, movetoworkspacesilent, 5
      bindu = ALT CTRL, 6, movetoworkspacesilent, 6
      bindu = ALT CTRL, 7, movetoworkspacesilent, 7
      bindu = ALT CTRL, 8, movetoworkspacesilent, 8
      bindu = ALT CTRL, 9, movetoworkspacesilent, 9

      workspace = w[tv1], gapsout:0, gapsin:0
      workspace = f[1], gapsout:0, gapsin:0
      windowrule = match:float 0, match:workspace w[tv1], border_size 0
      windowrule = match:float 0, match:workspace w[tv1], rounding 0
      windowrule = match:float 0, match:workspace f[1],   border_size 0
      windowrule = match:float 0, match:workspace f[1],   rounding 0

      windowrule = match:class ^(xdg-desktop-portal-gtk)$, float on
      windowrule = match:class ^(xdg-desktop-portal-gtk)$, size monitor_w * 0.5 monitor_h * 0.6
      windowrule = match:class ^(xdg-desktop-portal-kde)$, float on
      windowrule = match:class ^(xdg-desktop-portal-kde)$, size monitor_w * 0.5 monitor_h * 0.6
      windowrule = match:class ^(xdg-desktop-portal-hyprland)$, float on
      windowrule = match:class ^(xdg-desktop-portal-hyprland)$, size monitor_w * 0.5 monitor_h * 0.6
    '';
  };

  services.hypridle = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    settings = {
      general = {
        lock_cmd = "wp lock && hyprlock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "wp lock && hyprlock";
        }
        {
          timeout = 600;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1800;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

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

  services.hyprpaper = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    settings = {
      wallpaper = [ ",~/img/screen/wallpaper.jpg" ];
      splash = false;
    };
  };

  programs.waybar = {
    enable = true;
    settings.mainBar = {
      reload_style_on_change = true;
      layer = "top";
      position = "bottom";
      exclusive = true;
      height = 34;

      modules-left = [
        "hyprland/workspaces"
        "hyprland/window"
      ];
      modules-center = [ ];
      modules-right = [
        "backlight"
        "pulseaudio"
        "network"
        "battery"
        "clock"
      ];

      "hyprland/workspaces" = {
        disable-scroll = true;
        all-outputs = true;
        format = "{icon}";
        format-icons = {
          "1" = "i";
          "2" = "ii";
          "3" = "iii";
          "4" = "iv";
          "5" = "v";
          "6" = "vi";
          "7" = "vii";
          "8" = "viii";
          "9" = "ix";
        };
      };

      "hyprland/window" = {
        format = " {} [{}]";
        separate-outputs = true;
        max-length = 80;
        rewrite = { };
      };

      pulseaudio = {
        format = "volume:{volume}% │ ";
        format-muted = "volume:{volume}% (muted) │ ";
        interval = 2;
        signal = 1;
        tooltip-format = "Audio Output: {desc}";
      };

      network = {
        format-wifi = "wifi:{essid} │ ";
        format-ethernet = "eth:{interface} │ ";
        format-disconnected = "wifi:off │ ";
        format-disabled = "network:disabled";
        interval = 10;
        signal = 1;
        tooltip-format-wifi = "Signal: {signalStrength}%\nIP: {ipaddr}/{cidr}";
        tooltip-format-ethernet = "IP: {ipaddr}/{cidr}\nGateway: {gwaddr}";
        tooltip-format-disconnected = "Network: disconnected";
      };

      backlight = {
        device = backlightDevice;
        format = "brightness:{percent}% │ ";
        signal = 1;
        tooltip = false;
      };

      battery = {
        format = "battery:-{capacity}% │ ";
        format-charging = "battery:+{capacity}% │ ";
        format-full = "battery:{capacity}% │ ";
        states = {
          hi = 30;
          mid = 20;
          lo = 10;
          ultralo = 5;
        };
        events = {
          on-discharging-hi = "notify-send -u low 'battery 30%'";
          on-discharging-mid = "notify-send -u normal 'battery 20%'";
          on-discharging-lo = "notify-send -u critical 'battery 10%'";
          on-discharging-ultralo = "notify-send -u critical 'battery 5%'";
          on-charging-100 = "notify-send -u low 'battery 100%'";
        };
        interval = 30;
        signal = 1;
      };

      clock = {
        format = "{:%H:%M:%S %d/%m/%Y} ";
        interval = 1;
        tooltip-format = "{:%A, %d %B %Y\nTimezone: %Z}";
      };
    };

    style = ''
      @import url("${config.xdg.configHome}/waybar/themes/theme.css");

      * {
        font-family: "Berkeley Mono", monospace;
        font-size: 15px;
      }

      button {
        border: none;
        border-radius: 0;
      }

      #workspaces button {
        padding: 0 10px;
      }

      tooltip {
        text-shadow: none;
      }

      tooltip * {
        text-shadow: none;
      }
    '';
  };

  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    font = "Berkeley Mono 15";
    extraConfig = {
      show-icons = false;
    };
    theme =
      let
        inherit (config.lib.formats.rasi) mkLiteral;
      in
      {
        "*" = {
          selected-normal-foreground = mkLiteral "${c.fg}";
          foreground = mkLiteral "${c.fg}";
          normal-foreground = mkLiteral "@foreground";
          alternate-normal-background = mkLiteral "${c.bg}";
          background = mkLiteral "${c.bgAlt}";
          alternate-normal-foreground = mkLiteral "@foreground";
          normal-background = mkLiteral "@background";
          selected-normal-background = mkLiteral "${c.accent}";
          border-color = mkLiteral "${c.fgAlt}";
          spacing = 2;
          separatorcolor = mkLiteral "@foreground";
          background-color = mkLiteral "rgba ( 0, 0, 0, 0 % )";
        };
        window = {
          background-color = mkLiteral "@background";
          border = 1;
          padding = 5;
        };
        mainbox = {
          border = 0;
          padding = 0;
        };
        listview = {
          fixed-height = 0;
          border = mkLiteral "2px 0px 0px";
          border-color = mkLiteral "@separatorcolor";
          spacing = mkLiteral "2px";
          scrollbar = false;
          padding = mkLiteral "2px 0px 0px";
        };
        element = {
          border = 0;
          padding = mkLiteral "1px";
        };
        element-text = {
          background-color = mkLiteral "inherit";
          text-color = mkLiteral "inherit";
        };
        "element.normal.normal" = {
          background-color = mkLiteral "@normal-background";
          text-color = mkLiteral "@normal-foreground";
        };
        "element.selected.normal" = {
          background-color = mkLiteral "@selected-normal-background";
          text-color = mkLiteral "@selected-normal-foreground";
        };
        "element.alternate.normal" = {
          background-color = mkLiteral "@alternate-normal-background";
          text-color = mkLiteral "@alternate-normal-foreground";
        };
        inputbar = {
          spacing = 0;
          text-color = mkLiteral "@normal-foreground";
          padding = mkLiteral "1px";
          children = map mkLiteral [
            "prompt"
            "textbox-prompt-colon"
            "entry"
            "case-indicator"
          ];
        };
        textbox-prompt-colon = {
          expand = false;
          str = ":";
          margin = mkLiteral "0px 0.3em 0em 0em";
          text-color = mkLiteral "@normal-foreground";
        };
      };
  };

  services.dunst = {
    enable = true;
    settings = {
      global = {
        font = "Berkeley Mono 15";
        frame_color = c.fgAlt;
        separator_color = "frame";
        background = c.bg;
        foreground = c.fg;
      };
      urgency_low = {
        background = c.bg;
        foreground = c.fg;
      };
      urgency_normal = {
        background = c.bg;
        foreground = c.fg;
      };
      urgency_critical = {
        background = c.bg;
        foreground = c.red;
        frame_color = c.red;
      };
      experimental = {
        per_monitor_dpi = true;
      };
    };
  };
  xdg.configFile."waybar/themes/midnight.css".text = mkWaybarTheme config.palettes.midnight;
  xdg.configFile."waybar/themes/daylight.css".text = mkWaybarTheme config.palettes.daylight;

  home.activation.linkWaybarTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="${config.xdg.configHome}/waybar/themes/theme.css"
    $DRY_RUN_CMD ln -sf "${config.xdg.configHome}/waybar/themes/${config.theme}.css" "$target"
  '';

  xdg.configFile."X11".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/X11";
}
