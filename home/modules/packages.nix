{
  pkgs,
  lib,
  config,
  zen-browser,
  hostConfig,
  ...
}:

let
  repoDir = "${config.home.homeDirectory}/.config/nix";

  neovim = config.programs.neovim.enable;
  zen = true;
  sioyek = true;
  vesktop = true;
  signal = true;

  hexDigit =
    c:
    {
      "0" = 0;
      "1" = 1;
      "2" = 2;
      "3" = 3;
      "4" = 4;
      "5" = 5;
      "6" = 6;
      "7" = 7;
      "8" = 8;
      "9" = 9;
      "a" = 10;
      "b" = 11;
      "c" = 12;
      "d" = 13;
      "e" = 14;
      "f" = 15;
    }
    .${c};

  hexByte =
    hex: offset:
    hexDigit (builtins.substring offset 1 hex) * 16 + hexDigit (builtins.substring (offset + 1) 1 hex);

  pad3 =
    n:
    if n < 10 then
      "00${toString n}"
    else if n < 100 then
      "0${toString n}"
    else
      toString n;

  byteToFloat =
    n:
    let
      scaled = (n * 1000 + 127) / 255;
    in
    "${toString (scaled / 1000)}.${pad3 (scaled - (scaled / 1000) * 1000)}";

  hexToRgb =
    hex: "${byteToFloat (hexByte hex 1)} ${byteToFloat (hexByte hex 3)} ${byteToFloat (hexByte hex 5)}";

  mkSioyekTheme =
    palette: isDark:
    ''
      background_color ${hexToRgb palette.bg}
      custom_background_color ${hexToRgb palette.bg}
      text_highlight_color ${hexToRgb palette.bgAlt}
      visual_mark_color ${hexToRgb palette.bgAlt} 1.0
      custom_text_color ${hexToRgb palette.fg}
      ui_text_color ${hexToRgb palette.fg}
      ui_selected_text_color ${hexToRgb palette.fg}
      link_highlight_color ${hexToRgb palette.accent}
      search_highlight_color ${hexToRgb palette.accent}
      synctex_highlight_color ${hexToRgb palette.accent}
      highlight_color_a ${hexToRgb palette.blue}
      highlight_color_b ${hexToRgb palette.green}
      highlight_color_c ${hexToRgb palette.yellow}
      highlight_color_d ${hexToRgb palette.red}
      highlight_color_e ${hexToRgb palette.magenta}
      highlight_color_f ${hexToRgb palette.cyan}
      highlight_color_g ${hexToRgb palette.yellow}
      ui_background_color ${hexToRgb palette.bg}
      ui_selected_background_color ${hexToRgb palette.accent}
      status_bar_color ${hexToRgb palette.bg}
      status_bar_text_color ${hexToRgb palette.fg}
    ''
    + lib.optionalString isDark "startup_commands toggle_dark_mode\n";

  chromiumVersion = pkgs.ungoogled-chromium.version;

  mkCrx =
    { id, sha256, version }:
    {
      inherit id version;
      crxPath = builtins.fetchurl {
        url =
          "https://clients2.google.com/service/update2/crx"
          + "?response=redirect&acceptformat=crx2,crx3"
          + "&prodversion=${chromiumVersion}"
          + "&x=id%3D${id}%26installsource%3Dondemand%26uc";
        inherit sha256;
      };
    };

  sioyek-wrapped = pkgs.symlinkJoin {
    name = "sioyek";
    paths = [ pkgs.sioyek ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/sioyek \
        --set QT_QPA_PLATFORM xcb \
        --add-flags "--execute-command toggle_statusbar" \
        --add-flags "--execute-command toggle_synctex"
    '';
  };
in
{
  home.sessionVariables = lib.mkIf hostConfig.isLinux { BROWSER = "chromium"; };

  programs.mpv.enable = true;

  home.packages =
    with pkgs;
    [
      slack
      gemini-cli
      typst
      typstyle
      glab
    ]
    ++ lib.optionals hostConfig.isLinux [
      bitwarden-desktop
      libreoffice-fresh
    ]
    ++ lib.optionals zen [ zen-browser.packages.${hostConfig.platform}.default ]
    ++ lib.optionals sioyek [
      (if hostConfig.isLinux then sioyek-wrapped else pkgs.sioyek)
    ]
    ++ lib.optionals (vesktop && hostConfig.isLinux) [ pkgs.vesktop ]
    ++ lib.optionals (signal && hostConfig.isLinux) [ pkgs.signal-desktop ]
    ++ lib.optionals hostConfig.isLinux [ pkgs.element-desktop ];

  xdg.configFile."sioyek/keys_user.config" = lib.mkIf sioyek {
    text = ''
      previous_page k
      next_page j

      move_down J
      move_up K
      move_left l
      move_right h

      zoom_in =
      zoom_out -

      fit_to_page_height_smart s
      fit_to_page_width S

      toggle_presentation_mode T
      toggle_dark_mode d
      toggle_statusbar b

      close_window q

      synctex_under_cursor i
    '';
  };

  xdg.configFile."sioyek/prefs_user.config" = lib.mkIf sioyek {
    text = ''
      wheel_zoom_on_cursor 1
      page_separator_width 10
      should_launch_new_window 1

      source ${config.xdg.configHome}/sioyek/themes/theme.config

      font_size 18
      status_bar_font_size 18

      inverse_search_command nvim --server /tmp/nvim-preview.sock --remote-expr "execute('b +%2 %1 | normal! zz')"
    '';
  };

  xdg.configFile."sioyek/themes/midnight.config" = lib.mkIf sioyek {
    text = mkSioyekTheme config.palettes.midnight true;
  };

  xdg.configFile."sioyek/themes/daylight.config" = lib.mkIf sioyek {
    text = mkSioyekTheme config.palettes.daylight false;
  };

  home.activation.linkZenProfile = lib.mkIf (zen && hostConfig.isLinux) (
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

  programs.chromium = lib.mkIf hostConfig.isLinux {
    enable = true;
    package = pkgs.ungoogled-chromium;
    commandLineArgs = [
      "--enable-features=VerticalTabs,WaylandWindowDecorations"
      "--ozone-platform-hint=auto"
    ];
    extensions = [
      (mkCrx {
        id = "nngceckbapebfimnlniiiahkandclblb";
        sha256 = "14cfgn0dzqqkg6wpvjcbgdhvydpnvqlq83cy0llm1w36kxa8wm1j";
        version = "2026.2.0";
      })
      (mkCrx {
        id = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
        sha256 = "0zfcdcxdq98qqa1ad3w1bpnzald54d99hb6mv9zhpzgk7zgcrlm8";
        version = "4.9.121";
      })
      (mkCrx {
        id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
        sha256 = "08gd7scxysc1bgz2kzs8p9001pzbwf7hdwjq9ax14k8r19szz2qj";
        version = "2026.301.2014";
      })
      (mkCrx {
        id = "emffkefkbkpkgpdeeooapgaicgmcbolj";
        sha256 = "0jhzzf164mhbq7ly841ss79n0w2h5slgjp6y706caqxagq6h756y";
        version = "10.1.0";
      })
      {
        id = "ocaahdebbfolfmndjeplogmgcagdmblk";
        version = "1.5.4.2";
        crxPath = builtins.fetchurl {
          url = "https://github.com/NeverDecaf/chromium-web-store/releases/download/v1.5.4.2/Chromium.Web.Store.crx";
          sha256 = "0q3js6r6wzy0hqdjgm9n8kmwb8hn6prap7gp3vx0z3xgipgpp92c";
        };
      }
    ];
  };

  xdg.configFile."electron-flags.conf" = lib.mkIf hostConfig.isLinux {
    text = ''
      --enable-features=WaylandWindowDecorations
      --ozone-platform-hint=auto
    '';
  };

  xdg.mimeApps = lib.mkIf hostConfig.isLinux {
    enable = true;
    defaultApplications = lib.mkMerge [
      {
        "x-scheme-handler/http" = "chromium-browser.desktop";
        "x-scheme-handler/https" = "chromium-browser.desktop";
        "text/html" = "chromium-browser.desktop";
      }
      (lib.mkIf neovim {
        "text/plain" = "nvim.desktop";
      })
      (lib.mkIf sioyek {
        "application/pdf" = "sioyek.desktop";
        "application/epub+zip" = "sioyek.desktop";
      })
      (lib.mkIf vesktop {
        "x-scheme-handler/discord" = "vesktop.desktop";
      })
    ];
  };
}
