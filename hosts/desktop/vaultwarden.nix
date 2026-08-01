{
  config,
  pkgs,
  lib,
  identity,
  mkDesktopSecret,
  ...
}:
let
  inherit (import ../../modules/nixos/common/service-helpers.nix { inherit pkgs lib; }) mkR2Backup;
in
lib.mkMerge [
  (mkR2Backup {
    name = "vaultwarden";
    source = "/var/backup/vaultwarden/db.sqlite3";
    bucket = "vaultwarden";
    environmentFile = config.sops.secrets."vaultwarden-r2-backup-env".path;
    user = "vaultwarden";
    group = "vaultwarden";
    after = [ "backup-vaultwarden.service" ];
  })
  {
    services.vaultwarden = {
      enable = true;
      backupDir = "/var/backup/vaultwarden";
      config = {
        DOMAIN = "https://vault.${identity.domain}";
        SIGNUPS_ALLOWED = false;
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = 8222;
      };
    };

    services.nginx.virtualHosts."vault.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8222";
        # /notifications/hub is a websocket; without the upgrade headers
        # nginx turns it into a plain GET, which falls through to a 404 and
        # leaves clients with no live sync.
        proxyWebsockets = true;
      };
    };

    sops.secrets."vaultwarden-r2-backup-env" = mkDesktopSecret "vaultwarden-r2-backup-env" { };
  }
]
