{ pkgs, ... }:
let
  layoutName = "Baremak";
  layoutId = -19001;

  xkbBaremak = builtins.path {
    path = ../../../config/xkb/baremak;
    name = "xkb-baremak";
  };

  generator = builtins.path {
    path = ./baremak.py;
    name = "baremak-keylayout";
  };

  baremakLayout = pkgs.runCommand "baremak-keylayout" { } ''
    mkdir -p $out
    ${pkgs.python3}/bin/python3 ${generator} ${toString layoutId} ${layoutName} \
      <${xkbBaremak} >$out/${layoutName}.keylayout
  '';
in
{
  system.activationScripts.extraActivation.text = ''
    install -d -m 0755 "/Library/Keyboard Layouts"
    install -m 0644 ${baremakLayout}/${layoutName}.keylayout "/Library/Keyboard Layouts/${layoutName}.keylayout"
  '';

  system.defaults.CustomUserPreferences."com.apple.HIToolbox".AppleEnabledInputSources = [
    {
      InputSourceKind = "Keyboard Layout";
      "KeyboardLayout ID" = 0;
      "KeyboardLayout Name" = "U.S.";
    }
    {
      InputSourceKind = "Non Keyboard Input Method";
      "Bundle ID" = "com.apple.CharacterPaletteIM";
    }
    {
      InputSourceKind = "Keyboard Layout";
      "KeyboardLayout ID" = layoutId;
      "KeyboardLayout Name" = layoutName;
    }
  ];
}
