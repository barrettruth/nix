{
  config,
  pkgs,
  lib,
  identity,
  mkVpsSecret,
  ...
}:
let
  hasDeltaR2BackupSecret = builtins.pathExists ../../secrets/vps/delta-r2-backup-env;
  softwareSyncSecretNames = [
    "delta-software-sync-delta-api-key"
    "delta-software-sync-forgejo-token"
  ];
  hasSoftwareSyncSecrets = lib.all (
    name: builtins.pathExists ../../secrets/vps/${name}
  ) softwareSyncSecretNames;
  hasSoftwareSyncGithubSecret = builtins.pathExists ../../secrets/vps/delta-software-sync-github-token;
  deltaSoftwareSync = pkgs.callPackage ../../pkgs/delta-software-sync { };
  softwareSyncConfig = pkgs.writeText "delta-software-sync.json" (
    builtins.toJSON {
      delta = {
        url = "http://127.0.0.1:3001";
        apiKeyFile = config.sops.secrets."delta-software-sync-delta-api-key".path;
      };
      maintainerUsername = "barrettruth";
      category = "Software";
      forges = [
        {
          provider = "forgejo";
          baseUrl = "https://git.${identity.domain}";
          tokenFile = config.sops.secrets."delta-software-sync-forgejo-token".path;
          priority = 10;
        }
      ]
      ++ lib.optionals hasSoftwareSyncGithubSecret [
        {
          provider = "github";
          baseUrl = "https://github.com";
          tokenFile = config.sops.secrets."delta-software-sync-github-token".path;
          priority = 20;
        }
      ];
    }
  );
in
{
  services.nginx.virtualHosts."delta.${identity.domain}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:3001";
  };

  sops.secrets = {
    "delta-env" = mkVpsSecret "delta-env" {
      owner = "delta";
      group = "delta";
      mode = "0400";
      restartUnits = [ "delta.service" ];
    };
  }
  // lib.optionalAttrs hasDeltaR2BackupSecret {
    "delta-r2-backup-env" = mkVpsSecret "delta-r2-backup-env" {
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "delta-r2-backup.service" ];
    };
  }
  // lib.optionalAttrs hasSoftwareSyncSecrets {
    "delta-software-sync-delta-api-key" = mkVpsSecret "delta-software-sync-delta-api-key" {
      owner = "delta";
      group = "delta";
      mode = "0400";
      restartUnits = [ "delta-software-sync-discovery.service" ];
    };
    "delta-software-sync-forgejo-token" = mkVpsSecret "delta-software-sync-forgejo-token" {
      owner = "delta";
      group = "delta";
      mode = "0400";
      restartUnits = [ "delta-software-sync-discovery.service" ];
    };
  }
  // lib.optionalAttrs hasSoftwareSyncGithubSecret {
    "delta-software-sync-github-token" = mkVpsSecret "delta-software-sync-github-token" {
      owner = "delta";
      group = "delta";
      mode = "0400";
      restartUnits = [ "delta-software-sync-discovery.service" ];
    };
  };

  users.users.delta = {
    isSystemUser = true;
    home = "/opt/delta";
    group = "delta";
  };

  users.groups.delta = { };

  systemd.services.delta = {
    description = "delta - personal todo/productivity platform";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/opt/delta/.next/standalone/server.js";
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/opt/delta";
      ExecStart = "${pkgs.nodejs_22}/bin/node .next/standalone/server.js";
      Restart = "on-failure";
      RestartSec = 5;
      User = "delta";
      Group = "delta";
      StateDirectory = "delta";
      EnvironmentFile = config.sops.secrets."delta-env".path;
    };
    environment = {
      NODE_ENV = "production";
      PORT = "3001";
      HOSTNAME = "127.0.0.1";
      DATABASE_URL = "/var/lib/delta/data.db";
      DELTA_PUBLIC_ORIGIN = "https://delta.${identity.domain}";
      OAUTH_REDIRECT_BASE_URL = "https://delta.${identity.domain}";
      WEBAUTHN_RP_ID = "delta.${identity.domain}";
      WEBAUTHN_ORIGIN = "https://delta.${identity.domain}";
    };
  };

  systemd.services.delta-r2-backup = {
    description = "Backup delta SQLite to Cloudflare R2";
    serviceConfig = {
      Type = "oneshot";
    }
    // lib.optionalAttrs hasDeltaR2BackupSecret {
      EnvironmentFile = config.sops.secrets."delta-r2-backup-env".path;
    };
    path = [
      pkgs.awscli2
      pkgs.gawk
    ];
    script = ''
      : "''${R2_ACCESS_KEY_ID:?delta R2 backup secret is missing R2_ACCESS_KEY_ID}"
      : "''${R2_SECRET_ACCESS_KEY:?delta R2 backup secret is missing R2_SECRET_ACCESS_KEY}"
      : "''${R2_ENDPOINT:?delta R2 backup secret is missing R2_ENDPOINT}"

      export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
      export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
      ENDPOINT="$R2_ENDPOINT"
      DATE=$(date +%Y-%m-%d)

      aws s3 cp /var/lib/delta/data.db \
        "s3://delta/$DATE/data.db" \
        --endpoint-url "$ENDPOINT"

      CUTOFF=$(date -d '30 days ago' +%Y-%m-%d)
      aws s3 ls s3://delta/ --endpoint-url "$ENDPOINT" \
        | awk '{print $2}' | tr -d '/' \
        | while read dir; do
            if [ "$dir" \< "$CUTOFF" ]; then
              aws s3 rm "s3://delta/$dir" --recursive --endpoint-url "$ENDPOINT"
            fi
          done
    '';
  };

  systemd.timers.delta-r2-backup = {
    wantedBy = lib.optionals hasDeltaR2BackupSecret [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.services.delta-software-sync-discovery = lib.mkIf hasSoftwareSyncSecrets {
    description = "Discover forge Software tasks for delta";
    after = [
      "network-online.target"
      "delta.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "delta";
      Group = "delta";
      ExecStart = "${deltaSoftwareSync}/bin/delta-software-sync --config ${softwareSyncConfig} --mode discovery";
    };
  };

  systemd.timers.delta-software-sync-discovery = {
    wantedBy = lib.optionals hasSoftwareSyncSecrets [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
  };
}
