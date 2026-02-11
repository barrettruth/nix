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
in
{
  home.sessionVariables = lib.optionalAttrs enableZen {
    BROWSER = "zen";
  }
  // lib.optionalAttrs enableClaude {
    CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
  };

  programs.mpv.enable = true;

  home.packages =
    with pkgs;
    [
      signal-desktop
      slack
      bitwarden-desktop
      gemini-cli
    ]
    ++ lib.optionals enableClaude [ claude-code ]
    ++ lib.optionals enableZen [ zen-browser.packages.${hostPlatform}.default ]
    ++ lib.optionals enableSioyek [ sioyek ]
    ++ lib.optionals enableVesktop [ vesktop ];

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

  home.activation.linkZenProfile = lib.mkIf enableZen (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      zen_config="$HOME/.zen"
      repo_zen="${config.home.homeDirectory}/.config/nix/config/zen"

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
    defaultApplications =
      { }
      // lib.optionalAttrs enableZen {
        "x-scheme-handler/http" = "zen.desktop";
        "x-scheme-handler/https" = "zen.desktop";
        "text/html" = "zen.desktop";
      }
      // lib.optionalAttrs enableNeovim {
        "text/plain" = "nvim.desktop";
      }
      // lib.optionalAttrs enableSioyek {
        "application/pdf" = "sioyek.desktop";
        "application/epub" = "sioyek.desktop";
      }
      // lib.optionalAttrs enableVesktop {
        "x-scheme-handler/discord" = "vesktop.desktop";
      };
  };
}
