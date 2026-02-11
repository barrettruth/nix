{
  pkgs,
  lib,
  config,
  zen-browser,
  hostPlatform,
  ...
}:

let
  enableClaude = true;
  enableZen = true;
  enableSioyek = true;
  enableVesktop = true;
  enableNeovim = config.programs.neovim.enable;

  sioyek-wrapped = pkgs.symlinkJoin {
    name = "sioyek";
    paths = [ pkgs.sioyek ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/sioyek \
        --set QT_QPA_PLATFORM xcb
    '';
  };

  repoDir = "${config.home.homeDirectory}/.config/nix";
in
{
  home.sessionVariables = lib.mkMerge [
    (lib.mkIf enableZen { BROWSER = "zen"; })
    (lib.mkIf enableClaude { CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude"; })
  ];

  programs.mpv.enable = true;

  home.packages = lib.mkMerge [
    (with pkgs; [
      signal-desktop
      slack
      bitwarden-desktop
      gemini-cli
      typst
    ])
    (lib.mkIf enableClaude [ pkgs.claude-code ])
    (lib.mkIf enableZen [ zen-browser.packages.${hostPlatform}.default ])
    (lib.mkIf enableSioyek [ sioyek-wrapped ])
    (lib.mkIf enableVesktop [ pkgs.vesktop ])
  ];

  xdg.configFile."claude/settings.json" = lib.mkIf enableClaude {
    text = builtins.toJSON {
      permissions.defaultMode = "acceptEdits";
      network_access = true;
      allowed_domains = [
        "github.com"
        "raw.githubusercontent.com"
        "api.github.com"
      ];
      tools.web_fetch = true;
    };
  };

  xdg.configFile."claude/CLAUDE.md" = lib.mkIf enableClaude {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/claude/CLAUDE.md";
  };

  xdg.configFile."claude/rules" = lib.mkIf enableClaude {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/claude/rules";
  };

  xdg.configFile."claude/skills" = lib.mkIf enableClaude {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/claude/skills";
  };

  xdg.configFile."sioyek/keys_user.config" = lib.mkIf enableSioyek {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/sioyek/keys_user.config";
  };

  xdg.configFile."sioyek/prefs_user.config" = lib.mkIf enableSioyek {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/sioyek/prefs_user.config";
  };

  xdg.configFile."sioyek/themes/midnight.config" = lib.mkIf enableSioyek {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/sioyek/themes/midnight.config";
  };

  xdg.configFile."sioyek/themes/daylight.config" = lib.mkIf enableSioyek {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/sioyek/themes/daylight.config";
  };

  home.activation.linkZenProfile = lib.mkIf enableZen (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      zen_config="$HOME/.zen"
      repo_zen="${repoDir}/config/zen"

      if [ ! -d "$zen_config" ]; then
        exit 0
      fi

      profile=""
      for d in "$zen_config"/*.Default\ Profile; do
        [ -d "$d" ] && profile="$d" && break
      done

      if [ -z "$profile" ]; then
        exit 0
      fi

      mkdir -p "$profile/chrome"

      for f in userChrome.css user.js containers.json handlers.json zen-keyboard-shortcuts.json; do
        src="$repo_zen/$f"
        if [ "$f" = "userChrome.css" ]; then
          dest="$profile/chrome/$f"
        else
          dest="$profile/$f"
        fi

        [ -f "$src" ] || continue

        if [ -L "$dest" ]; then
          continue
        fi

        if [ -f "$dest" ]; then
          rm "$dest"
        fi

        ln -s "$src" "$dest"
      done
    ''
  );

  xdg.configFile."electron-flags.conf".text = ''
    --enable-features=WaylandWindowDecorations
    --ozone-platform-hint=auto
  '';

  xdg.mimeApps = {
    enable = true;
    defaultApplications = lib.mkMerge [
      (lib.mkIf enableZen {
        "x-scheme-handler/http" = "zen.desktop";
        "x-scheme-handler/https" = "zen.desktop";
        "text/html" = "zen.desktop";
      })
      (lib.mkIf enableNeovim {
        "text/plain" = "nvim.desktop";
      })
      (lib.mkIf enableSioyek {
        "application/pdf" = "sioyek.desktop";
        "application/epub+zip" = "sioyek.desktop";
      })
      (lib.mkIf enableVesktop {
        "x-scheme-handler/discord" = "vesktop.desktop";
      })
    ];
  };
}
