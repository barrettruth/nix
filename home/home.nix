{
  lib,
  config,
  pkgs,
  hostConfig,
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
    ./modules/packages.nix
  ]
  ++ lib.optionals hostConfig.isLinux [
    ./modules/hyprland.nix
    ./modules/ui.nix
  ];

  config = {
    theme = "midnight";

    home.username = "barrett";
    home.homeDirectory =
      if hostConfig.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";
    home.stateVersion = "24.11";

    xdg.enable = true;
    xdg.userDirs = lib.mkIf hostConfig.isLinux {
      enable = true;
      createDirectories = true;
      desktop = "${config.home.homeDirectory}/Desktop";
      documents = "${config.home.homeDirectory}/Documents";
      download = "${config.home.homeDirectory}/Downloads";
      music = "${config.home.homeDirectory}/Music";
      pictures = "${config.home.homeDirectory}/Pictures";
      publicShare = "${config.home.homeDirectory}/Public";
      templates = "${config.home.homeDirectory}/Templates";
      videos = "${config.home.homeDirectory}/Videos";
    };
    home.sessionVariables = lib.mkIf hostConfig.isLinux {
      XDG_DESKTOP_DIR = config.xdg.userDirs.desktop;
      XDG_DOCUMENTS_DIR = config.xdg.userDirs.documents;
      XDG_DOWNLOAD_DIR = config.xdg.userDirs.download;
      XDG_MUSIC_DIR = config.xdg.userDirs.music;
      XDG_PICTURES_DIR = config.xdg.userDirs.pictures;
      XDG_PUBLICSHARE_DIR = config.xdg.userDirs.publicShare;
      XDG_TEMPLATES_DIR = config.xdg.userDirs.templates;
      XDG_VIDEOS_DIR = config.xdg.userDirs.videos;
    };
    targets.genericLinux.enable = hostConfig.isLinux && !hostConfig.isNixOS;
    news.display = "silent";

    home.sessionPath = [ "${config.home.homeDirectory}/.config/nix/scripts" ];

    programs.home-manager.enable = true;

    systemd.user.services.nix-flake-update = lib.mkIf hostConfig.isLinux {
      Unit.Description = "Update nix flake inputs";
      Service = {
        Type = "oneshot";
        WorkingDirectory = "%h/.config/nix";
        ExecStart = "${pkgs.nix}/bin/nix flake update";
      };
    };

    systemd.user.timers.nix-flake-update = lib.mkIf hostConfig.isLinux {
      Unit.Description = "Auto-update nix flake inputs";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.theme-apply = lib.mkIf hostConfig.isLinux {
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

    systemd.user.services.cliphist-wipe = lib.mkIf hostConfig.isLinux {
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
