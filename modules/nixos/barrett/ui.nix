{
  config,
  pkgs,
  lib,
  palettes ? null,
  themeGenerators ? null,
  ...
}:
let
  cfg = config.barrett.ui;
  user = config.barrett.user;
  username = user.name;
  homeDirectory = user.homeDirectory;
  XDG_CONFIG_HOME = "${homeDirectory}/.config";
  XDG_DATA_HOME = "${homeDirectory}/.local/share";
  XDG_STATE_HOME = "${homeDirectory}/.local/state";
  XDG_CACHE_HOME = "${homeDirectory}/.cache";
  repo = "${XDG_CONFIG_HOME}/nix";
  sourceRoot = ../../..;
  sourceConfig = "${sourceRoot}/config";
  sourceScripts = "${sourceRoot}/scripts";
  configRoot = if cfg.useHomeRepo then "${repo}/config" else sourceConfig;
  scriptsPath = if cfg.useHomeRepo then "${repo}/scripts" else "${uiScripts}/bin";

  uiScripts = pkgs.runCommand "barrett-ui-scripts" { } ''
    mkdir -p $out/bin
    for script in ctl hypr mux theme waybarctl; do
      ln -s ${sourceScripts}/$script $out/bin/$script
    done
  '';

  wayland = import ../desktop/wayland.nix { inherit pkgs; };
  inherit (wayland)
    hyprSessionEnv
    mkWaylandGate
    wrapWaylandExec
    ;
  waylandGate = mkWaylandGate "hyprland-session.target";

  mkSymlink = target: link: ''
    ln -sfnT "${target}" "${link}"
    chown -h ${username}:users "${link}"
  '';

  mkDir = dir: ''
    install -d -o ${username} -g users "${dir}"
  '';

  readTheme = ''
    theme="$(cat "${XDG_STATE_HOME}/theme" 2>/dev/null)" || theme="midnight"
    [ -z "$theme" ] && theme="midnight"
  '';

  zshInit = pkgs.writeText "zsh-init" ''
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
    source ${pkgs.fzf}/share/fzf/key-bindings.zsh
    source ${pkgs.fzf}/share/fzf/completion.zsh
    eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
    alias ls="${pkgs.eza}/bin/eza --git"
    source ${configRoot}/zsh/zshrc
  '';

  mimeappsList = pkgs.writeText "mimeapps-ui.list" ''
    [Default Applications]
    x-scheme-handler/http=chromium-browser.desktop
    x-scheme-handler/https=chromium-browser.desktop
    text/html=chromium-browser.desktop
    text/plain=nvim.desktop
  '';

  fzfThemes = pkgs.runCommand "fzf-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight << 'FZFMIDNIGHT'
    ${themeGenerators.mkFzfTheme palettes.midnight}
    FZFMIDNIGHT

    cat > $out/daylight << 'FZFDAYLIGHT'
    ${themeGenerators.mkFzfTheme palettes.daylight}
    FZFDAYLIGHT
  '';

  hyprThemes = pkgs.runCommand "hypr-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.conf << 'HYPRMIDNIGHT'
    ${themeGenerators.mkHyprTheme palettes.midnight}
    HYPRMIDNIGHT

    cat > $out/daylight.conf << 'HYPRDAYLIGHT'
    ${themeGenerators.mkHyprTheme palettes.daylight}
    HYPRDAYLIGHT
  '';

  waybarThemes = pkgs.runCommand "waybar-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.css << 'WAYBARMIDNIGHT'
    ${themeGenerators.mkWaybarTheme palettes.midnight}
    WAYBARMIDNIGHT

    cat > $out/daylight.css << 'WAYBARDAYLIGHT'
    ${themeGenerators.mkWaybarTheme palettes.daylight}
    WAYBARDAYLIGHT
  '';

  fuzzelThemes = pkgs.runCommand "fuzzel-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.ini << 'FUZZELMIDNIGHT'
    ${themeGenerators.mkFuzzelTheme palettes.midnight}
    FUZZELMIDNIGHT

    cat > $out/daylight.ini << 'FUZZELDAYLIGHT'
    ${themeGenerators.mkFuzzelTheme palettes.daylight}
    FUZZELDAYLIGHT
  '';

  dunstThemes = pkgs.runCommand "dunst-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.conf << 'DUNSTMIDNIGHT'
    ${themeGenerators.mkDunstTheme palettes.midnight}
    DUNSTMIDNIGHT

    cat > $out/daylight.conf << 'DUNSTDAYLIGHT'
    ${themeGenerators.mkDunstTheme palettes.daylight}
    DUNSTDAYLIGHT
  '';

  waybarConfig = pkgs.writeText "waybar-config" (
    builtins.replaceStrings [ "$HOME/.config/nix" ] [ "${sourceRoot}" ] (
      builtins.readFile (sourceRoot + "/config/waybar/config.jsonc")
    )
  );
  waybarConfigFile = if cfg.useHomeRepo then "${configRoot}/waybar/config.jsonc" else waybarConfig;

  chromiumExtension = pkgs.runCommand "chromium-extension" { } ''
    cp -R --no-preserve=mode,ownership ${sourceConfig}/chromium/extension $out
    ln -sfnT ${chromiumThemeCss} $out/theme.css
    ln -sfnT ${chromiumThemeJs} $out/theme.js
  '';

  fuzzelConf = pkgs.writeText "fuzzel-wrapper" ''
    include=${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini
    include=${configRoot}/fuzzel/fuzzel.ini
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
    source = ${configRoot}/hypr/hosts/${config.networking.hostName}.conf
    source = ${configRoot}/hypr/hyprland.conf
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
    export BARRETT_NIX_CONFIG_DIR=${configRoot}
    ${scriptsPath}/ctl wallpaper lock
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

    ${lib.optionalString cfg.idle.suspend ''
      listener {
        timeout = 3600
        on-timeout = ${pkgs.systemd}/bin/systemctl suspend
      }
    ''}
  '';

  hypridleStart = pkgs.writeShellScript "hypridle-start" ''
    set -eu

    export BARRETT_NIX_CONFIG_DIR=${configRoot}
    if [ "$(${scriptsPath}/ctl idle state)" = off ]; then
      exit 0
    fi

    exec ${wrapWaylandExec "${pkgs.hypridle}/bin/hypridle"}
  '';

  chromiumThemeCss = pkgs.writeText "chromium-theme.css" themeGenerators.mkChromeThemeCss;
  chromiumThemeJs = pkgs.writeText "chromium-theme.js" themeGenerators.mkChromeThemeJs;

  chromiumArgs = [
    "--ozone-platform=wayland"
    "--silent-debugger-extension-api"
    "--enable-features=AcceleratedVideoDecodeLinuxZeroCopyGL"
  ];

  chromiumBase = pkgs.chromium.override {
    commandLineArgs = lib.concatStringsSep " " chromiumArgs;
  };

  chromium = pkgs.symlinkJoin {
    name = chromiumBase.name;
    paths = [ chromiumBase ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = lib.optionalString (cfg.gpu == "nvidia") ''
      wrapProgram "$out/bin/chromium" \
        --set __NV_PRIME_RENDER_OFFLOAD 1 \
        --set __NV_PRIME_RENDER_OFFLOAD_PROVIDER NVIDIA-G0 \
        --set __GLX_VENDOR_LIBRARY_NAME nvidia \
        --set __VK_LAYER_NV_optimus NVIDIA_only
    '';
  };
in
{
  options.barrett.ui = {
    enable = lib.mkEnableOption "Barrett graphical interface";
    gpu = lib.mkOption {
      type = lib.types.enum [
        "generic"
        "nvidia"
      ];
      default = "generic";
    };
    idle.suspend = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    useHomeRepo = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = palettes != null && themeGenerators != null;
        message = "barrett.ui.enable requires palettes and themeGenerators module arguments";
      }
    ];

    users.users.${username} = {
      shell = lib.mkDefault pkgs.zsh;
      packages =
        (with pkgs; [
          pure-prompt
          fzf
          eza
          zoxide
          ripgrep
          fd
          git
          neovim
          ghostty
          jq
          curl
          openssl
          socat
          procps
          dconf
          hyprlock
          hyprpaper
          hypridle
          hyprland
          waybar
          fuzzel
          dunst
          xdg-desktop-portal-hyprland
          xdg-desktop-portal-gtk
          wl-clipboard
          grim
          slurp
          wf-recorder
          cliphist
          tesseract
          papirus-icon-theme
          apple-cursor
          libnotify
          gsettings-desktop-schemas
          zsh-syntax-highlighting
          zsh-autosuggestions
        ])
        ++ [
          chromium
          uiScripts
        ];
    };

    fonts.packages = with pkgs; [
      barrett-fonts
      iosevka
      dejavu_fonts
      freefont_ttf
      gyre-fonts
      liberation_ttf
      unifont
      noto-fonts-color-emoji
    ];

    fonts.fontconfig.defaultFonts = {
      sansSerif = [ "SF Pro Display" ];
      monospace = [ "Berkeley Mono" ];
      serif = [ "Times New Roman" ];
    };

    environment.sessionVariables = {
      XDG_CONFIG_HOME = XDG_CONFIG_HOME;
      XDG_DATA_HOME = XDG_DATA_HOME;
      XDG_STATE_HOME = XDG_STATE_HOME;
      XDG_CACHE_HOME = XDG_CACHE_HOME;
      EDITOR = "nvim";
      MANPAGER = "nvim +Man!";
      TERMINAL = "ghostty";
      TERM = "xterm-ghostty";
      TERMINFO = "${XDG_DATA_HOME}/terminfo";
      BROWSER = "chromium";
      LESSHISTFILE = "-";
      BARRETT_NIX_CONFIG_DIR = configRoot;
      FZF_DEFAULT_OPTS_FILE = "${XDG_CONFIG_HOME}/fzf/themes/theme";
      FZF_DEFAULT_COMMAND = "rg --files --hidden";
      FZF_CTRL_T_COMMAND = "rg --files --hidden";
      FZF_ALT_C_COMMAND = "fd --type d --hidden";
      HYPRLAND_NO_SD_VARS = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      XCURSOR_SIZE = "24";
      XCURSOR_THEME = "macOS";
    };

    environment.extraInit = ''
      export PATH="${scriptsPath}:${homeDirectory}/.local/bin:$PATH"
    '';

    programs.zsh = {
      enable = true;
      shellInit = ''
        export ZDOTDIR="$HOME/.config/zsh"
        THEME="$(cat "''${XDG_STATE_HOME:-$HOME/.local/state}/theme" 2>/dev/null)" || THEME="midnight"
        [ -z "$THEME" ] && THEME="midnight"
        export THEME
      '';
      loginShellInit = ''
        if [[ -z "$DISPLAY$WAYLAND_DISPLAY" && "$(tty)" == /dev/tty1 ]]; then
          [ -e /etc/set-environment ] && . /etc/set-environment
          exec start-hyprland
        fi
      '';
    };

    security.pam.services.hyprlock = { };

    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];
      config.common = {
        default = [
          "hyprland"
          "gtk"
        ];
      };
    };

    environment.pathsToLink = [
      "/share/applications"
      "/share/xdg-desktop-portal"
    ];

    systemd.tmpfiles.rules = [
      "d ${homeDirectory}/Pictures/Screensavers 0755 ${username} users -"
      "d ${homeDirectory}/Pictures/Screenshots 0755 ${username} users -"
      "d ${homeDirectory}/Pictures/wp 0755 ${username} users -"
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

    systemd.user.services.dunst = waylandGate // {
      description = "Dunst notification daemon";
      serviceConfig = waylandGate.serviceConfig // {
        ExecStart = wrapWaylandExec "${pkgs.dunst}/bin/dunst";
      };
    };

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
          ${pkgs.dconf}/bin/dconf write /org/gnome/system/location/enabled true
        '';
      };
    };

    system.activationScripts.barrettUiConfig.text = ''
      ${mkDir "${XDG_CONFIG_HOME}/zsh"}
      ${mkDir "${XDG_STATE_HOME}/zsh"}
      ${mkDir "${XDG_CONFIG_HOME}/ghostty"}
      [ -d "${XDG_CONFIG_HOME}/ghostty/themes" ] && [ ! -L "${XDG_CONFIG_HOME}/ghostty/themes" ] && rm -rf "${XDG_CONFIG_HOME}/ghostty/themes"
      ${mkDir "${XDG_CONFIG_HOME}/fzf/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/hypr/themes"}
      ${mkDir "${XDG_STATE_HOME}/hypr"}
      ${mkDir "${XDG_CONFIG_HOME}/waybar/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/fuzzel/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst/dunstrc.d"}
      ${mkDir "${homeDirectory}/Pictures/Screensavers"}

      ${mkSymlink "${mimeappsList}" "${XDG_CONFIG_HOME}/mimeapps.list"}
      ${lib.optionalString (!cfg.useHomeRepo) ''
        if [ ! -e "${repo}" ] && [ ! -L "${repo}" ]; then
          ln -sfnT "${sourceRoot}" "${repo}"
          chown -h ${username}:users "${repo}"
        fi
      ''}

      ${mkSymlink "${zshInit}" "${XDG_CONFIG_HOME}/zsh/.zshrc"}
      ${mkSymlink "${configRoot}/nvim" "${XDG_CONFIG_HOME}/nvim"}
      ${mkSymlink "${configRoot}/ghostty/config" "${XDG_CONFIG_HOME}/ghostty/config"}
      ${mkSymlink "${configRoot}/ghostty/themes" "${XDG_CONFIG_HOME}/ghostty/themes"}

      ${mkSymlink "${fzfThemes}/midnight" "${XDG_CONFIG_HOME}/fzf/themes/midnight"}
      ${mkSymlink "${fzfThemes}/daylight" "${XDG_CONFIG_HOME}/fzf/themes/daylight"}

      ${mkSymlink "${hyprThemes}/midnight.conf" "${XDG_CONFIG_HOME}/hypr/themes/midnight.conf"}
      ${mkSymlink "${hyprThemes}/daylight.conf" "${XDG_CONFIG_HOME}/hypr/themes/daylight.conf"}
      ${mkSymlink "${hyprlandConf}" "${XDG_CONFIG_HOME}/hypr/hyprland.conf"}
      ${mkSymlink "${hyprpaperConf}" "${XDG_CONFIG_HOME}/hypr/hyprpaper.conf"}
      ${mkSymlink "${hypridleConf}" "${XDG_CONFIG_HOME}/hypr/hypridle.conf"}
      ${mkSymlink "${hyprlockConf}" "${XDG_CONFIG_HOME}/hypr/hyprlock.conf"}

      ${mkSymlink "${waybarThemes}/midnight.css" "${XDG_CONFIG_HOME}/waybar/themes/midnight.css"}
      ${mkSymlink "${waybarThemes}/daylight.css" "${XDG_CONFIG_HOME}/waybar/themes/daylight.css"}
      ${mkSymlink "${waybarConfigFile}" "${XDG_CONFIG_HOME}/waybar/config"}
      ${mkSymlink "${configRoot}/waybar/style.css" "${XDG_CONFIG_HOME}/waybar/style.css"}

      ${mkSymlink "${fuzzelThemes}/midnight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/midnight.ini"}
      ${mkSymlink "${fuzzelThemes}/daylight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/daylight.ini"}
      ${mkSymlink "${fuzzelConf}" "${XDG_CONFIG_HOME}/fuzzel/fuzzel.ini"}

      ${mkSymlink "${dunstThemes}/midnight.conf" "${XDG_CONFIG_HOME}/dunst/themes/midnight.conf"}
      ${mkSymlink "${dunstThemes}/daylight.conf" "${XDG_CONFIG_HOME}/dunst/themes/daylight.conf"}
      ${mkSymlink "${configRoot}/dunst/dunstrc" "${XDG_CONFIG_HOME}/dunst/dunstrc"}

      ${lib.optionalString cfg.useHomeRepo ''
        ${mkSymlink "${chromiumThemeCss}" "${configRoot}/chromium/extension/theme.css"}
        ${mkSymlink "${chromiumThemeJs}" "${configRoot}/chromium/extension/theme.js"}
      ''}
      ${lib.optionalString (!cfg.useHomeRepo) ''
        ${mkDir "${XDG_CONFIG_HOME}/chromium"}
        ${mkSymlink "${chromiumExtension}" "${XDG_CONFIG_HOME}/chromium/extension"}
      ''}

      ${readTheme}
      ${mkSymlink "${XDG_CONFIG_HOME}/fzf/themes/$theme" "${XDG_CONFIG_HOME}/fzf/themes/theme"}
      ${mkSymlink "${XDG_CONFIG_HOME}/hypr/themes/$theme.conf" "${XDG_CONFIG_HOME}/hypr/themes/theme.conf"}
      ${mkSymlink "${XDG_CONFIG_HOME}/waybar/themes/$theme.css" "${XDG_CONFIG_HOME}/waybar/themes/theme.css"}
      ${mkSymlink "${XDG_CONFIG_HOME}/fuzzel/themes/$theme.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini"}
      ${mkSymlink "${XDG_CONFIG_HOME}/dunst/themes/$theme.conf" "${XDG_CONFIG_HOME}/dunst/dunstrc.d/theme.conf"}

      src="${configRoot}/screen"
      dest="${homeDirectory}/Pictures/Screensavers"
      if [ -d "$src" ]; then
        for f in "$src"/*; do
          [ -f "$f" ] || continue
          name=$(basename "$f")
          [ -L "$dest/$name" ] || ln -sf "$f" "$dest/$name"
        done
        chown -h ${username}:users "$dest"/* 2>/dev/null || true
      fi

      grayscale="$(cat "${XDG_STATE_HOME}/hypr/grayscale" 2>/dev/null)" || grayscale="off"
      case "$grayscale" in
        on) screen_shader="${configRoot}/hypr/shaders/grayscale.frag" ;;
        *) screen_shader="${configRoot}/hypr/shaders/pass-through.frag" ;;
      esac
      ln -sfnT "$screen_shader" "${XDG_STATE_HOME}/hypr/screen-shader.frag"
      chown -h ${username}:users "${XDG_STATE_HOME}/hypr/screen-shader.frag"

      wp_themed="${homeDirectory}/Pictures/Screensavers/wallpaper-$theme.jpg"
      wp_link="${homeDirectory}/Pictures/Screensavers/wallpaper.jpg"
      [ -f "$wp_themed" ] && {
        ln -sf "$wp_themed" "$wp_link"
        chown -h ${username}:users "$wp_link"
      }

      for profile in "${XDG_CONFIG_HOME}"/chromium/Default "${XDG_CONFIG_HOME}"/chromium/Profile\ *; do
        prefs="$profile/Preferences"
        [ -f "$prefs" ] || continue
        ${pkgs.python3}/bin/python "${configRoot}/chromium/seed_shortcuts.py" "$prefs"
        chown ${username}:users "$prefs"
      done

      [ -L ${homeDirectory}/.zshenv ] && rm ${homeDirectory}/.zshenv || true
    '';
  };
}
