{ pkgs, config, ... }:

let
  c = config.colors;
in
{
  home.sessionVariables = {
    TERMINAL = "ghostty";
    TERM = "xterm-ghostty";
    TERMINFO = "${config.xdg.dataHome}/terminfo";
  };

  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "Berkeley Mono";
      font-codepoint-map = "U+f101-U+f25c=nonicons";
      font-feature = "-calt";
      font-size = 20;
      adjust-cell-height = "10%";

      theme = "dark:midnight,light:daylight";

      cursor-style-blink = false;
      shell-integration-features = "no-cursor";

      window-decoration = false;
      window-padding-x = 0;
      window-padding-y = 0;
      window-padding-color = "background";
      app-notifications = "no-clipboard-copy,no-config-reload";
      resize-overlay = "never";
      mouse-scroll-multiplier = 0.5;
      quit-after-last-window-closed = true;
      confirm-close-surface = false;

      keybind = [
        "clear"
        "alt+r=reload_config"
        "alt+y=copy_to_clipboard"
        "alt+p=paste_from_clipboard"
        "alt+shift+h=decrease_font_size:1"
        "alt+shift+l=increase_font_size:1"
        "shift+enter=text:\\n"
      ];
    };
  };

  xdg.configFile."ghostty/themes/midnight".text = ''
    palette = 0=#121212
    palette = 1=#ff6b6b
    palette = 2=#98c379
    palette = 3=#e5c07b
    palette = 4=#7aa2f7
    palette = 5=#c678dd
    palette = 6=#56b6c2
    palette = 7=#e0e0e0
    palette = 8=#666666
    palette = 9=#f48771
    palette = 10=#b5e890
    palette = 11=#f0d197
    palette = 12=#9db8f7
    palette = 13=#e298ff
    palette = 14=#7dd6e0
    palette = 15=#ffffff
    background = #121212
    foreground = #e0e0e0
    cursor-color = #ff6b6b
    cursor-text = #121212
    selection-background = #2d2d2d
    selection-foreground = #e0e0e0
  '';

  xdg.configFile."ghostty/themes/daylight".text = ''
    palette = 0=#f5f5f5
    palette = 1=#c7254e
    palette = 2=#2d7f3e
    palette = 3=#996800
    palette = 4=#3b5bdb
    palette = 5=#ae3ec9
    palette = 6=#1098ad
    palette = 7=#1a1a1a
    palette = 8=#999999
    palette = 9=#e03e52
    palette = 10=#37b24d
    palette = 11=#f59f00
    palette = 12=#4c6ef5
    palette = 13=#da77f2
    palette = 14=#15aabf
    palette = 15=#000000
    background = #f5f5f5
    foreground = #1a1a1a
    cursor-color = #e03e52
    cursor-text = #f5f5f5
    selection-background = #ebebeb
    selection-foreground = #1a1a1a
  '';
}
