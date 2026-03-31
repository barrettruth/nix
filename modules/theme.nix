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
    s: offset:
    hexDigit (builtins.substring offset 1 s) * 16 + hexDigit (builtins.substring (offset + 1) 1 s);

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
    s: "${byteToFloat (hexByte s 1)} ${byteToFloat (hexByte s 3)} ${byteToFloat (hexByte s 5)}";

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
