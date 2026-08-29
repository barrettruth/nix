{
  config,
  pkgs,
  lib,
  identity,
  mkDesktopSecret,
  ...
}:
let
  forgejoSigningPublicKey = pkgs.writeText "forgejo-signing-key.pub" ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN+HWhaAsJvKzEEpmJJMRS1SJcFJ72z+5kLA2iOh42lb Forgejo instance signing <noreply@barrettruth.com>
  '';
  forgejoOauthSources = {
    github = {
      provider = "github";
      displayName = "GitHub";
    };
    google = {
      provider = "gplus";
      displayName = "Google";
    };
    gitlab = {
      provider = "gitlab";
      displayName = "GitLab";
    };
  };
  forgejoOauthSecretNames = lib.flatten (
    lib.mapAttrsToList (name: _: [
      "forgejo-oauth-${name}-id"
      "forgejo-oauth-${name}-secret"
    ]) forgejoOauthSources
  );
in
{
  sops.secrets =
    let
      mkForgejoSecret =
        restartUnits: name:
        mkDesktopSecret name {
          owner = "git";
          group = "git";
          mode = "0400";
          inherit restartUnits;
        };
    in
    lib.genAttrs [
      "forgejo-resend-api-key"
      "forgejo-hcaptcha-sitekey"
      "forgejo-hcaptcha-secret"
      "forgejo-ssh-host-ed25519-key"
      "forgejo-ssh-signing-key"
    ] (mkForgejoSecret [ "forgejo.service" ])
    // lib.genAttrs forgejoOauthSecretNames (mkForgejoSecret [ "forgejo-oauth-sync.service" ]);

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    user = "git";
    group = "git";
    dump = {
      enable = true;
      backupDir = "/var/backup/forgejo";
      age = "3d";
    };
    secrets = {
      mailer.PASSWD = config.sops.secrets."forgejo-resend-api-key".path;
      service.HCAPTCHA_SITEKEY = config.sops.secrets."forgejo-hcaptcha-sitekey".path;
      service.HCAPTCHA_SECRET = config.sops.secrets."forgejo-hcaptcha-secret".path;
    };
    settings = {
      server = {
        DOMAIN = "forge.${identity.domain}";
        ROOT_URL = "https://forge.${identity.domain}/";
        START_SSH_SERVER = true;
        SSH_LISTEN_PORT = 2222;
        SSH_SERVER_HOST_KEYS = config.sops.secrets."forgejo-ssh-host-ed25519-key".path;
      };
      service = {
        REGISTER_EMAIL_CONFIRM = true;
        ENABLE_NOTIFY_MAIL = true;
        ENABLE_CAPTCHA = true;
        REQUIRE_CAPTCHA_FOR_LOGIN = true;
        CAPTCHA_TYPE = "hcaptcha";
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        REGISTER_EMAIL_CONFIRM = false;
        UPDATE_AVATAR = true;
      };
      security.GLOBAL_TWO_FACTOR_REQUIREMENT = "admin";
      session.COOKIE_SECURE = true;
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.resend.com";
        SMTP_PORT = 2465;
        USER = "resend";
        FROM = "noreply@${identity.domain}";
      };
      mirror = {
        DEFAULT_INTERVAL = "15m";
        MIN_INTERVAL = "5m";
      };
      "repository.pull-request" = {
        POPULATE_SQUASH_COMMENT_WITH_COMMIT_MESSAGES = true;
        DEFAULT_MERGE_MESSAGE_COMMITS_LIMIT = 1000;
        DEFAULT_MERGE_MESSAGE_SIZE = 1048576;
      };
      "repository.signing" = {
        FORMAT = "ssh";
        SIGNING_KEY = "/run/credentials/forgejo.service/forgejo-signing-key.pub";
        SIGNING_NAME = "Forgejo";
        SIGNING_EMAIL = "noreply@${identity.domain}";
        CRUD_ACTIONS = "always";
        MERGES = "always";
      };
      "markup.sanitizer.video-muted" = {
        ELEMENT = "video";
        ALLOW_ATTR = "muted";
      };
      "markup.sanitizer.video-loop" = {
        ELEMENT = "video";
        ALLOW_ATTR = "loop";
      };
      "markup.sanitizer.video-playsinline" = {
        ELEMENT = "video";
        ALLOW_ATTR = "playsinline";
      };
    };
  };

  systemd.services.forgejo = {
    path = [ pkgs.openssh ];
    serviceConfig.TimeoutStopSec = "300s";
    serviceConfig.LoadCredential = lib.mkAfter [
      "forgejo-signing-key:${config.sops.secrets."forgejo-ssh-signing-key".path}"
      "forgejo-signing-key.pub:${forgejoSigningPublicKey}"
    ];
  };

  systemd.services.forgejo-oauth-sync = {
    description = "Sync Forgejo OAuth2 authentication sources from on-disk credentials";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    wantedBy = [ "forgejo.service" ];
    path = [ pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "git";
      Group = "git";
      WorkingDirectory = "/var/lib/forgejo";
      LoadCredential = lib.flatten (
        lib.mapAttrsToList (name: _: [
          "${name}-id:${config.sops.secrets."forgejo-oauth-${name}-id".path}"
          "${name}-secret:${config.sops.secrets."forgejo-oauth-${name}-secret".path}"
        ]) forgejoOauthSources
      );
    };
    script =
      let
        forgejo = "${config.services.forgejo.package}/bin/forgejo --config /var/lib/forgejo/custom/conf/app.ini --work-path /var/lib/forgejo";
        syncOne = name: cfg: ''
          id=$(${forgejo} admin auth list | awk -F'\t' -v d="${cfg.displayName}" -v n="${name}" 'NR>1 && ($2==d || $2==n) {print $1; exit}')
          key=$(cat "$CREDENTIALS_DIRECTORY/${name}-id")
          secret=$(cat "$CREDENTIALS_DIRECTORY/${name}-secret")
          if [ -z "$id" ]; then
            ${forgejo} admin auth add-oauth \
              --name "${name}" \
              --provider "${cfg.provider}" \
              --key "$key" \
              --secret "$secret"
          else
            ${forgejo} admin auth update-oauth \
              --id "$id" \
              --name "${name}" \
              --key "$key" \
              --secret "$secret"
          fi
        '';
      in
      ''
        set -eu
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList syncOne forgejoOauthSources)}
      '';
  };

  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };

  users.groups.git = { };

  systemd.services.forgejo-dump.preStart = ''
    free_bytes=$(df --output=avail -B1 /var/backup/forgejo | tail -n 1 | tr -d ' ')
    min_free_bytes=$((20 * 1024 * 1024 * 1024))
    if [ "$free_bytes" -lt "$min_free_bytes" ]; then
      echo "Refusing Forgejo dump: less than 20G free in /var/backup/forgejo"
      exit 1
    fi
  '';

}
