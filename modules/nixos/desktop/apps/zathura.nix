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

  zathuraThemes = pkgs.runCommand "zathura-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight << 'ZATHURAMIDNIGHT'
    ${themeGenerators.mkZathuraTheme palettes.midnight}
    ZATHURAMIDNIGHT

    cat > $out/daylight << 'ZATHURADAYLIGHT'
    ${themeGenerators.mkZathuraTheme palettes.daylight}
    ZATHURADAYLIGHT
  '';
in
{
  config = lib.mkIf hostConfig.enableDesktop {
    users.users.${username}.packages = [ pkgs.zathura ];

    system.activationScripts.zathuraConfig.text = ''
      ${mkDir "${XDG_CONFIG_HOME}/zathura/themes"}

      ${mkSymlink "${zathuraThemes}/midnight" "${XDG_CONFIG_HOME}/zathura/themes/midnight"}
      ${mkSymlink "${zathuraThemes}/daylight" "${XDG_CONFIG_HOME}/zathura/themes/daylight"}
      ${mkSymlink "${repo}/config/zathura/zathurarc" "${XDG_CONFIG_HOME}/zathura/zathurarc"}

      ${readTheme}
      ${mkSymlink "${XDG_CONFIG_HOME}/zathura/themes/$theme" "${XDG_CONFIG_HOME}/zathura/theme"}
    '';
  };
}
