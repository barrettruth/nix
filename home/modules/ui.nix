{
  pkgs,
  lib,
  config,
  ...
}:

let
  c = config.colors;
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
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
  };

  dconf.enable = true;

  home.packages = with pkgs; [
    wl-clipboard
    cliphist
    grim
    slurp
    libnotify
    brightnessctl
    pamixer
    socat
    glib
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

}
