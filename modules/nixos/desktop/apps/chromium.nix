{
  pkgs,
  lib,
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
    ;

  chromiumThemeCss = pkgs.writeText "chromium-theme.css" themeGenerators.mkChromeThemeCss;
  chromiumThemeJs = pkgs.writeText "chromium-theme.js" themeGenerators.mkChromeThemeJs;
in
{
  config = lib.mkIf hostConfig.enableDesktop {
    users.users.${username}.packages = [
      (pkgs.chromium.override {
        commandLineArgs = "--silent-debugger-extension-api";
      })
    ];

    system.activationScripts.chromiumConfig.text = ''
      ${mkSymlink "${chromiumThemeCss}" "${repo}/config/chromium/extension/theme.css"}
      ${mkSymlink "${chromiumThemeJs}" "${repo}/config/chromium/extension/theme.js"}

      for profile in "${XDG_CONFIG_HOME}"/chromium/Default "${XDG_CONFIG_HOME}"/chromium/Profile\ *; do
        prefs="$profile/Preferences"
        [ -f "$prefs" ] || continue
        ${pkgs.python3}/bin/python "${repo}/config/chromium/seed_shortcuts.py" "$prefs"
        chown ${username}:users "$prefs"
      done
    '';
  };
}
