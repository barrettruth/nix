{
  config,
  pkgs,
  identity,
  mkDesktopSecret,
  ...
}:
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
    locations."/".proxyPass = "http://127.0.0.1:8222";
  };

  sops.secrets."vaultwarden-r2-backup-env" = mkDesktopSecret "vaultwarden-r2-backup-env" { };

  systemd.services.vaultwarden-r2-backup = {
    description = "Backup Vaultwarden to Cloudflare R2";
    after = [ "backup-vaultwarden.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.secrets."vaultwarden-r2-backup-env".path;
    };
    path = [
      pkgs.awscli2
      pkgs.gawk
    ];
    script = ''
      export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
      export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
      ENDPOINT="$R2_ENDPOINT"
      DATE=$(date +%Y-%m-%d)

      aws s3 cp /var/backup/vaultwarden/db.sqlite3 \
        "s3://vaultwarden/$DATE/db.sqlite3" \
        --endpoint-url "$ENDPOINT"

      CUTOFF=$(date -d '30 days ago' +%Y-%m-%d)
      aws s3 ls s3://vaultwarden/ --endpoint-url "$ENDPOINT" \
        | awk '{print $2}' | tr -d '/' \
        | while read dir; do
            if [ "$dir" \< "$CUTOFF" ]; then
              aws s3 rm "s3://vaultwarden/$dir" --recursive --endpoint-url "$ENDPOINT"
            fi
          done
    '';
  };

  systemd.timers.vaultwarden-r2-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
