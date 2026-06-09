{
  pkgs,
  lib,
  palettes,
  themeGenerators,
  hostConfig,
  ...
}:
let
  wayland = import ../wayland.nix { inherit pkgs hostConfig; };
  helpers = import ../helpers.nix { inherit hostConfig; };
  inherit (wayland)
    hyprSessionEnv
    mkWaylandGate
    wrapWaylandExec
    ;
  inherit (helpers)
    username
    homeDirectory
    XDG_CONFIG_HOME
    XDG_STATE_HOME
    repo
    mkSymlink
    mkDir
    readTheme
    ;

  waylandGate = mkWaylandGate "hyprland-session.target";

  hyprThemes = pkgs.runCommand "hypr-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.conf << 'HYPRMIDNIGHT'
    ${themeGenerators.mkHyprTheme palettes.midnight}
    HYPRMIDNIGHT

    cat > $out/daylight.conf << 'HYPRDAYLIGHT'
    ${themeGenerators.mkHyprTheme palettes.daylight}
    HYPRDAYLIGHT
  '';

  hyprlandConf = pkgs.writeText "hyprland-wrapper" ''
    env = XCURSOR_SIZE,24
    env = HYPRCURSOR_SIZE,24
    env = HYPRCURSOR_THEME,macOS
    env = GSK_RENDERER,ngl
    decoration {
      screen_shader = ${XDG_STATE_HOME}/hypr/screen-shader.frag
    }
    exec-once = ${hyprSessionEnv}/bin/hypr-session-env import
    source = ${repo}/config/hypr/hyprland.conf
  '';

  hyprpaperConf = pkgs.writeText "hyprpaper-conf" ''
    splash = 0

    wallpaper {
      monitor =
      path = ${homeDirectory}/Pictures/Screensavers/wallpaper.jpg
    }
  '';

  hyprlockConf = pkgs.writeText "hyprlock-conf" ''
    general {
      hide_cursor = true
      grace = 0
    }

    background {
      monitor =
      path = ${homeDirectory}/Pictures/Screensavers/lock.jpg
    }

    animations {
      enabled = false
    }

    input-field {
      monitor =
      size = 600, 50
      outline_thickness = 0
      dots_text_format = *
      dots_size = 0.9
      dots_spacing = 0.3
      dots_center = true
      outer_color = rgba(00000000)
      inner_color = rgba(00000000)
      font_color = rgb(ffffff)
      font_family = Berkeley Mono
      check_color = rgb(98c379)
      fail_color = rgb(ff6b6b)
      fail_text = $FAIL
      rounding = 0
      placeholder_text =
      position = 0, 0
      halign = center
      valign = center
    }
  '';

  hypridleLockCmd = pkgs.writeShellScriptBin "hypridle-lock" ''
    set -e
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.hyprland
        pkgs.jq
        pkgs.nix
      ]
    }
    ${repo}/scripts/ctl wallpaper lock
    exec ${pkgs.hyprlock}/bin/hyprlock
  '';

  hypridleConf = pkgs.writeText "hypridle-conf" ''
    general {
      lock_cmd = ${hypridleLockCmd}/bin/hypridle-lock
      after_sleep_cmd = ${pkgs.hyprland}/bin/hyprctl dispatch dpms on
    }

    listener {
      timeout = 300
      on-timeout = ${pkgs.systemd}/bin/loginctl lock-session
    }

    listener {
      timeout = 600
      on-timeout = ${pkgs.hyprland}/bin/hyprctl dispatch dpms off
      on-resume = ${pkgs.hyprland}/bin/hyprctl dispatch dpms on
    }

    listener {
      timeout = 3600
      on-timeout = ${pkgs.systemd}/bin/systemctl suspend
    }
  '';

  hypridleStart = pkgs.writeShellScript "hypridle-start" ''
    set -eu

    if [ "$(${repo}/scripts/ctl idle state)" = off ]; then
      exit 0
    fi

    exec ${wrapWaylandExec "${pkgs.hypridle}/bin/hypridle"}
  '';
in
{
  config = lib.mkIf hostConfig.enableWayland {
    users.users.${username}.packages = with pkgs; [
      hyprlock
      hyprpaper
      hypridle
      hyprland
      xdg-desktop-portal-hyprland
    ];

    systemd.user.services.hyprpaper = waylandGate // {
      description = "Hyprpaper wallpaper daemon";
      serviceConfig = waylandGate.serviceConfig // {
        ExecStart = wrapWaylandExec "${pkgs.hyprpaper}/bin/hyprpaper";
      };
    };

    systemd.user.services.hypridle = waylandGate // {
      description = "Hypridle idle daemon";
      serviceConfig = waylandGate.serviceConfig // {
        ExecStart = "${hypridleStart}";
      };
    };

    system.activationScripts.hyprlandConfig.text = ''
      ${mkDir "${XDG_CONFIG_HOME}/hypr/themes"}
      ${mkDir "${XDG_STATE_HOME}/hypr"}
      ${mkDir "${homeDirectory}/Pictures/Screensavers"}

      ${mkSymlink "${hyprThemes}/midnight.conf" "${XDG_CONFIG_HOME}/hypr/themes/midnight.conf"}
      ${mkSymlink "${hyprThemes}/daylight.conf" "${XDG_CONFIG_HOME}/hypr/themes/daylight.conf"}
      ${mkSymlink "${hyprlandConf}" "${XDG_CONFIG_HOME}/hypr/hyprland.conf"}
      ${mkSymlink "${hyprpaperConf}" "${XDG_CONFIG_HOME}/hypr/hyprpaper.conf"}
      ${mkSymlink "${hypridleConf}" "${XDG_CONFIG_HOME}/hypr/hypridle.conf"}
      ${mkSymlink "${hyprlockConf}" "${XDG_CONFIG_HOME}/hypr/hyprlock.conf"}

      src="${repo}/config/screen"
      dest="${homeDirectory}/Pictures/Screensavers"
      if [ -d "$src" ]; then
        for f in "$src"/*; do
          [ -f "$f" ] || continue
          name=$(basename "$f")
          [ -L "$dest/$name" ] || ln -sf "$f" "$dest/$name"
        done
        chown -h ${username}:users "$dest"/* 2>/dev/null || true
      fi

      ${readTheme}
      ${mkSymlink "${XDG_CONFIG_HOME}/hypr/themes/$theme.conf" "${XDG_CONFIG_HOME}/hypr/themes/theme.conf"}

      grayscale="$(cat "${XDG_STATE_HOME}/hypr/grayscale" 2>/dev/null)" || grayscale="off"
      case "$grayscale" in
        on) screen_shader="${repo}/config/hypr/shaders/grayscale.frag" ;;
        *) screen_shader="${repo}/config/hypr/shaders/pass-through.frag" ;;
      esac
      ln -sfnT "$screen_shader" "${XDG_STATE_HOME}/hypr/screen-shader.frag"
      chown -h ${username}:users "${XDG_STATE_HOME}/hypr/screen-shader.frag"

      wp_themed="${homeDirectory}/Pictures/Screensavers/wallpaper-$theme.jpg"
      wp_link="${homeDirectory}/Pictures/Screensavers/wallpaper.jpg"
      [ -f "$wp_themed" ] && {
        ln -sf "$wp_themed" "$wp_link"
        chown -h ${username}:users "$wp_link"
      }
    '';
  };
}
