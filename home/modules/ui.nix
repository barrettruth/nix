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
    #workspaces button { background: transparent; }
    #workspaces button.active { box-shadow: inset 0 -2px ${palette.accent}; }
    #window { color: ${palette.fgAlt}; }
    tooltip { background: ${palette.bgAlt}; color: ${palette.fg}; border: 1px solid ${palette.border}; }
  '';

  hexToFuzzel = hex: "${builtins.substring 1 6 hex}ff";

  mkFuzzelTheme = palette: ''
    [colors]
    background=${hexToFuzzel palette.bg}
    text=${hexToFuzzel palette.fg}
    prompt=${hexToFuzzel palette.fgAlt}
    placeholder=${hexToFuzzel palette.fgAlt}
    input=${hexToFuzzel palette.fg}
    match=${hexToFuzzel palette.accent}
    selection=${hexToFuzzel palette.bgAlt}
    selection-text=${hexToFuzzel palette.fg}
    selection-match=${hexToFuzzel palette.accent}
    border=${hexToFuzzel palette.border}
    counter=${hexToFuzzel palette.fgAlt}
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
    psmisc
    fuzzel
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

      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [
        "hyprland/language"
        "privacy"
        "tray"
        "pulseaudio"
        "network"
        "battery"
        "clock"
        "custom/power"
      ];

      "hyprland/workspaces" = {
        format = "{id}";
        disable-scroll = true;
        all-outputs = true;
        tooltip = true;
      };

      "hyprland/language" = {
        format = " [{}]";
        format-en = "en";
        format-en-colemak = "cmk";
        tooltip-format = "{long}";
        on-click = "ctl keyboard toggle";
      };

      privacy = {
        icon-size = 14;
        icon-spacing = 6;
      };

      tray = {
        icon-size = 16;
        spacing = 8;
        tooltip = true;
        show-passive-items = true;
      };

      "hyprland/window" = {
        format = "{}";
        separate-outputs = true;
        rewrite = { };
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 muted";
        format-icons = {
          default = [
            "󰕿"
            "󰖀"
            "󰕾"
          ];
        };
        signal = 1;
        tooltip-format = "{desc}";
        on-click = "pamixer -t";
        on-scroll-up = "pamixer -i 5";
        on-scroll-down = "pamixer -d 5";
      };

      network = {
        format-wifi = "󰤨 {essid}";
        format-ethernet = "󰈀 {ifname}";
        format-disconnected = "󰤭 off";
        format-disabled = "󰤭 off";
        interval = 10;
        tooltip-format-wifi = "{signalStrength}% · {ipaddr}";
        tooltip-format-ethernet = "{ipaddr}/{cidr}";
        on-click = "ctl audio out";
      };

      battery = {
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-full = "󰁹 {capacity}%";
        format-icons = [
          "󰁺"
          "󰁻"
          "󰁼"
          "󰁽"
          "󰁾"
          "󰁿"
          "󰂀"
          "󰂁"
          "󰂂"
          "󰁹"
        ];
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
        tooltip = true;
        tooltip-format = "{capacity}% · {timeTo}";
      };

      clock = {
        format = "{:%a %d/%m/%Y  %H:%M:%S}";
        interval = 1;
        tooltip-format = "{:%A, %d %B %Y\nTimezone: %Z}";
      };

      "custom/power" = {
        format = "⏻";
        tooltip = true;
        tooltip-format = "power menu";
        on-click = "ctl power";
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
        font-family: "SF Pro Display", sans-serif;
        padding: 0 10px;
        min-width: 24px;
        background: transparent;
        box-shadow: none;
      }

      #workspaces button:hover {
        background: transparent;
        box-shadow: none;
      }

      #language,
      #privacy,
      #tray,
      #pulseaudio,
      #network,
      #battery,
      #clock,
      #custom-power {
        padding: 0 10px;
      }

      #window {
        padding: 0 16px;
      }

      tooltip {
        border-radius: 4px;
      }
    '';
  };

  services.dunst = {
    enable = true;
    settings = {
      global = {
        font = "SF Pro Display 13";
        width = "(0, 400)";
        height = "(0, 120)";
        origin = "top-right";
        offset = "16x16";
        padding = 16;
        horizontal_padding = 20;
        frame_width = 1;
        frame_color = c.border;
        separator_color = "frame";
        separator_height = 1;
        gap_size = 8;
        corner_radius = 0;
        background = c.bg;
        foreground = c.fg;
        alignment = "left";
        ellipsize = "end";
        icon_position = "left";
        max_icon_size = 32;
        format = "<b>%s</b>\\n%b";
      };
      urgency_low = {
        background = c.bg;
        foreground = c.fg;
        frame_color = c.border;
      };
      urgency_normal = {
        background = c.bg;
        foreground = c.fg;
        frame_color = c.border;
      };
      urgency_critical = {
        background = c.bg;
        foreground = c.red;
        frame_color = c.red;
      };
    };
  };
  xdg.configFile."waybar/themes/midnight.css".text = mkWaybarTheme config.palettes.midnight;
  xdg.configFile."waybar/themes/daylight.css".text = mkWaybarTheme config.palettes.daylight;

  xdg.configFile."fuzzel/fuzzel.ini".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/fuzzel/fuzzel.ini";
  xdg.configFile."fuzzel/themes/midnight.ini".text = mkFuzzelTheme config.palettes.midnight;
  xdg.configFile."fuzzel/themes/daylight.ini".text = mkFuzzelTheme config.palettes.daylight;

}
