{
  pkgs,
  lib,
  themeGenerators,
  hostConfig,
  ...
}:
let
  helpers = import ../helpers.nix { inherit hostConfig pkgs; };
  inherit (helpers)
    username
    XDG_CONFIG_HOME
    repo
    runUser
    mkSymlink
    ;

  chromiumThemeCss = pkgs.writeText "chromium-theme.css" themeGenerators.mkChromeThemeCss;
  chromiumThemeJs = pkgs.writeText "chromium-theme.js" themeGenerators.mkChromeThemeJs;

  chromiumArgs = [
    "--ozone-platform=wayland"
    "--silent-debugger-extension-api"
    "--enable-features=AcceleratedVideoDecodeLinuxZeroCopyGL"
  ];

  chromiumBase = pkgs.chromium.override {
    commandLineArgs = lib.concatStringsSep " " chromiumArgs;
  };

  chromium = pkgs.symlinkJoin {
    name = chromiumBase.name;
    paths = [ chromiumBase ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/chromium" \
        --set __NV_PRIME_RENDER_OFFLOAD 1 \
        --set __NV_PRIME_RENDER_OFFLOAD_PROVIDER NVIDIA-G0 \
        --set __GLX_VENDOR_LIBRARY_NAME nvidia \
        --set __VK_LAYER_NV_optimus NVIDIA_only
    '';
  };
in
{
  config = lib.mkIf hostConfig.enableDesktop {
    users.users.${username}.packages = [ chromium ];

    system.activationScripts.chromiumConfig.text = ''
      ${mkSymlink "${chromiumThemeCss}" "${repo}/config/chromium/extension/theme.css"}
      ${mkSymlink "${chromiumThemeJs}" "${repo}/config/chromium/extension/theme.js"}

      for profile in "${XDG_CONFIG_HOME}"/chromium/Default "${XDG_CONFIG_HOME}"/chromium/Profile\ *; do
        prefs="$profile/Preferences"
        [ -f "$prefs" ] || continue
        ${runUser} ${pkgs.python3}/bin/python "${repo}/config/chromium/seed_shortcuts.py" "$prefs"
      done
    '';
  };
}
