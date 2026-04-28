{
  pkgs,
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
    mkSymlink
    mkDir
    readTheme
    ;

  fzfThemes = pkgs.runCommand "fzf-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight << 'FZFMIDNIGHT'
    ${themeGenerators.mkFzfTheme palettes.midnight}
    FZFMIDNIGHT

    cat > $out/daylight << 'FZFDAYLIGHT'
    ${themeGenerators.mkFzfTheme palettes.daylight}
    FZFDAYLIGHT
  '';
in
{
  users.users.${username}.packages = [ pkgs.fzf ];

  environment.sessionVariables = {
    FZF_DEFAULT_OPTS_FILE = "${XDG_CONFIG_HOME}/fzf/themes/theme";
    FZF_DEFAULT_COMMAND = "rg --files --hidden";
    FZF_CTRL_T_COMMAND = "rg --files --hidden";
    FZF_ALT_C_COMMAND = "fd --type d --hidden";
  };

  system.activationScripts.fzfConfig.text = ''
    ${mkDir "${XDG_CONFIG_HOME}/fzf/themes"}

    ${mkSymlink "${fzfThemes}/midnight" "${XDG_CONFIG_HOME}/fzf/themes/midnight"}
    ${mkSymlink "${fzfThemes}/daylight" "${XDG_CONFIG_HOME}/fzf/themes/daylight"}

    ${readTheme}
    ${mkSymlink "${XDG_CONFIG_HOME}/fzf/themes/$theme" "${XDG_CONFIG_HOME}/fzf/themes/theme"}
  '';
}
