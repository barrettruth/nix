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

  services.tailscale.enable = true;

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

      exec ${pkgs.tailscale}/bin/tailscale up \
        --login-server "https://headscale.${identity.domain}" \
        --auth-key "file:${authKeyPath}"
    '';
  };
}
