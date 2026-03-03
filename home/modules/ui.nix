{
  pkgs,
  lib,
  config,
  ...
}:

let
  mkWaybarTheme = palette: ''
    * { color: ${palette.fg}; }
    window#waybar { background: ${palette.bg}; border-bottom: 2px solid ${palette.bgAlt}; }
    #workspaces button { background: transparent; }
    #workspaces button.active { box-shadow: inset 0 2px ${palette.accent}; }
    #workspaces button:hover { background: ${palette.bgAlt}; }
    #window { color: ${palette.fgAlt}; }
    tooltip { background: ${palette.bgAlt}; color: ${palette.fg}; border: 1px solid ${palette.border}; }
  '';

  mkEwwTheme = palette: ''
    $bg: ${palette.bg};
    $fg: ${palette.fg};
    $bgAlt: ${palette.bgAlt};
    $fgAlt: ${palette.fgAlt};
    $border: ${palette.border};
    $accent: ${palette.accent};
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

  mkDunstTheme = palette: ''
    [global]
    frame_color = "${palette.border}"
    separator_color = "frame"
    background = "${palette.bg}"
    foreground = "${palette.fg}"

    [urgency_low]
    background = "${palette.bg}"
    foreground = "${palette.fg}"
    frame_color = "${palette.border}"

    [urgency_normal]
    background = "${palette.bg}"
    foreground = "${palette.fg}"
    frame_color = "${palette.border}"

    [urgency_critical]
    background = "${palette.bg}"
    foreground = "${palette.red}"
    frame_color = "${palette.red}"
  '';
