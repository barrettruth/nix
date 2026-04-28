{
  pkgs,
  lib,
  palettes,
  themeGenerators,
  hostConfig,
  ...
}:
let
  helpers = import ../helpers.nix { inherit hostConfig; };
  inherit (helpers)
    username
    XDG_CONFIG_HOME
    repo
    mkSymlink
    mkDir
    readTheme
    ;

  waybarThemes = pkgs.runCommand "waybar-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.css << 'WAYBARMIDNIGHT'
    ${themeGenerators.mkWaybarTheme palettes.midnight}
    WAYBARMIDNIGHT

    cat > $out/daylight.css << 'WAYBARDAYLIGHT'
    ${themeGenerators.mkWaybarTheme palettes.daylight}
    WAYBARDAYLIGHT
  '';
in
{
  config = lib.mkIf hostConfig.enableWayland {
    users.users.${username}.packages = [ pkgs.waybar ];

    system.activationScripts.waybarConfig.text = ''
      ${mkDir "${XDG_CONFIG_HOME}/waybar/themes"}

      ${mkSymlink "${waybarThemes}/midnight.css" "${XDG_CONFIG_HOME}/waybar/themes/midnight.css"}
      ${mkSymlink "${waybarThemes}/daylight.css" "${XDG_CONFIG_HOME}/waybar/themes/daylight.css"}
      ${mkSymlink "${repo}/config/waybar/config.jsonc" "${XDG_CONFIG_HOME}/waybar/config"}
      ${mkSymlink "${repo}/config/waybar/style.css" "${XDG_CONFIG_HOME}/waybar/style.css"}

      ${readTheme}
      ${mkSymlink "${XDG_CONFIG_HOME}/waybar/themes/$theme.css" "${XDG_CONFIG_HOME}/waybar/themes/theme.css"}
    '';
  };
}
