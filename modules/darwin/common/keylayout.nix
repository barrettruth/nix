{ pkgs, ... }:
let
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
    ${pkgs.python3}/bin/python3 ${generator} <${xkbBaremak} >$out/Baremak.keylayout
  '';
in
{
  system.activationScripts.extraActivation.text = ''
    install -d -m 0755 "/Library/Keyboard Layouts"
    install -m 0644 ${baremakLayout}/Baremak.keylayout "/Library/Keyboard Layouts/Baremak.keylayout"
  '';
}
