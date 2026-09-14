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
  policy = pkgs.writeShellApplication {
    name = "ivpn-policy";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = (builtins.readFile ../../scripts/ivpn-runtime.bash) + "\n" + (
      lib.replaceStrings
        [ "@ivpn@" "@state_dir@" "@exceptions@" "@auto_connect@" "@always_on@" "@bypass_file@" ]
        [
          (lib.escapeShellArg (
            if pkgs.stdenv.hostPlatform.isDarwin then
              "/Applications/IVPN.app/Contents/MacOS/cli/ivpn"
            else
              lib.getExe pkgs.ivpn
          ))
          (lib.escapeShellArg cfg.stateDirectory)
          (lib.escapeShellArg (lib.optionalString tailnet "100.64.0.0/10,fd7a:115c:a1e0::/48"))
          (lib.boolToString cfg.autoConnect)
          (lib.boolToString cfg.alwaysOn)
          (lib.escapeShellArg cfg.bypassFile)
        ]
        (builtins.readFile ../../scripts/ivpn-policy.bash)
    );
  };
in
{
  options.barrett.privacy = {
    enable = lib.mkEnableOption "IVPN with Quad9 encrypted DNS";
    autoConnect = lib.mkEnableOption "automatic IVPN connections on app and daemon startup";
    alwaysOn = lib.mkEnableOption "the persistent IVPN firewall, including when the VPN is disconnected";
    bypassFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = lib.optionalString (pkgs.stdenv.hostPlatform.isDarwin && cfg.alwaysOn) "/var/run/ivpn/bypass";
      description = "Root-owned expiry of an explicit temporary bypass; empty when unavailable.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "/Library/Application Support/IVPN"
        else
          "/etc/opt/ivpn/mutable";
      description = "IVPN's native mutable settings directory.";
    };
    policy = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = policy;
      description = "Apply host policy through IVPN's CLI without changing account credentials.";
    };
  };

  config = lib.mkIf cfg.enable {
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
