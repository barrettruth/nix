{
  config,
  pkgs,
  lib,
  mkDesktopSecret,
  ...
}:
let
  hasVercelToken = builtins.pathExists ../../secrets/desktop/vercel-dns-token;
  parseHost =
    host:
    let
      parts = lib.splitString "." host;
      n = lib.length parts;
    in
    {
      domain = lib.concatStringsSep "." (lib.sublist (n - 2) 2 parts);
      name = lib.concatStringsSep "." (lib.sublist 0 (n - 2) parts);
    };
  ddnsTargets = map parseHost (lib.attrNames config.services.nginx.virtualHosts);
  ddnsDomains = lib.unique (map (t: t.domain) ddnsTargets);
  ddnsByDomain = map (d: {
    domain = d;
    names = lib.unique (map (t: t.name) (lib.filter (t: t.domain == d) ddnsTargets));
  }) ddnsDomains;
  vercelDdns = pkgs.writeShellApplication {
    name = "vercel-ddns";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      token="$(cat "$CREDENTIALS_DIRECTORY/token")"
      authheader="header = \"Authorization: Bearer $token\""

      ip=""
      for svc in https://api.ipify.org https://icanhazip.com https://ifconfig.me/ip; do
        if ip="$(curl -fsS --max-time 15 --retry 3 --retry-delay 2 "$svc" | tr -d '[:space:]')" && [ -n "$ip" ]; then
          break
        fi
      done
      if [ -z "$ip" ]; then
        echo "could not determine public IP" >&2
        exit 1
      fi

      rc=0

      update_domain() {
        domain="$1"
        shift
        if ! records="$(printf '%s\n' "$authheader" | curl -fsS --max-time 20 --retry 3 --retry-delay 2 -K - "https://api.vercel.com/v4/domains/$domain/records")"; then
          echo "failed to fetch records for $domain" >&2
          rc=1
          return 0
        fi
        if ! printf '%s' "$records" | jq -e '.records | type == "array"' >/dev/null 2>&1; then
          echo "unexpected Vercel response for $domain" >&2
          rc=1
          return 0
        fi
        for name in "$@"; do
          label="$name.$domain"
          [ -z "$name" ] && label="$domain"
          row="$(printf '%s' "$records" \
            | jq -r --arg n "$name" '.records[] | select(.name==$n and .type=="A") | "\(.id)\t\(.value)"' \
            | head -n1)"
          id="$(printf '%s' "$row" | cut -f1)"
          cur="$(printf '%s' "$row" | cut -f2)"
          if [ -z "$id" ]; then
            echo "no A record for $label; skipping" >&2
            continue
          fi
          if [ "$cur" = "$ip" ]; then
            continue
          fi
          echo "updating $label: $cur -> $ip"
          if ! printf '%s\n' "$authheader" | curl -fsS --max-time 20 --retry 3 --retry-delay 2 -K - \
            -X PATCH -H "Content-Type: application/json" -d "{\"value\":\"$ip\"}" \
            "https://api.vercel.com/v1/domains/records/$id" >/dev/null; then
            echo "failed to update $label" >&2
            rc=1
          fi
        done
        return 0
      }

      ${lib.concatMapStringsSep "\n" (
        g: "update_domain ${lib.escapeShellArg g.domain} ${lib.concatMapStringsSep " " lib.escapeShellArg g.names}"
      ) ddnsByDomain}

      exit "$rc"
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
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      CapabilityBoundingSet = "";
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
      UMask = "0077";
    };
  };

  systemd.timers.vercel-ddns = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      RandomizedDelaySec = "30s";
      Persistent = true;
    };
  };
}
