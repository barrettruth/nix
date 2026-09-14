{
  config,
  identity,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.barrett.privacy;
in
{
  imports = [ ../../common/privacy.nix ];

  config = lib.mkIf cfg.enable {
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

    systemd.tmpfiles.rules = [ "d ${cfg.stateDirectory} - - - -" ];
    systemd.paths.ivpn-policy = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = [
        cfg.stateDirectory
        "${cfg.stateDirectory}/port.txt"
        "${cfg.stateDirectory}/settings.json"
      ];
    };
    systemd.services.ivpn-policy = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "ivpn-service.service" ];
      after = [ "ivpn-service.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe cfg.policy;
      };
    };
    systemd.user.services.ivpn-ui = lib.mkIf config.barrett.ui.enable {
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.ivpn-ui;
        Restart = "on-failure";
        RestartSec = 5;
      };
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
    services.tailscale = {
      extraUpFlags = [ "--accept-dns=false" ];
      extraSetFlags = [ "--accept-dns=false" ];
    };
  };
}
