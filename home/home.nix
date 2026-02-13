{
  lib,
  config,
  pkgs,
  isNixOS,
  ...
}:

{
  imports = [
    ./modules/bootstrap.nix
    ./modules/theme.nix
    ./modules/shell.nix
    ./modules/terminal.nix
    ./modules/git.nix
    ./modules/editor.nix
    ./modules/hyprland.nix
    ./modules/ui.nix
    ./modules/packages.nix
  ];

  config = {
    theme = "midnight";

    home.username = "barrett";
    home.homeDirectory = "/home/${config.home.username}";
    home.stateVersion = "24.11";

    xdg.enable = true;
    targets.genericLinux.enable = !isNixOS;
    news.display = "silent";

    home.sessionPath = [ "${config.home.homeDirectory}/.config/nix/scripts" ];

    programs.home-manager.enable = true;

    systemd.user.services.nix-flake-update = {
      Unit.Description = "Update nix flake inputs";
      Service = {
        Type = "oneshot";
        WorkingDirectory = "%h/.config/nix";
        ExecStart = "${pkgs.nix}/bin/nix flake update";
      };
    };

    systemd.user.timers.nix-flake-update = {
      Unit.Description = "Auto-update nix flake inputs";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.theme-apply = {
      Unit = {
        Description = "Apply theme on login";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -lc '${config.home.homeDirectory}/.config/nix/scripts/theme ${config.theme}'";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.cliphist-wipe = {
      Unit.Description = "Clear clipboard history on session end";
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = "${pkgs.cliphist}/bin/cliphist wipe";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
