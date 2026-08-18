{ config, lib, ... }:
let
  experimentalFeatures = [
    "nix-command"
    "flakes"
  ];
  inherit (config.barrett.mac) determinateInstalled;
in
{
  options.barrett.mac.determinateInstalled = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether the Determinate installer's Nix is installed on this mac.
      nix-darwin aborts activation when it finds one while it is still set to
      manage Nix, so such a host leaves nix.enable off and reaches the daemon
      through determinateNix, where nix.settings would be silently dropped.
    '';
  };

  config = lib.mkMerge [
    {
      determinateNix.enable = determinateInstalled;
      nix.enable = !determinateInstalled;
    }
    (lib.mkIf determinateInstalled {
      determinateNix.customSettings.experimental-features = experimentalFeatures;
    })
    (lib.mkIf (!determinateInstalled) {
      nix.settings.experimental-features = experimentalFeatures;
    })
  ];
}
