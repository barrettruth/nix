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

  home.packages = [ pkgs.rofi ];

  xdg.configFile."rofi/config.rasi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/rofi/config.rasi";
  xdg.configFile."rofi/themes/midnight.rasi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/rofi/themes/midnight.rasi";
  xdg.configFile."rofi/themes/daylight.rasi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/rofi/themes/daylight.rasi";

  home.activation.linkRofiTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="${config.xdg.configHome}/rofi/themes/theme.rasi"
    $DRY_RUN_CMD ln -sf "${config.xdg.configHome}/rofi/themes/${config.theme}.rasi" "$target"
  '';

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
