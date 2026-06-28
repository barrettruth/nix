{
  pkgs,
  lib,
  palettes,
  themeGenerators,
  hostConfig,
  ...
}:
let
  helpers = import ../helpers.nix { inherit hostConfig pkgs; };
  inherit (helpers)
    XDG_CONFIG_HOME
    repo
    mkSymlink
    mkDir
    readTheme
    ;

  fuzzelThemes = pkgs.runCommand "fuzzel-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight.ini << 'FUZZELMIDNIGHT'
    ${themeGenerators.mkFuzzelTheme palettes.midnight}
    FUZZELMIDNIGHT

    cat > $out/daylight.ini << 'FUZZELDAYLIGHT'
    ${themeGenerators.mkFuzzelTheme palettes.daylight}
    FUZZELDAYLIGHT
  '';

  fuzzelConf = pkgs.writeText "fuzzel-wrapper" ''
    include=${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini
    include=${repo}/config/fuzzel/fuzzel.ini
  '';
in
{
  config = lib.mkIf hostConfig.enableWayland {
    users.users.${hostConfig.username}.packages = [ pkgs.fuzzel ];

    system.activationScripts.fuzzelConfig.text = ''
      ${mkDir "${XDG_CONFIG_HOME}/fuzzel/themes"}

      ${mkSymlink "${fuzzelThemes}/midnight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/midnight.ini"}
      ${mkSymlink "${fuzzelThemes}/daylight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/daylight.ini"}
      ${mkSymlink "${fuzzelConf}" "${XDG_CONFIG_HOME}/fuzzel/fuzzel.ini"}

      ${readTheme}
      ${mkSymlink "${XDG_CONFIG_HOME}/fuzzel/themes/$theme.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini"}
    '';
  };
}
