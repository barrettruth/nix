{
  config,
  pkgs,
  lib,
  identity,
  mkDesktopSecret,
  ...
}:
let
  hasVercelToken = builtins.pathExists ../../secrets/desktop/vercel-dns-token;
  ddnsNames = [
    "forge"
    "git"
  ];
  vercelDdns = pkgs.writeShellApplication {
    name = "vercel-ddns";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      token="$(cat "$CREDENTIALS_DIRECTORY/token")"
      domain="${identity.domain}"
      ip="$(curl -fsS --max-time 15 https://api.ipify.org)"
      if [ -z "$ip" ]; then
        echo "could not determine public IP" >&2
        exit 1
      fi
      records="$(curl -fsS --max-time 15 -H "Authorization: Bearer $token" \
        "https://api.vercel.com/v4/domains/$domain/records")"
      for name in ${lib.concatStringsSep " " ddnsNames}; do
        row="$(printf '%s' "$records" \
          | jq -r --arg n "$name" '.records[] | select(.name==$n and .type=="A") | "\(.id)\t\(.value)"' \
          | head -n1)"
        id="$(printf '%s' "$row" | cut -f1)"
        cur="$(printf '%s' "$row" | cut -f2)"
        if [ -z "$id" ]; then
          echo "no A record for $name.$domain; skipping" >&2
          continue
        fi
        if [ "$cur" = "$ip" ]; then
          echo "$name.$domain already $ip"
          continue
        fi
        echo "updating $name.$domain: $cur -> $ip"
        curl -fsS --max-time 15 -X PATCH \
          -H "Authorization: Bearer $token" \
          -H "Content-Type: application/json" \
          -d "{\"value\":\"$ip\"}" \
          "https://api.vercel.com/v1/domains/records/$id" >/dev/null
      done
    '';
  };
in
lib.mkIf hasVercelToken {
  sops.secrets."vercel-dns-token" = mkDesktopSecret "vercel-dns-token" {
    mode = "0400";
    restartUnits = [ "vercel-ddns.service" ];
  };

  systemd.services.vercel-ddns = {
    description = "Update Vercel A records to the current home public IP";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = [ "token:${config.sops.secrets."vercel-dns-token".path}" ];
      ExecStart = lib.getExe vercelDdns;
    };
  };

  systemd.timers.vercel-ddns = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
  };
}
