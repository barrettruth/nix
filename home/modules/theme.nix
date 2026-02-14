{
  lib,
  config,
  pkgs,
  hostConfig,
  ...
}:

let
  palettes = {
    midnight = {
      bg = "#121212";
      fg = "#e0e0e0";
      bgAlt = "#2d2d2d";
      fgAlt = "#666666";
      border = "#3d3d3d";
      accent = "#7aa2f7";
      green = "#98c379";
      red = "#ff6b6b";
      yellow = "#e5c07b";
      blue = "#7aa2f7";
      magenta = "#c678dd";
      cyan = "#56b6c2";
      bellFg = "#ff6b6b";
      activityFg = "#7aa2f7";
    };
    daylight = {
      bg = "#f5f5f5";
      fg = "#1a1a1a";
      bgAlt = "#ebebeb";
      fgAlt = "#999999";
      border = "#e8e8e8";
      accent = "#3b5bdb";
      green = "#2d7f3e";
      red = "#c7254e";
      yellow = "#996800";
      blue = "#3b5bdb";
      magenta = "#ae3ec9";
      cyan = "#1098ad";
      bellFg = "#c7254e";
      activityFg = "#3b5bdb";
    };
  };
  mkFzfTheme = palette: ''
    --color=fg:${palette.fg},bg:${palette.bg},hl:${palette.accent}
    --color=fg+:${palette.fg},bg+:${palette.bgAlt},hl+:${palette.accent}
    --color=info:${palette.green},prompt:${palette.accent},pointer:${palette.fg},marker:${palette.green},spinner:${palette.fg}
  '';
in
{
  options.theme = lib.mkOption {
    type = lib.types.enum [
      "midnight"
      "daylight"
    ];
    default = "midnight";
  };

  options.palettes = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
    readOnly = true;
  };

  options.colors = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
  };

  config = {
    palettes = palettes;
    colors = palettes.${config.theme};

    home.pointerCursor = lib.mkIf hostConfig.isLinux {
      name = "macOS";
      package = pkgs.apple-cursor;
      size = 24;
      gtk.enable = true;
      x11.enable = false;
    };

    gtk = lib.mkIf hostConfig.isLinux {
      enable = true;
      font = {
        name = "SF Pro Display";
        size = 11;
      };
    };

    home.file.".local/share/fonts" = lib.mkIf hostConfig.isLinux {
      source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/fonts";
    };

    home.activation.checkFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${config.home.homeDirectory}/.config/nix/fonts" ] || \
         [ -z "$(ls -A "${config.home.homeDirectory}/.config/nix/fonts" 2>/dev/null)" ]; then
        echo "WARNING: ~/.config/nix/fonts is missing or empty — fonts will not be available"
        echo "         copy your fonts into ~/.config/nix/fonts/ and rebuild"
      fi
    '';

    xdg.configFile."fzf/themes/midnight".text = mkFzfTheme palettes.midnight;
    xdg.configFile."fzf/themes/daylight".text = mkFzfTheme palettes.daylight;

    home.activation.linkTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cfg="${config.xdg.configHome}"
      theme="${config.theme}"
      ${lib.optionalString hostConfig.isLinux ''
        $DRY_RUN_CMD ln -sf "$cfg/hypr/themes/$theme.conf" "$cfg/hypr/themes/theme.conf"
        $DRY_RUN_CMD ln -sf "$cfg/waybar/themes/$theme.css" "$cfg/waybar/themes/theme.css"
        $DRY_RUN_CMD ln -sf "$cfg/rofi/themes/$theme.rasi" "$cfg/rofi/themes/theme.rasi"
        $DRY_RUN_CMD ln -sf "$cfg/fuzzel/themes/$theme.ini" "$cfg/fuzzel/themes/theme.ini"
      ''}
      $DRY_RUN_CMD ln -sf "$cfg/sioyek/themes/$theme.config" "$cfg/sioyek/themes/theme.config"
      $DRY_RUN_CMD ln -sf "$cfg/fzf/themes/$theme" "$cfg/fzf/themes/theme"
    '';
  };
}
