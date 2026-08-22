{
  config,
  identity,
  lib,
  mkHostSecret,
  pkgs,
  ...
}:
let
  cfg = config.barrett.tailscale;
  loginServer = "https://headscale.${identity.domain}";
  authKeyPath = lib.optionalString cfg.useAuthKey config.sops.secrets."headscale-authkey".path;
  shieldsFlag = lib.optionalString cfg.shieldsUp " --shields-up";
  applyShields = lib.optionalString cfg.shieldsUp ''
    ${pkgs.tailscale}/bin/tailscale set --shields-up=true || true
  '';
  login =
    if cfg.useAuthKey then
      ''
        for _ in $(seq 1 10); do
          ${pkgs.tailscale}/bin/tailscale up \
            --login-server "${loginServer}" \
            --auth-key "file:${authKeyPath}"${shieldsFlag} && exit 0
          sleep 15
        done
      ''
    else
      ''
        echo "tailscaled is not logged in; run: tailscale up --login-server ${loginServer}${shieldsFlag}" >&2
      '';
in
{
  options.barrett.tailscale = {
    shieldsUp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Drop all inbound tailnet connections, leaving the node outbound-only.";
    };

    useAuthKey = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Register with a headscale preauth key rather than an interactive OIDC login.";
    };
  };

  config = {
    sops.secrets = lib.mkIf cfg.useAuthKey {
      "headscale-authkey" = mkHostSecret config.networking.hostName "headscale-authkey" {
        mode = "0400";
      };
    };

    services.tailscale = {
      enable = true;

      overrideLocalDns = false;
    };

    environment.etc."resolver/${identity.tailnetDomain}".text = "nameserver 100.100.100.100";

    launchd.daemons.tailscaled.serviceConfig.KeepAlive = true;

    networking.knownNetworkServices = [
      "Wi-Fi"
      "Thunderbolt Bridge"
    ];

    launchd.daemons.tailscaled-autoconnect = {
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = false;
        StandardErrorPath = "/var/log/tailscaled-autoconnect.log";
        StandardOutPath = "/var/log/tailscaled-autoconnect.log";
      };
      script = ''
        set -eu

        for _ in $(seq 1 60); do
          state=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
            | ${pkgs.jq}/bin/jq -r '.BackendState // empty') || state=""
          case "$state" in
            Running)
              ${applyShields}
              exit 0
              ;;
            NeedsLogin|Stopped) break ;;
          esac
          sleep 1
        done

        ${login}
        exit 1
      '';
    };
  };
}
