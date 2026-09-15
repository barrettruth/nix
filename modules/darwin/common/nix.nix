{ config, lib, ... }:
let
  daemonConfigFiles = lib.filter (
    file:
    file.enable
    && builtins.elem file.target [
      "nix/nix.conf"
      "nix/machines"
    ]
  ) (builtins.attrValues config.environment.etc);
in
{
  imports = [ ../../common/direnv.nix ];

  nix = {
    enable = true;
    channel.enable = false;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [ "https://nix-community.cachix.org" ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  launchd.daemons.nix-daemon.environment.NIX_DAEMON_RESTART_TRIGGERS = map (
    file: toString file.source
  ) daemonConfigFiles;

  system.activationScripts.nix-daemon.text = lib.mkForce ''
    if [[ -e /etc/nix/nix.custom.conf ]]; then
      mv /etc/nix/nix.custom.conf{,.before-nix-darwin}
    fi
  '';
}
