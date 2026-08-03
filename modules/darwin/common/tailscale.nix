{
  config,
  identity,
  mkMacSecret,
  pkgs,
  ...
}:
let
  authKeyPath = config.sops.secrets."headscale-authkey".path;
in
{
  sops.secrets."headscale-authkey" = mkMacSecret "headscale-authkey" {
    mode = "0400";
  };

  services.tailscale = {
    enable = true;

    # Tailscaled on macOS registers split DNS for its own ts.net rather than
    # headscale's base_domain, so *.ts.barrettruth.com never reached
    # 100.100.100.100. Headscale already sets override_local_dns and global
    # nameservers, so it is safe to make it the sole resolver.
    overrideLocalDns = false;
  };

  environment.etc."resolver/ts.${identity.domain}".text = "nameserver 100.100.100.100";

  # nix-darwin's tailscaled daemon sets RunAtLoad but not KeepAlive. With
  # overrideLocalDns it is the only resolver, so a crash would take all name
  # resolution with it until someone noticed.
  launchd.daemons.tailscaled.serviceConfig.KeepAlive = true;

  # networking.dns is applied per entry in knownNetworkServices, so without
  # this the resolver is never actually set and the option silently does
  # nothing.
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
          Running) exit 0 ;;
          NeedsLogin|Stopped) break ;;
        esac
        sleep 1
      done

      for _ in $(seq 1 10); do
        ${pkgs.tailscale}/bin/tailscale up \
          --login-server "https://headscale.${identity.domain}" \
          --auth-key "file:${authKeyPath}" && exit 0
        sleep 15
      done

      exit 1
    '';
  };
}
