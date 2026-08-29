{
  config,
  pkgs,
  lib,
  palettes,
  themeGenerators,
  act,
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
  configRoot = "${repo}/config";

  graphicalSession = {
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
  };

  inherit (act) runAsUser mkSymlink;
  mkDir = act.installDir;

  readTheme = ''
    theme="$(cat "${XDG_STATE_HOME}/theme" 2>/dev/null)" || theme="midnight"
    [ -z "$theme" ] && theme="midnight"
  '';

  mimeappsList = pkgs.writeText "mimeapps-ui.list" ''
    [Default Applications]
    x-scheme-handler/http=chromium-browser.desktop
    x-scheme-handler/https=chromium-browser.desktop
    text/html=chromium-browser.desktop
    text/plain=nvim.desktop
    application/pdf=org.pwmt.zathura.desktop
  '';

  zathuraThemes = pkgs.runCommand "zathura-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight << 'ZATHURAMIDNIGHT'
    ${themeGenerators.mkZathuraTheme palettes.midnight}
    ZATHURAMIDNIGHT

    cat > $out/daylight << 'ZATHURADAYLIGHT'
    ${themeGenerators.mkZathuraTheme palettes.daylight}
    ZATHURADAYLIGHT
  '';

  hyprThemes = pkgs.runCommand "hypr-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.lua << 'HYPRMIDNIGHT'
    ${themeGenerators.mkHyprTheme palettes.midnight}
    HYPRMIDNIGHT

    cat > $out/daylight.lua << 'HYPRDAYLIGHT'
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

  fuzzelConf = pkgs.writeText "fuzzel-wrapper" ''
    include=${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini
    include=${configRoot}/fuzzel/fuzzel.ini
  '';

  hyprlandConf = pkgs.writeText "hyprland-wrapper.lua" ''
    hl.env("XCURSOR_SIZE", "24")
    hl.env("HYPRCURSOR_SIZE", "24")
    hl.env("HYPRCURSOR_THEME", "macOS")
    hl.env("GSK_RENDERER", "ngl")

    hl.on("hyprland.start", function()
        hl.exec_cmd("${lib.getExe pkgs.uwsm} finalize")
    end)

    local function source(path)
        local ok, err = pcall(require, path)
        if ok then
            return
        end

        hl.on("hyprland.start", function()
            hl.notification.create({ text = "hyprland: " .. tostring(err), timeout = 15000 })
        end)
    end

    source("${configRoot}/hypr/hosts/${config.networking.hostName}.lua")
    source("${configRoot}/hypr/hyprland.lua")
  '';

  hyprpaperConf = pkgs.writeText "hyprpaper-conf" ''
    splash = 0

    wallpaper {
      monitor =
      path = ${homeDirectory}/Pictures/Screensavers/wallpaper.jpg
    }
  '';

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
    postBuild = lib.optionalString (cfg.gpu == "nvidia-prime") ''
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
        "nvidia-prime"
      ];
      default = "generic";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${username} = {
      shell = lib.mkDefault pkgs.zsh;
      packages =
        (with pkgs; [
          hyprpaper
          waybar
          fuzzel
          dunst
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
          zathura
          ffmpeg
          poppler-utils
          librsvg
          brightnessctl
          glib.bin
          (mpv.override { youtubeSupport = false; })
        ])
        ++ [
          chromium
        ];
    };

    fonts.packages = [
      pkgs.barrett-berkeley-mono
    ]
    ++ (with pkgs; [
      dejavu_fonts
      freefont_ttf
      gyre-fonts
      liberation_ttf
      unifont
      noto-fonts-color-emoji
    ]);

    fonts.fontconfig.defaultFonts = {
      sansSerif = [
        "DejaVu Sans"
      ];
      monospace = [
        "Berkeley Mono"
      ];
      serif = [
        "Times New Roman"
        "DejaVu Serif"
      ];
    };

    environment.sessionVariables = {
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      XCURSOR_SIZE = "24";
      XCURSOR_THEME = "macOS";
    };

    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    programs.zsh = {
      enable = true;
      loginShellInit = ''
        if [[ -z "$DISPLAY$WAYLAND_DISPLAY" && "$(tty)" == /dev/tty1 ]] && ${lib.getExe pkgs.uwsm} check may-start; then
          exec ${lib.getExe pkgs.uwsm} start -F -- ${pkgs.hyprland}/bin/start-hyprland
        fi
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${homeDirectory}/Pictures/Screensavers 0755 ${username} users -"
      "d ${homeDirectory}/Pictures/Screenshots 0755 ${username} users -"
      "d ${homeDirectory}/Pictures/wp 0755 ${username} users -"
    ];

    systemd.user.services.hyprpaper = graphicalSession // {
      description = "Hyprpaper wallpaper daemon";
      serviceConfig = {
        ExecStart = lib.getExe pkgs.hyprpaper;
        Restart = "on-failure";
        Slice = "background-graphical.slice";
      };
    };

    systemd.user.services.dunst = graphicalSession // {
      description = "Dunst notification daemon";
      serviceConfig = {
        ExecStart = lib.getExe pkgs.dunst;
        Restart = "on-failure";
        Slice = "background-graphical.slice";
      };
    };

    systemd.user.services.cliphist = graphicalSession // {
      description = "Clipboard history";
      serviceConfig = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
        Slice = "app-graphical.slice";
      };
    };

    systemd.user.services.cliphist-wipe = {
      description = "Clear clipboard history on session end";
      partOf = [ "graphical-session.target" ];
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
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      before = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "dconf-setup" ''
          runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
          export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime_dir/bus}"
          theme="$(${pkgs.coreutils}/bin/cat "${XDG_STATE_HOME}/theme" 2>/dev/null || true)"
          [ -z "$theme" ] && theme="midnight"
          case "$theme" in
            daylight) color_scheme="prefer-light" ;;
            *) color_scheme="prefer-dark" ;;
          esac
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'$color_scheme'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/font-name "'DejaVu Sans 11'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/document-font-name "'DejaVu Sans 11'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/monospace-font-name "'Berkeley Mono 11'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/system/location/enabled true
        '';
      };
    };

    system.activationScripts.barrettUiConfig.text = ''
      ${mkDir "${XDG_CONFIG_HOME}"}
      ${mkDir "${XDG_DATA_HOME}"}
      ${mkDir "${XDG_STATE_HOME}"}
      ${mkDir "${XDG_CACHE_HOME}"}
      ${mkDir "${XDG_CONFIG_HOME}/hypr"}
      ${mkDir "${XDG_CONFIG_HOME}/hypr/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/xkb"}
      ${mkDir "${XDG_CONFIG_HOME}/xkb/symbols"}
      ${mkDir "${XDG_CONFIG_HOME}/waybar"}
      ${mkDir "${XDG_CONFIG_HOME}/waybar/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/fuzzel"}
      ${mkDir "${XDG_CONFIG_HOME}/fuzzel/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst/dunstrc.d"}
      ${mkDir "${XDG_CONFIG_HOME}/zathura"}
      ${mkDir "${XDG_CONFIG_HOME}/zathura/themes"}
      ${mkDir "${homeDirectory}/Pictures/Screensavers"}

      ${mkSymlink "${mimeappsList}" "${XDG_CONFIG_HOME}/mimeapps.list"}
      ${mkSymlink "${repo}/config/electron-flags.conf" "${XDG_CONFIG_HOME}/electron-flags.conf"}
      ${mkSymlink "${hyprThemes}/midnight.lua" "${XDG_CONFIG_HOME}/hypr/themes/midnight.lua"}
      ${mkSymlink "${hyprThemes}/daylight.lua" "${XDG_CONFIG_HOME}/hypr/themes/daylight.lua"}
      ${mkSymlink "${hyprlandConf}" "${XDG_CONFIG_HOME}/hypr/hyprland.lua"}
      ${mkSymlink "${hyprpaperConf}" "${XDG_CONFIG_HOME}/hypr/hyprpaper.conf"}

      ${mkSymlink "${waybarThemes}/midnight.css" "${XDG_CONFIG_HOME}/waybar/themes/midnight.css"}
      ${mkSymlink "${waybarThemes}/daylight.css" "${XDG_CONFIG_HOME}/waybar/themes/daylight.css"}
      ${mkSymlink "${configRoot}/waybar/config.jsonc" "${XDG_CONFIG_HOME}/waybar/config"}
      ${mkSymlink "${configRoot}/waybar/style.css" "${XDG_CONFIG_HOME}/waybar/style.css"}

      ${mkSymlink "${fuzzelThemes}/midnight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/midnight.ini"}
      ${mkSymlink "${fuzzelThemes}/daylight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/daylight.ini"}
      ${mkSymlink "${fuzzelConf}" "${XDG_CONFIG_HOME}/fuzzel/fuzzel.ini"}

      ${mkSymlink "${dunstThemes}/midnight.conf" "${XDG_CONFIG_HOME}/dunst/themes/midnight.conf"}
      ${mkSymlink "${dunstThemes}/daylight.conf" "${XDG_CONFIG_HOME}/dunst/themes/daylight.conf"}
      ${mkSymlink "${configRoot}/dunst/dunstrc" "${XDG_CONFIG_HOME}/dunst/dunstrc"}

      ${mkSymlink "${zathuraThemes}/midnight" "${XDG_CONFIG_HOME}/zathura/themes/midnight"}
      ${mkSymlink "${zathuraThemes}/daylight" "${XDG_CONFIG_HOME}/zathura/themes/daylight"}
      ${mkSymlink "${configRoot}/zathura/zathurarc" "${XDG_CONFIG_HOME}/zathura/zathurarc"}

      ${readTheme}
      ${mkSymlink "${XDG_CONFIG_HOME}/hypr/themes/$theme.lua" "${XDG_CONFIG_HOME}/hypr/themes/theme.lua"}
      ${mkSymlink "${XDG_CONFIG_HOME}/waybar/themes/$theme.css" "${XDG_CONFIG_HOME}/waybar/themes/theme.css"}
      ${mkSymlink "${XDG_CONFIG_HOME}/fuzzel/themes/$theme.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini"}
      ${mkSymlink "${XDG_CONFIG_HOME}/dunst/themes/$theme.conf" "${XDG_CONFIG_HOME}/dunst/dunstrc.d/theme.conf"}
      ${mkSymlink "${XDG_CONFIG_HOME}/zathura/themes/$theme" "${XDG_CONFIG_HOME}/zathura/theme"}

      src="${configRoot}/screen"
      dest="${homeDirectory}/Pictures/Screensavers"
      if [ -d "$src" ]; then
        for f in "$src"/*; do
          [ -f "$f" ] || continue
          name=$(basename "$f")
          [ -L "$dest/$name" ] || ${runAsUser} ${pkgs.coreutils}/bin/ln -sf "$f" "$dest/$name"
        done
      fi

      wp_themed="${homeDirectory}/Pictures/Screensavers/wallpaper-$theme.jpg"
      wp_link="${homeDirectory}/Pictures/Screensavers/wallpaper.jpg"
      [ -f "$wp_themed" ] && ${runAsUser} ${pkgs.coreutils}/bin/ln -sf "$wp_themed" "$wp_link"

      for profile in "${XDG_CONFIG_HOME}"/chromium/Default "${XDG_CONFIG_HOME}"/chromium/Profile\ *; do
        prefs="$profile/Preferences"
        [ -f "$prefs" ] || continue
        ${runAsUser} ${pkgs.python3}/bin/python "${configRoot}/chromium/seed_shortcuts.py" linux "$prefs"
      done
    '';
  };
}
