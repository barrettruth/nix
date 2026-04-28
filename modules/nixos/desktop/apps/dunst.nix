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

  waylandGate = {
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 60); do [ -S \"$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY\" ] && exit 0; sleep 0.5; done; exit 1'";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

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
        ExecStart = "${pkgs.dunst}/bin/dunst";
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
