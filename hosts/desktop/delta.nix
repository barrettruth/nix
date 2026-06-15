{
  config,
  pkgs,
  lib,
  identity,
  mkDesktopSecret,
  ...
}:
let
  inherit (import ../../modules/nixos/common/service-helpers.nix { inherit pkgs lib; })
    mkR2Backup
    mkNextjsApp
    mkDeployService
    hardening
    ;
  hasDeltaR2BackupSecret = builtins.pathExists ../../secrets/desktop/delta-r2-backup-env;
  softwareSyncSecretNames = [
    "delta-software-sync-delta-api-key"
    "delta-software-sync-forgejo-token"
  ];
  hasSoftwareSyncSecrets = lib.all (
    name: builtins.pathExists ../../secrets/desktop/${name}
  ) softwareSyncSecretNames;
  hasSoftwareSyncGithubSecret = builtins.pathExists ../../secrets/desktop/delta-software-sync-github-token;
  deltaSoftwareSync = pkgs.callPackage ../../pkgs/delta-software-sync { };
  softwareSyncConfig = pkgs.writeText "delta-software-sync.json" (
    builtins.toJSON {
      delta = {
        url = "http://127.0.0.1:3001";
        apiKeyFile = config.sops.secrets."delta-software-sync-delta-api-key".path;
      };
      maintainerUsername = "barrettruth";
      category = "Software";
      canonicalProviders = lib.optionalAttrs hasSoftwareSyncGithubSecret {
        "barrettruth/diffs.nvim" = "github";
        "barrettruth/canola.nvim" = "github";
        "barrettruth/canola-collection" = "github";
      };
      forges = [
        {
          provider = "forgejo";
          baseUrl = "http://127.0.0.1:3000";
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
  mkSoftwareSyncService =
    { mode, description }:
    lib.mkIf hasSoftwareSyncSecrets {
      inherit description;
      after = [
        "network-online.target"
        "delta.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "delta";
        Group = "delta";
        ExecStart = "${deltaSoftwareSync}/bin/delta-software-sync --config ${softwareSyncConfig} --mode ${mode}";
      }
      // hardening;
    };
  softwareSyncUnits = [
    "delta-software-sync-discovery.service"
    "delta-software-sync-active.service"
  ];
  mkSoftwareSyncTimer = onBootSec: {
    wantedBy = lib.optionals hasSoftwareSyncSecrets [ "timers.target" ];
    timerConfig = {
      OnBootSec = onBootSec;
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
  };
in
lib.mkMerge [
  (mkNextjsApp {
    name = "delta";
    dir = "/opt/delta";
    user = "delta";
    group = "delta";
    port = 3001;
    description = "delta - personal todo/productivity platform";
    environmentFile = config.sops.secrets."delta-env".path;
    environment = {
      DATABASE_URL = "/var/lib/delta/data.db";
      DELTA_PUBLIC_ORIGIN = "https://delta.${identity.domain}";
      OAUTH_REDIRECT_BASE_URL = "https://delta.${identity.domain}";
      WEBAUTHN_RP_ID = "delta.${identity.domain}";
      WEBAUTHN_ORIGIN = "https://delta.${identity.domain}";
    };
  })
  (mkDeployService {
    name = "delta";
    dir = "/opt/delta";
    user = "delta";
    group = "delta";
    environment = {
      DATABASE_URL = "/var/lib/delta/data.db";
    };
    readWritePaths = [
      "/opt/delta"
      "/var/lib/delta"
    ];
    restartUnit = "delta.service";
  })
  (lib.optionalAttrs hasDeltaR2BackupSecret (mkR2Backup {
    name = "delta";
    source = "/var/lib/delta/data.db";
    bucket = "delta";
    environmentFile = config.sops.secrets."delta-r2-backup-env".path;
    user = "delta";
    group = "delta";
  }))
  {
    services.nginx.virtualHosts."delta.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3001";
    };

    sops.secrets = {
      "delta-env" = mkDesktopSecret "delta-env" {
        owner = "delta";
        group = "delta";
        mode = "0400";
        restartUnits = [ "delta.service" ];
      };
    }
    // lib.optionalAttrs hasDeltaR2BackupSecret {
      "delta-r2-backup-env" = mkDesktopSecret "delta-r2-backup-env" {
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "delta-r2-backup.service" ];
      };
    }
    // lib.optionalAttrs hasSoftwareSyncSecrets {
      "delta-software-sync-delta-api-key" = mkDesktopSecret "delta-software-sync-delta-api-key" {
        owner = "delta";
        group = "delta";
        mode = "0400";
        restartUnits = softwareSyncUnits;
      };
      "delta-software-sync-forgejo-token" = mkDesktopSecret "delta-software-sync-forgejo-token" {
        owner = "delta";
        group = "delta";
        mode = "0400";
        restartUnits = softwareSyncUnits;
      };
    }
    // lib.optionalAttrs hasSoftwareSyncGithubSecret {
      "delta-software-sync-github-token" = mkDesktopSecret "delta-software-sync-github-token" {
        owner = "delta";
        group = "delta";
        mode = "0400";
        restartUnits = softwareSyncUnits;
      };
    };

    systemd.services.delta-software-sync-discovery = mkSoftwareSyncService {
      mode = "discovery";
      description = "Discover forge Software tasks for delta";
    };

    systemd.services.delta-software-sync-active = mkSoftwareSyncService {
      mode = "active";
      description = "Reconcile tracked forge Software tasks for delta";
    };

    systemd.timers.delta-software-sync-discovery = mkSoftwareSyncTimer "2m";
    systemd.timers.delta-software-sync-active = mkSoftwareSyncTimer "4m";
  }
]
