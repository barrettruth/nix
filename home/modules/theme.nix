{
  lib,
  config,
  pkgs,
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

    home.pointerCursor = {
      name = "macOS";
      package = pkgs.apple-cursor;
      size = 24;
      gtk.enable = true;
      x11.enable = false;
    };

    home.file.".local/share/fonts".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/fonts";

    home.activation.checkFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${config.home.homeDirectory}/.config/nix/fonts" ] || \
         [ -z "$(ls -A "${config.home.homeDirectory}/.config/nix/fonts" 2>/dev/null)" ]; then
        echo "WARNING: ~/.config/nix/fonts is missing or empty — fonts will not be available"
        echo "         copy your fonts into ~/.config/nix/fonts/ and rebuild"
      fi
    '';

    home.activation.linkTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cfg="${config.xdg.configHome}"
      theme="${config.theme}"
      $DRY_RUN_CMD ln -sf "$cfg/hypr/themes/$theme.conf" "$cfg/hypr/themes/theme.conf"
      $DRY_RUN_CMD ln -sf "$cfg/waybar/themes/$theme.css" "$cfg/waybar/themes/theme.css"
      $DRY_RUN_CMD ln -sf "$cfg/rofi/themes/$theme.rasi" "$cfg/rofi/themes/theme.rasi"
      $DRY_RUN_CMD ln -sf "$cfg/sioyek/themes/$theme.config" "$cfg/sioyek/themes/theme.config"
    '';
  };
}
