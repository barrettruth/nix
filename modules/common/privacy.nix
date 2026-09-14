{
  config,
  identity,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.barrett.privacy;
  tailnet = config.services.tailscale.enable;
  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = [ pkgs.jq ];
    text = lib.replaceStrings
      [ "@ivpn@" "@tailscale@" "@tailnet@" ]
      [
        (lib.escapeShellArg (
          if pkgs.stdenv.hostPlatform.isDarwin then
            "/Applications/IVPN.app/Contents/MacOS/cli/ivpn"
          else
            lib.getExe pkgs.ivpn
        ))
        (lib.escapeShellArg (lib.getExe config.services.tailscale.package))
        (lib.boolToString tailnet)
      ]
      (builtins.readFile ../../scripts/vpn.sh);
  };
in
{
  options.barrett.privacy.enable = lib.mkEnableOption "IVPN with Quad9 encrypted DNS";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ vpn ];

    services.dnscrypt-proxy = {
      enable = true;
      settings = {
        listen_addresses = [ "[::1]:53" ];
        server_names = [
          "quad9-primary"
          "quad9-secondary"
        ];
        dnscrypt_servers = false;
        doh_servers = true;
        require_dnssec = true;
        require_nolog = true;
        require_nofilter = false;
        ignore_system_dns = true;
        bootstrap_resolvers = [ ];
        netprobe_timeout = 0;
        static = {
          quad9-primary.stamp = "sdns://AgMAAAAAAAAABzkuOS45LjkADWRucy5xdWFkOS5uZXQKL2Rucy1xdWVyeQ";
          quad9-secondary.stamp = "sdns://AgMAAAAAAAAADzE0OS4xMTIuMTEyLjExMgANZG5zLnF1YWQ5Lm5ldAovZG5zLXF1ZXJ5";
        };
        forwarding_rules = lib.mkIf tailnet (
          pkgs.writeText "tailnet-dns-forwarding" ''
            ${identity.tailnetDomain} 100.100.100.100
          ''
        );
      };
    };
  };
}
