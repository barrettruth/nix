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
      zathuraHighlightColor = "rgba(122,162,247,0.369701)";
      zathuraHighlightActiveColor = "rgba(152,195,121,0.325217)";
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
      zathuraHighlightColor = "rgba(59,91,219,0.544157)";
      zathuraHighlightActiveColor = "rgba(45,127,62,0.588445)";
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

  colorChannel = color: offset: lib.fromHexString (builtins.substring offset 2 color);

  formatColorChannel =
    value:
    let
      hexValue = lib.toHexString value;
    in
    if builtins.stringLength hexValue == 1 then "0${hexValue}" else hexValue;

  blendColor =
    foreground: background: opacity:
    let
      blendChannel =
        offset:
        builtins.div (
          colorChannel foreground offset * opacity + colorChannel background offset * (100 - opacity)
        ) 100;
    in
    "#${formatColorChannel (blendChannel 1)}${formatColorChannel (blendChannel 3)}${formatColorChannel (blendChannel 5)}";

  mkCodexScope =
    {
      name,
      scope,
      foreground,
      background ? null,
      fontStyle ? null,
    }:
    ''
      <dict>
        <key>name</key>
        <string>${name}</string>
        <key>scope</key>
        <string>${scope}</string>
        <key>settings</key>
        <dict>
          <key>foreground</key>
          <string>${foreground}</string>
          ${lib.optionalString (background != null) ''
            <key>background</key>
            <string>${background}</string>
          ''}
          ${lib.optionalString (fontStyle != null) ''
            <key>fontStyle</key>
            <string>${fontStyle}</string>
          ''}
        </dict>
      </dict>
    '';

  mkCodexTheme =
    {
      name,
      background,
      foreground,
      muted,
      red,
      green,
      yellow,
      blue,
      diffBackgrounds ? null,
    }:
    let
      scopes = [
        {
          name = "Comments";
          scope = "comment, punctuation.definition.comment";
          foreground = muted;
        }
        {
          name = "Keywords";
          scope = "keyword, storage.modifier, meta.preprocessor";
          foreground = blue;
        }
        {
          name = "Strings";
          scope = "string, constant.character";
          foreground = green;
        }
        {
          name = "Constants";
          scope = "constant, constant.numeric, constant.language, support.constant";
          foreground = green;
        }
        {
          name = "Code";
          scope = "entity.name, entity.other.attribute-name, support.function, support.type, variable, keyword.operator, storage.type, punctuation";
          inherit foreground;
        }
        {
          name = "Headings";
          scope = "markup.heading, entity.name.section";
          inherit foreground;
          fontStyle = "bold";
        }
        {
          name = "Emphasis";
          scope = "markup.italic";
          inherit foreground;
          fontStyle = "italic";
        }
        {
          name = "Strong";
          scope = "markup.bold";
          inherit foreground;
          fontStyle = "bold";
        }
        {
          name = "Links";
          scope = "markup.underline.link, string.other.link";
          inherit foreground;
          fontStyle = "underline";
        }
        {
          name = "Notes";
          scope = "keyword.other.note";
          foreground = blue;
          fontStyle = "bold italic";
        }
        {
          name = "Warnings";
          scope = "keyword.other.todo, keyword.other.fixme, keyword.other.warning";
          foreground = yellow;
          fontStyle = "bold italic";
        }
        {
          name = "Invalid";
          scope = "invalid, invalid.illegal";
          foreground = red;
        }
        {
          name = "Inserted";
          scope = "markup.inserted, diff.inserted";
          foreground = green;
          background = if diffBackgrounds == null then null else diffBackgrounds.added;
        }
        {
          name = "Deleted";
          scope = "markup.deleted, diff.deleted";
          foreground = red;
          background = if diffBackgrounds == null then null else diffBackgrounds.deleted;
        }
        {
          name = "Changed";
          scope = "markup.changed, diff.changed, meta.diff.header";
          foreground = blue;
          background = if diffBackgrounds == null then null else diffBackgrounds.changed;
        }
      ];
    in
    ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>name</key>
        <string>${name}</string>
        <key>settings</key>
        <array>
          <dict>
            <key>settings</key>
            <dict>
              <key>background</key>
              <string>${background}</string>
              <key>foreground</key>
              <string>${foreground}</string>
            </dict>
          </dict>
          ${lib.concatMapStrings mkCodexScope scopes}
        </array>
      </dict>
      </plist>
    '';

  mkCodexPaletteTheme =
    name: palette:
    mkCodexTheme {
      inherit name;
      inherit (palette)
        red
        green
        yellow
        blue
        ;
      background = palette.bg;
      foreground = palette.fg;
      muted = palette.fgAlt;
      diffBackgrounds = {
        added = blendColor palette.green palette.bg 40;
        deleted = blendColor palette.red palette.bg 40;
        changed = blendColor palette.blue palette.bg 40;
      };
    };

  mkCodexAnsiTheme =
    name:
    mkCodexTheme {
      inherit name;
      # Codex interprets the alpha byte as an ANSI palette selector. Palette
      # indices follow Ghostty as it switches between Midnight and Daylight.
      background = "#00000001";
      foreground = "#00000001";
      muted = "#08000000";
      red = "#01000000";
      green = "#02000000";
      yellow = "#03000000";
      blue = "#04000000";
    };

  mkFzfTheme = palette: ''
    --color=fg:${palette.fg},bg:${palette.bg},hl:${palette.accent}
    --color=fg+:${palette.fg},bg+:${palette.bgAlt},hl+:${palette.accent}
    --color=info:${palette.green},prompt:${palette.accent},pointer:${palette.fg},marker:${palette.green},spinner:${palette.fg}
  '';

  mkHyprTheme = palette: ''
    hl.config({
        general = {
            col = {
                active_border = "rgb(${hex palette.fg})",
                inactive_border = "rgb(${hex palette.bg})",
            },
        },
    })
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

  mkZathuraTheme = palette: ''
    set default-bg "${palette.bg}"
    set default-fg "${palette.fg}"
    set statusbar-bg "${palette.bg}"
    set statusbar-fg "${palette.fg}"
    set inputbar-bg "${palette.bg}"
    set inputbar-fg "${palette.fg}"
    set notification-bg "${palette.bg}"
    set notification-fg "${palette.fg}"
    set notification-error-bg "${palette.bg}"
    set notification-error-fg "${palette.red}"
    set notification-warning-bg "${palette.bg}"
    set notification-warning-fg "${palette.yellow}"
    set highlight-color "${palette.zathuraHighlightColor}"
    set highlight-active-color "${palette.zathuraHighlightActiveColor}"
    set completion-bg "${palette.bgAlt}"
    set completion-fg "${palette.fg}"
    set completion-highlight-bg "${palette.accent}"
    set completion-highlight-fg "${palette.bg}"
    set recolor-darkcolor "${palette.fg}"
    set recolor-lightcolor "${palette.bg}"
    set render-loading-bg "${palette.bg}"
    set render-loading-fg "${palette.fg}"
    set index-bg "${palette.bg}"
    set index-fg "${palette.fg}"
    set index-active-bg "${palette.bgAlt}"
    set index-active-fg "${palette.fg}"
  '';

  mkChromeThemeCss =
    let
      m = palettes.midnight;
      d = palettes.daylight;
    in
    ''
      :root {
        --bg: ${d.bg}; --fg: ${d.fg}; --bg-alt: ${d.bgAlt}; --fg-alt: ${d.fgAlt};
        --border: ${d.border}; --accent: ${d.accent};
        --green: ${d.green}; --red: ${d.red}; --yellow: ${d.yellow};
        --blue: ${d.blue}; --magenta: ${d.magenta}; --cyan: ${d.cyan};
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --bg: ${m.bg}; --fg: ${m.fg}; --bg-alt: ${m.bgAlt}; --fg-alt: ${m.fgAlt};
          --border: ${m.border}; --accent: ${m.accent};
          --green: ${m.green}; --red: ${m.red}; --yellow: ${m.yellow};
          --blue: ${m.blue}; --magenta: ${m.magenta}; --cyan: ${m.cyan};
        }
      }
      html, body { margin: 0; background: var(--bg); color: var(--fg); min-height: 100vh; }
    '';

  mkChromeThemeJs = ''
    var MIDNIGHT = ${builtins.toJSON palettes.midnight};
    var DAYLIGHT = ${builtins.toJSON palettes.daylight};
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
        mkZathuraTheme
        mkChromeThemeCss
        mkChromeThemeJs
        mkCodexPaletteTheme
        mkCodexAnsiTheme
        ;
    };
  };
}
