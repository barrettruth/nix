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
    window#waybar { background: ${palette.bg}; border-top: 4px solid ${palette.bgAlt}; }
    #workspaces button { background: transparent; }
    #workspaces button.active { box-shadow: inset 0 -2px ${palette.accent}; }
    #workspaces button:hover { background: ${palette.bgAlt}; }
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
    nerd-fonts.jetbrains-mono
    papirus-icon-theme
    psmisc
    fuzzel
    wl-clipboard
    cliphist
    grim
    slurp
    libnotify
    brightnessctl
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
        "tray"
        "custom/keyboard"
        "privacy"
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

      "custom/keyboard" = {
        exec = "hyprctl devices -j | jq -r '.keyboards[] | select(.main) | .active_keymap' 2>/dev/null || echo 'unknown'";
        interval = 1;
        format = "󰌌";
        tooltip = true;
        tooltip-format = "Layout: {}";
        on-click = "ctl keyboard next";
        on-click-right = "ctl keyboard pick";
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
        format = "{icon}";
        format-muted = "󰖁";
        format-icons = {
          default = [
            "󰕿"
            "󰖀"
            "󰕾"
          ];
        };
        signal = 1;
        tooltip = true;
        tooltip-format = "Volume: {volume}%\nOutput: {desc}";
        on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        on-click-right = "ctl audio out";
        on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ --limit 1.0";
        on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
      };

      network = {
        format-wifi = "󰖩";
        format-ethernet = "󰈀";
        format-disconnected = "󰖪";
        format-disabled = "󰖪";
        interval = 10;
        tooltip = true;
        tooltip-format-wifi = "SSID: {essid}\nSignal: {signalStrength}%\nDownload: {bandwidthDownBits}\nUpload: {bandwidthUpBits}\nIP: {ipaddr}";
        tooltip-format-ethernet = "Interface: {ifname}\nIP: {ipaddr}/{cidr}\nDownload: {bandwidthDownBits}\nUpload: {bandwidthUpBits}";
        tooltip-format-disconnected = "Wireless LAN disconnected";
        on-click = "rfkill toggle wlan";
        on-click-right = "ctl wifi pick";
      };

      battery = {
        format = "{icon}";
        format-charging = "{icon}";
        format-full = "{icon}";
        format-icons = ["" "" "" "" ""];
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
        tooltip-format = "Capacity: {capacity}%\n{timeTo}";
      };

      clock = {
        format = " {:%a %d/%m/%Y  %H:%M:%S}";
        interval = 1;
        tooltip = false;
      };

      "custom/power" = {
        format = "󰐥";
        tooltip = true;
        tooltip-format = "power menu";
        on-click = "ctl power";
      };
    };

    style = ''
      @import url("${config.xdg.configHome}/waybar/themes/theme.css");

      * {
        font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
        font-size: 14px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      #workspaces button {
        font-family: "SF Pro Display", sans-serif;
        padding: 0 7px;
        min-width: 20px;
        background: transparent;
        box-shadow: none;
        transition: none;
      }

      #workspaces button:hover {
        transition: none;
      }

      #custom-keyboard,
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
        border-radius: 0;
      }

      #custom-power {
        padding: 0 16px 0 10px;
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
        padding = 21;
        horizontal_padding = 25;
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
      ctl = {
        appname = "ctl";
        icon_position = "off";
        width = 300;
        height = 50;
        padding = 12;
        format = "%s";
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
