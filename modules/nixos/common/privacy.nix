{
  config,
  identity,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../../common/privacy.nix ];

  config = lib.mkIf config.barrett.privacy.enable {
    assertions = [
      {
        assertion = config.networking.enableIPv6;
        message = "Quad9's local DNS proxy requires IPv6 loopback (::1).";
      }
    ];

    services.ivpn.enable = true;
    environment.systemPackages = lib.optional config.barrett.ui.enable pkgs.ivpn-ui;
    systemd.services.ivpn-service = {
      requires = [ "systemd-resolved.service" ];
      after = [ "dnscrypt-proxy.service" ];
      path = [ config.systemd.package ];
      serviceConfig.ExecStart = lib.mkForce "${lib.getExe pkgs.ivpn-service}";
    };

    services.dnscrypt-proxy.upstreamDefaults = false;
    networking.nameservers = [ "::1" ];
    services.resolved = {
      enable = true;
      settings.Resolve = {
        FallbackDNS = [ ];
        Domains = [ "~." ] ++ lib.optional config.services.tailscale.enable identity.tailnetDomain;
        LLMNR = false;
      };
    };

    networking.wireless.iwd.settings.Network.NameResolvingService = lib.mkForce "systemd";
    services.tailscale.extraSetFlags = [ "--accept-dns=false" ];
  };
}
