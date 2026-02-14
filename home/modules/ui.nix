{
  pkgs,
  lib,
  config,
  hostConfig,
  ...
}:

let
  c = config.colors;

  mkWaybarTheme = palette: ''
    * { color: ${palette.fg}; }
    window#waybar { background: ${palette.bg}; }
    #workspaces button { color: ${palette.fgAlt}; background: transparent; }
    #workspaces button.active { color: ${palette.fg}; box-shadow: inset 0 -2px ${palette.accent}; }
    #window { color: ${palette.fgAlt}; }
    #pulseaudio.muted { color: ${palette.fgAlt}; }
    #network.disconnected { color: ${palette.fgAlt}; }
    #battery.charging { color: ${palette.green}; }
    #battery.lo, #battery.ultralo { color: ${palette.red}; }
    #idle_inhibitor.activated { color: ${palette.accent}; }
    #language { color: ${palette.fgAlt}; }
    tooltip { background: ${palette.bgAlt}; color: ${palette.fg}; border: 1px solid ${palette.border}; }
    tooltip * { color: ${palette.fg}; }
  '';
in
{
  home.sessionVariables = {
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
  };

  dconf = {
    enable = true;
    settings."org/gnome/desktop/interface" = {
      font-name = "SF Pro Display 11";
      document-font-name = "SF Pro Display 11";
      monospace-font-name = "Berkeley Mono 11";
    };
  };

  home.packages = with pkgs; [
    nerd-fonts.symbols-only
    rofi
    wl-clipboard
    cliphist
    grim
    slurp
    libnotify
    brightnessctl
    pamixer
    socat
    glib.bin
    gsettings-desktop-schemas
    (python3.withPackages (ps: [ ps.pillow ]))
  ];

  programs.waybar = {
    enable = true;
    settings.mainBar = {
      reload_style_on_change = true;
      layer = "top";
      position = "bottom";
      exclusive = true;
      height = 38;

      modules-left = [ "hyprland/workspaces" "hyprland/language" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [
        "idle_inhibitor"
        "privacy"
        "tray"
        "pulseaudio"
        "network"
        "battery"
        "clock"
      ];

      "hyprland/workspaces" = {
        format = "{id}";
        disable-scroll = true;
        all-outputs = true;
      };

      "hyprland/language" = {
        format = "{}";
        format-en = "en";
        format-en-colemak = "cmk";
      };

      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "󰅶";
          deactivated = "󰛊";
        };
        tooltip-format-activated = "idle inhibitor on";
        tooltip-format-deactivated = "idle inhibitor off";
      };

      privacy = {
        icon-size = 14;
        icon-spacing = 6;
      };

      tray = {
        icon-size = 16;
        spacing = 8;
      };

      "hyprland/window" = {
        format = "{}";
        separate-outputs = true;
        max-length = 60;
        rewrite = { };
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 muted";
        format-icons = {
          default = [ "󰕿" "󰖀" "󰕾" ];
        };
        signal = 1;
        tooltip-format = "{desc}";
      };

      network = {
        format-wifi = "󰤨 {essid}";
        format-ethernet = "󰈀 {ifname}";
        format-disconnected = "󰤭 off";
        format-disabled = "󰤭 off";
        interval = 10;
        tooltip-format-wifi = "{signalStrength}% · {ipaddr}";
        tooltip-format-ethernet = "{ipaddr}/{cidr}";
      };

      battery = {
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-full = "󰁹 {capacity}%";
        format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
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
      };

      clock = {
        format = "{:%a %d %b  %H:%M:%S}";
        interval = 1;
        tooltip-format = "{:%A, %d %B %Y\nTimezone: %Z}";
      };
    };

    style = ''
      @import url("${config.xdg.configHome}/waybar/themes/theme.css");

      * {
        font-family: "Symbols Nerd Font", "SF Pro Display", sans-serif;
        font-size: 14px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      #workspaces button {
        padding: 0 6px;
        min-width: 24px;
      }

      #language {
        padding: 0 8px;
      }

      #idle_inhibitor,
      #privacy,
      #tray,
      #pulseaudio,
      #network,
      #battery {
        padding: 0 12px;
      }

      #clock {
        padding: 0 14px 0 12px;
      }

      #window {
        padding: 0 16px;
      }

      tooltip {
        border-radius: 4px;
      }
    '';
  };

  xdg.configFile."rofi/config.rasi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/rofi/config.rasi";
  xdg.configFile."rofi/themes/midnight.rasi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/rofi/themes/midnight.rasi";
  xdg.configFile."rofi/themes/daylight.rasi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/rofi/themes/daylight.rasi";

  services.dunst = {
    enable = true;
    settings = {
      global = {
        font = "SF Pro Display 15";
        frame_color = c.fgAlt;
        separator_color = "frame";
        background = c.bg;
        foreground = c.fg;
      };
      urgency_low = {
        background = c.bg;
        foreground = c.blue;
        frame_color = c.blue;
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

}
