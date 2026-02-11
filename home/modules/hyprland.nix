{
  lib,
  config,
  isNixOS,
  ...
}:

let
  mkHyprTheme = palette: ''
    general {
        col.active_border = rgb(${builtins.substring 1 6 palette.fg})
        col.inactive_border = rgb(${builtins.substring 1 6 palette.bg})
    }
  '';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    portalPackage = lib.mkIf (!isNixOS) null;
    systemd.enable = isNixOS;

    extraConfig = ''
      source = $XDG_CONFIG_HOME/nix/config/hypr/hyprland.conf
    '';
  };

  xdg.configFile."hypr/themes/midnight.conf".text = mkHyprTheme config.palettes.midnight;
  xdg.configFile."hypr/themes/daylight.conf".text = mkHyprTheme config.palettes.daylight;
}
