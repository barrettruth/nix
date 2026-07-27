{ pkgs, ... }:
let
  hyprSessionEnv = pkgs.writeShellScriptBin "hypr-session-env" ''
    set -eu

    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.systemd
        pkgs.hyprland
        pkgs.dbus
      ]
    }

    active_session() {
      session="''${XDG_SESSION_ID:-}"
      if [ -n "$session" ]; then
        printf '%s\n' "$session"
        return 0
      fi

      user="''${USER:-$(id -un)}"
      session="$(loginctl show-user "$user" -p Display --value 2>/dev/null || true)"
      case "$session" in
        "" | "n/a") return 1 ;;
      esac

      printf '%s\n' "$session"
    }

    session_scope() {
      session="$1"
      scope="$(loginctl show-session "$session" -p Scope --value 2>/dev/null || true)"
      case "$scope" in
        "" | "n/a") return 1 ;;
      esac

      printf '%s\n' "$scope"
    }

    resolve_instance_once() {
      session="$(active_session || true)"
      scope=""
      if [ -n "$session" ]; then
        scope="$(session_scope "$session" || true)"
      fi

      lines="$(hyprctl instances -j 2>/dev/null | jq -r '.[] | [.pid, .instance, .wl_socket] | @tsv' 2>/dev/null || true)"
      [ -n "$lines" ] || return 1

      tmp="$(mktemp)"
      printf '%s\n' "$lines" >"$tmp"

      first=""
      count=0
      selected=""
      while IFS="$(printf '\t')" read -r pid instance socket; do
        [ -n "$pid" ] || continue
        count=$((count + 1))
        if [ -z "$first" ]; then
          first="$(printf '%s\t%s\n' "$instance" "$socket")"
        fi

        if [ -n "$scope" ]; then
          cgroup="$(cat "/proc/$pid/cgroup" 2>/dev/null || true)"
          case "$cgroup" in
            *"/$scope"*)
              selected="$(printf '%s\t%s\n' "$instance" "$socket")"
              break
              ;;
          esac
        fi
      done <"$tmp"

      rm -f "$tmp"
      if [ -n "$selected" ]; then
        printf '%s\n' "$selected"
        return 0
      fi

      if [ "$count" -eq 1 ]; then
        printf '%s\n' "$first"
        return 0
      fi

      return 1
    }

    resolve_instance() {
      i=0
      while [ "$i" -lt 60 ]; do
        resolved="$(resolve_instance_once || true)"
        if [ -n "$resolved" ]; then
          printf '%s\n' "$resolved"
          return 0
        fi

        i=$((i + 1))
        sleep 0.5
      done

      return 1
    }

    set_active_env() {
      resolved="$(resolve_instance)"
      HYPRLAND_INSTANCE_SIGNATURE="$(printf '%s\n' "$resolved" | cut -f1)"
      WAYLAND_DISPLAY="$(printf '%s\n' "$resolved" | cut -f2)"
      XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-Hyprland}"
      RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

      export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP RUNTIME_DIR
    }

    wait_socket() {
      set_active_env

      i=0
      while [ "$i" -lt 60 ]; do
        if [ -S "$RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
          return 0
        fi

        i=$((i + 1))
        sleep 0.5
      done

      return 1
    }

    import_env() {
      wait_socket

      set -- WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
      if [ -n "''${DISPLAY:-}" ]; then
        set -- "$@" DISPLAY
      fi
      if [ -n "''${THEME:-}" ]; then
        set -- "$@" THEME
      fi

      systemctl --user import-environment "$@"
      dbus-update-activation-environment --systemd "$@"
    }

    usage() {
      printf '%s\n' 'Usage: hypr-session-env {exec <command...>|import|wait|print}' >&2
    }

    command="''${1:-}"
    case "$command" in
      exec)
        shift
        [ "$#" -gt 0 ] || {
          usage
          exit 1
        }
        wait_socket
        exec "$@"
        ;;
      import)
        import_env
        ;;
      wait)
        wait_socket
        ;;
      print)
        set_active_env
        printf '%s\n' "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
        printf '%s\n' "HYPRLAND_INSTANCE_SIGNATURE=$HYPRLAND_INSTANCE_SIGNATURE"
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  '';

  mkWaylandGate = target: {
    partOf = [ target ];
    after = [ target ];
    wantedBy = [ target ];
    startLimitIntervalSec = 120;
    startLimitBurst = 5;
    serviceConfig = {
      ExecStartPre = "${hyprSessionEnv}/bin/hypr-session-env wait";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  wrapWaylandExec = command: "${hyprSessionEnv}/bin/hypr-session-env exec ${command}";
in
{
  inherit hyprSessionEnv mkWaylandGate wrapWaylandExec;
}
