{ lib, ... }:
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

  hex = color: builtins.substring 1 6 color;

  hexToFuzzel = color: "${builtins.substring 1 6 color}ff";

  mkFzfTheme = palette: ''
    --color=fg:${palette.fg},bg:${palette.bg},hl:${palette.accent}
    --color=fg+:${palette.fg},bg+:${palette.bgAlt},hl+:${palette.accent}
    --color=info:${palette.green},prompt:${palette.accent},pointer:${palette.fg},marker:${palette.green},spinner:${palette.fg}
  '';

  mkHyprTheme = palette: ''
    general {
        col.active_border = rgb(${hex palette.fg})
        col.inactive_border = rgb(${hex palette.bg})
    }
  '';

  mkWaybarTheme = palette: ''
    * { color: ${palette.fg}; }
    window#waybar { background: ${palette.bg}; border-bottom: 2px solid ${palette.bgAlt}; }
    #workspaces button { background: transparent; }
    #workspaces button.active { box-shadow: inset 0 2px ${palette.accent}; }
    #workspaces button:hover { background: ${palette.bgAlt}; }
    #window { color: ${palette.fgAlt}; }
    tooltip { background: ${palette.bgAlt}; color: ${palette.fg}; border: 1px solid ${palette.border}; }
  '';

  mkFuzzelTheme = palette: ''
    [colors]
    background=${hexToFuzzel palette.bg}
    text=${hexToFuzzel palette.fg}
    prompt=${hexToFuzzel palette.fgAlt}
    placeholder=${hexToFuzzel palette.fgAlt}
    input=${hexToFuzzel palette.fg}
    match=${hexToFuzzel palette.accent}
    selection=${hexToFuzzel palette.bgAlt}
    selection-text=${hexToFuzzel palette.fg}
    selection-match=${hexToFuzzel palette.accent}
    border=${hexToFuzzel palette.border}
    counter=${hexToFuzzel palette.fgAlt}
  '';

  mkDunstTheme = palette: ''
    [global]
    frame_color = "${palette.border}"
    separator_color = "frame"
    background = "${palette.bg}"
    foreground = "${palette.fg}"

    [urgency_low]
    background = "${palette.bg}"
    foreground = "${palette.fg}"
    frame_color = "${palette.border}"

    [urgency_normal]
    background = "${palette.bg}"
    foreground = "${palette.fg}"
    frame_color = "${palette.border}"

    [urgency_critical]
    background = "${palette.bg}"
    foreground = "${palette.red}"
    frame_color = "${palette.red}"
  '';

in
{
  _module.args = {
    inherit palettes;
    themeGenerators = {
      inherit
        mkFzfTheme
        mkHyprTheme
        mkWaybarTheme
        mkFuzzelTheme
        mkDunstTheme
        ;
    };
  };
}
