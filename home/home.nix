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
    ./modules/hyprlock.nix
    ./modules/hypridle.nix
    ./modules/hyprpaper.nix
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
  };
}