in
{
  home.sessionVariables = lib.mkMerge [
    { QT_AUTO_SCREEN_SCALE_FACTOR = "1"; }
    (lib.mkIf config.gtk.enable {
      GTK_RC_FILES = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    })
  ];

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
    eww
    wl-clipboard
    grim
    slurp
    wf-recorder
    libnotify
    brightnessctl
    socat
    glib.bin
    gsettings-desktop-schemas
    (python3.withPackages (ps: [ ps.pillow ]))
  ];

  programs.waybar = {
    enable = true;
    systemd.enable = false;
    settings.mainBar = {
      reload_style_on_change = true;
      layer = "top";
      position = "top";
      exclusive = false;
      height = 38;

      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [
        "tray"
        "custom/keyboard"
        "privacy"
        "wireplumber#source"
        "wireplumber"
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
        on-click = "ctl keyboard pick";
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
        max-length = 40;
        separate-outputs = true;
        rewrite = { };
      };

      wireplumber = {
        format = "{icon}";
        format-muted = "󰖁";
        format-icons = [ "󰕿" "󰖀" "󰕾" ];
        node-type = "Audio/Sink";
        max-volume = 100;
        scroll-step = 5;
        on-click = "ctl audio sink";
        on-click-right = "eww open --toggle volume";
        on-click-middle = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        tooltip = true;
        tooltip-format = "{volume}%";
      };

      "wireplumber#source" = {
        format = "{icon}";
        format-muted = "󰍭";
        format-icons = [ "󰍬" ];
        node-type = "Audio/Source";
        max-volume = 100;
        scroll-step = 5;
        on-click = "ctl audio source";
        on-click-right = "eww open --toggle volume";
        on-click-middle = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
        tooltip = true;
        tooltip-format = "{volume}%";
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
        on-click = "ctl wifi pick";
      };

      battery = {
        format = "{icon}";
        format-charging = "{icon}";
        format-full = "{icon}";
        format-icons = [
          ""
          ""
          ""
          ""
          ""
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
        tooltip-format-discharging = "Discharging: {capacity}%\n{timeTo}";
        tooltip-format-charging = "Charging: {capacity}%\n{timeTo}";
        tooltip-format-full = "Full: {capacity}%";
        tooltip-format = "{capacity}%\n{timeTo}";
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
      #wireplumber,
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

  services.cliphist.enable = true;

  services.dunst = {
    enable = true;
    settings = {
      global = {
        font = "SF Pro Display 13";
        width = "(0, 400)";
        height = "(0, 120)";
        origin = "top-right";
        offset = "(16, 16)";
        padding = 10;
        horizontal_padding = 10;
        frame_width = 3;
        separator_height = 1;
        gap_size = 8;
        corner_radius = 0;
        alignment = "left";
        ellipsize = "end";
        icon_position = "left";
        max_icon_size = 32;
      };
      ctl = {
        appname = "ctl";
        icon_position = "off";
        format = "%s";
      };
    };
  };
  xdg.configFile."dunst/themes/midnight.conf".text = mkDunstTheme config.palettes.midnight;
  xdg.configFile."dunst/themes/daylight.conf".text = mkDunstTheme config.palettes.daylight;
  xdg.configFile."waybar/themes/midnight.css".text = mkWaybarTheme config.palettes.midnight;
  xdg.configFile."waybar/themes/daylight.css".text = mkWaybarTheme config.palettes.daylight;

  xdg.configFile."eww/scripts/audio" = {
    executable = true;
    text = ''
      #!/bin/sh
      emit() {
        sink=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
        source=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
        sv=$(echo "$sink" | awk '{printf "%d", $2 * 100}')
        sm=$(echo "$sink" | grep -q MUTED && echo true || echo false)
        iv=$(echo "$source" | awk '{printf "%d", $2 * 100}')
        im=$(echo "$source" | grep -q MUTED && echo true || echo false)
        printf '{"sv":%d,"sm":%s,"iv":%d,"im":%s}\n' "$sv" "$sm" "$iv" "$im"
      }
      emit
      pactl subscribe 2>/dev/null | while read -r line; do
        case "$line" in
          *"change"*"sink"*|*"change"*"source"*|*"change"*"server"*) emit ;;
        esac
      done
    '';
  };

  xdg.configFile."eww/eww.yuck".text = ''
    (deflisten audio :initial '{"sv":0,"sm":false,"iv":0,"im":false}' "''${EWW_CONFIG_DIR}/scripts/audio")

    (defwidget volume-popup []
      (box :class "volume-popup" :orientation "v" :space-evenly false :spacing 12
        (box :class "slider-row" :orientation "h" :space-evenly false :spacing 8
          (button :class "mute-btn" :onclick "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
            (label :text {audio.sm ? "󰖁" : audio.sv <= 33 ? "󰕿" : audio.sv <= 66 ? "󰖀" : "󰕾"}))
          (scale :class "vol-slider" :value {audio.sv} :min 0 :max 100 :orientation "h"
            :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%"))
        (box :class "slider-row" :orientation "h" :space-evenly false :spacing 8
          (button :class "mute-btn" :onclick "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
            (label :text {audio.im ? "󰍭" : "󰍬"}))
          (scale :class "vol-slider" :value {audio.iv} :min 0 :max 100 :orientation "h"
            :onchange "wpctl set-volume @DEFAULT_AUDIO_SOURCE@ {}%"))))

    (defwindow volume
      :monitor 0
      :geometry (geometry :x "-16px" :y "8px" :width "280px" :anchor "top right")
      :stacking "overlay"
      :exclusive false
      :focusable false
      (volume-popup))
  '';

  xdg.configFile."eww/eww.scss".text = ''
    @import "themes/theme";

    .volume-popup {
      background: $bg;
      border: 2px solid $border;
      padding: 16px;
    }

    .slider-row {
      padding: 4px 0;
    }

    .mute-btn {
      background: transparent;
      color: $fg;
      font-size: 18px;
      min-width: 28px;
      min-height: 28px;
      padding: 0;
      border: none;
      &:hover { color: $accent; }
    }

    .vol-slider {
      min-width: 200px;
      min-height: 8px;

      trough {
        background: $bgAlt;
        min-height: 4px;
        border-radius: 2px;
      }

      highlight {
        background: $accent;
        border-radius: 2px;
      }

      slider {
        background: $fg;
        min-width: 12px;
        min-height: 12px;
        border-radius: 6px;
        margin: -4px 0;
      }
    }
  '';

  xdg.configFile."eww/themes/midnight.scss".text = mkEwwTheme config.palettes.midnight;
  xdg.configFile."eww/themes/daylight.scss".text = mkEwwTheme config.palettes.daylight;

  xdg.configFile."fuzzel/fuzzel.ini".text = ''
    include=${config.xdg.configHome}/fuzzel/themes/theme.ini

    [main]
    font=SF Pro Display:size=12,Symbols Nerd Font:size=12
    prompt=""
    width=50
    lines=10
    horizontal-pad=24
    vertical-pad=20
    inner-pad=12
    line-height=24
    letter-spacing=0
    icons-enabled=yes
    icon-theme=Papirus
    image-size-ratio=0.5
    layer=overlay
    anchor=center
    match-mode=fzf
    dpi-aware=auto
    hide-before-typing=no
    match-counter=no

    [border]
    width=2
    radius=0
    selection-radius=0

    [dmenu]
    mode=text
    exit-immediately-if-empty=no

    [key-bindings]
    custom-1=Control+r
  '';
  xdg.configFile."fuzzel/themes/midnight.ini".text = mkFuzzelTheme config.palettes.midnight;
  xdg.configFile."fuzzel/themes/daylight.ini".text = mkFuzzelTheme config.palettes.daylight;

  systemd.user.services.waybar = lib.mkIf config.programs.waybar.enable {
    Unit.Description = lib.mkForce "Waybar (masked)";
    Install.WantedBy = lib.mkForce [ ];
  };
}
