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
in
lib.mkMerge [
  {
    programs.gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
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
