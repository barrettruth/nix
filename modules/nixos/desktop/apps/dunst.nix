{
  pkgs,
  lib,
  palettes,
  themeGenerators,
  hostConfig,
  ...
}:
let
  wayland = import ../wayland.nix { inherit pkgs hostConfig; };
  helpers = import ../helpers.nix { inherit hostConfig; };
  inherit (wayland)
    mkWaylandGate
    wrapWaylandExec
    ;
  inherit (helpers)
    username
    XDG_CONFIG_HOME
    repo
    mkSymlink
    mkDir
    readTheme
    ;

  waylandGate = mkWaylandGate "hyprland-session.target";

  dunstThemes = pkgs.runCommand "dunst-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.conf << 'DUNSTMIDNIGHT'
    ${themeGenerators.mkDunstTheme palettes.midnight}
    DUNSTMIDNIGHT

    cat > $out/daylight.conf << 'DUNSTDAYLIGHT'
    ${themeGenerators.mkDunstTheme palettes.daylight}
    DUNSTDAYLIGHT
  '';
in
{
  config = lib.mkIf hostConfig.enableWayland {
    users.users.${username}.packages = [ pkgs.dunst ];

    systemd.user.services.dunst = waylandGate // {
      description = "Dunst notification daemon";
      serviceConfig = waylandGate.serviceConfig // {
        ExecStart = wrapWaylandExec "${pkgs.dunst}/bin/dunst";
      };
    };

    system.activationScripts.dunstConfig.text = ''
      ${mkDir "${XDG_CONFIG_HOME}/dunst/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst/dunstrc.d"}

      ${mkSymlink "${dunstThemes}/midnight.conf" "${XDG_CONFIG_HOME}/dunst/themes/midnight.conf"}
      ${mkSymlink "${dunstThemes}/daylight.conf" "${XDG_CONFIG_HOME}/dunst/themes/daylight.conf"}
      ${mkSymlink "${repo}/config/dunst/dunstrc" "${XDG_CONFIG_HOME}/dunst/dunstrc"}

      ${readTheme}
      ${mkSymlink "${XDG_CONFIG_HOME}/dunst/themes/$theme.conf" "${XDG_CONFIG_HOME}/dunst/dunstrc.d/theme.conf"}
    '';
  };
}
