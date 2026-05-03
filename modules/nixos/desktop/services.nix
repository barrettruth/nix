{
  pkgs,
  lib,
  hostConfig,
  whisperPkgs ? pkgs,
  ...
}:
let
  wayland = import ./wayland.nix { inherit pkgs hostConfig; };
  inherit (wayland)
    mkWaylandGate
    wrapWaylandExec
    ;
  waylandGate = mkWaylandGate "hyprland-session.target";
  gpgCacheTtlSeconds = 2147483647;
in
lib.mkMerge [
  {
    programs.gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
      settings = {
        default-cache-ttl = gpgCacheTtlSeconds;
        default-cache-ttl-ssh = gpgCacheTtlSeconds;
        max-cache-ttl = gpgCacheTtlSeconds;
        max-cache-ttl-ssh = gpgCacheTtlSeconds;
      };
    };

    systemd.user.services.nix-flake-update = {
      description = "Update nix flake inputs";
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = "%h/.config/nix";
        ExecStart = "${pkgs.nix}/bin/nix flake update";
      };
    };

    systemd.user.timers.nix-flake-update = {
      description = "Auto-update nix flake inputs";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.user.services.direnv-cache-prune = {
      description = "Prune stale direnv and nix-direnv caches";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "direnv-cache-prune" ''
          set -euo pipefail

          ${pkgs.direnv}/bin/direnv prune || true

          for root in "$HOME/dev" "$HOME/.config/nix"; do
            [ -d "$root" ] || continue

            ${pkgs.findutils}/bin/find "$root" -maxdepth 3 -type d -name .direnv -prune -print0 \
              | while IFS= read -r -d "" cache; do
                  recent_cache=$(${pkgs.findutils}/bin/find "$cache" -mindepth 1 -maxdepth 2 \
                    \( -name 'flake-profile*' -o -name 'nix-profile*' -o -path "$cache/flake-inputs/*" \) \
                    -mtime -7 -print -quit)
                  if [ -n "$recent_cache" ]; then
                    continue
                  fi

                  ${pkgs.coreutils}/bin/rm -f -- "$cache"/flake-profile* "$cache"/nix-profile* "$cache"/*.rc
                  ${pkgs.coreutils}/bin/rm -rf -- "$cache/flake-inputs"
                  ${pkgs.findutils}/bin/find "$cache" -type d -empty -delete
                done
          done
        '';
      };
    };

    systemd.user.timers.direnv-cache-prune = {
      description = "Auto-prune stale direnv caches";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.user.services.whisper-dictation =
      let
        whisper = whisperPkgs.whisper-cpp.override { cudaSupport = hostConfig.gpu == "nvidia"; };
      in
      {
        description = "Whisper dictation server";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${whisper}/bin/whisper-server --model ${hostConfig.XDG_DATA_HOME}/whisper-models/ggml-large-v3-turbo-q5_0.bin --host 127.0.0.1 --port 8178";
        };
      };
  }

  (lib.mkIf hostConfig.enableWayland {
    systemd.user.services.cliphist = waylandGate // {
      description = "Clipboard history";
      serviceConfig = waylandGate.serviceConfig // {
        ExecStart = wrapWaylandExec "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      };
    };

    systemd.user.services.cliphist-wipe = {
      description = "Clear clipboard history on session end";
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = "${pkgs.cliphist}/bin/cliphist wipe";
      };
    };
  })

  (lib.mkIf hostConfig.enableDesktop {
    systemd.user.services.dconf-setup = {
      description = "Set dconf preferences";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "dconf-setup" ''
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/font-name "'SF Pro Display 11'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/document-font-name "'SF Pro Display 11'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/monospace-font-name "'Berkeley Mono 11'"
        '';
      };
    };
  })
]
