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
      DEFAULT = {
        APP_NAME = identity.fullName;
      };
      server = {
        DOMAIN = "forge.${identity.domain}";
        ROOT_URL = "https://forge.${identity.domain}/";
        HTTP_PORT = 3000;
        SSH_DOMAIN = "forge.${identity.domain}";
        START_SSH_SERVER = true;
        SSH_PORT = 22;
        SSH_LISTEN_PORT = 2222;
        SSH_SERVER_HOST_KEYS = config.sops.secrets."forgejo-ssh-host-ed25519-key".path;
      };
      service = {
        DISABLE_REGISTRATION = false;
        REGISTER_EMAIL_CONFIRM = true;
        ENABLE_NOTIFY_MAIL = true;
        ENABLE_CAPTCHA = true;
        REQUIRE_CAPTCHA_FOR_LOGIN = false;
        CAPTCHA_TYPE = "hcaptcha";
      };
      repository = {
        DEFAULT_PRIVATE = "private";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        REGISTER_EMAIL_CONFIRM = false;
        UPDATE_AVATAR = true;
        USERNAME = "nickname";
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
        INITIAL_COMMIT = "always";
        CRUD_ACTIONS = "always";
        MERGES = "always";
        WIKI = "never";
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

  systemd.tmpfiles.rules = [
    "R /var/lib/forgejo/custom/public - - - -"
    "R /var/lib/forgejo/custom/templates - - - -"
  ];

  systemd.services.forgejo-dump.preStart = ''
    find /var/backup/forgejo -maxdepth 1 -type f -name 'forgejo-dump-*' -mtime +3 -delete

    free_bytes=$(df --output=avail -B1 /var/backup/forgejo | tail -n 1 | tr -d ' ')
    min_free_bytes=$((20 * 1024 * 1024 * 1024))
    if [ "$free_bytes" -lt "$min_free_bytes" ]; then
      echo "Refusing Forgejo dump: less than 20G free in /var/backup/forgejo"
      exit 1
    fi
  '';

  systemd.services.forgejo-heatmap-reconcile = {
    description = "Replay barrettruth commit history into Forgejo's action table to backfill heatmap";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "git";
      Group = "git";
    };
    path = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnused
      pkgs.sqlite
    ];
    script = ''
      set -euo pipefail

      DB="/var/lib/forgejo/data/forgejo.db"
      REPOS_ROOT="/var/lib/forgejo/repositories"
      OWNER_NAME="barrettruth"
      OP_COMMIT=5
      OP_CREATE_ISSUE=6
      OP_CREATE_PR=7
      OP_COMMENT_ISSUE=10
      OP_COMMENT_PR=23
      OP_PUBLISH_RELEASE=24

      sql() {
        sqlite3 -bail -batch "$DB" ".timeout 5000" "$1"
      }

      user_id=$(sql "SELECT id FROM \"user\" WHERE lower_name = '$OWNER_NAME';")
      if [ -z "$user_id" ]; then
        echo "no forgejo user named $OWNER_NAME found" >&2
        exit 1
      fi
      echo "Reconciling heatmap for $OWNER_NAME (id=$user_id)"

      emails_file=$(mktemp)
      trap 'rm -f "$emails_file"' EXIT
      sql "SELECT email FROM email_address WHERE uid = $user_id;" > "$emails_file"
      sql "SELECT email FROM \"user\" WHERE id = $user_id;" >> "$emails_file"
      sort -u -o "$emails_file" "$emails_file"

      inserted=0

      while IFS='|' read -r repo_id repo_name default_branch; do
        [ -z "$repo_id" ] && continue
        bare="$REPOS_ROOT/$OWNER_NAME/$repo_name.git"
        [ -d "$bare" ] || continue

        default_ref="refs/heads/$default_branch"
        if ! git -C "$bare" rev-parse --verify --quiet "$default_ref" >/dev/null; then
          continue
        fi

        repo_added=0
        while IFS='|' read -r sha ct ae; do
          [ -z "$sha" ] && continue
          if ! grep -Fxq "$ae" "$emails_file"; then
            continue
          fi
          exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $OP_COMMIT AND created_unix = $ct;")
          if [ "$exists" -gt 0 ]; then
            continue
          fi
          content=$(printf '%s\n%s' "$default_branch" "$sha")
          sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $OP_COMMIT, $user_id, $repo_id, '$default_ref', 0, '$content', $ct);"
          repo_added=$((repo_added + 1))
          inserted=$((inserted + 1))
        done < <(git -C "$bare" log --branches --format='%H|%ct|%ae')

        if [ "$repo_added" -gt 0 ]; then
          echo "  $OWNER_NAME/$repo_name: +$repo_added"
        fi
      done < <(sql "SELECT id, name, default_branch FROM repository WHERE owner_id = $user_id AND is_private = 0;")

      echo "Backfilling issues / PRs / comments / releases authored by $OWNER_NAME ..."

      issue_match="(poster_id = $user_id OR (poster_id = -1 AND original_author = '$OWNER_NAME'))"
      comment_match="(c.poster_id = $user_id OR (c.poster_id = -1 AND c.original_author = '$OWNER_NAME'))"

      added_issues=0
      while IFS='|' read -r issue_id repo_id is_pull ct; do
        [ -z "$issue_id" ] && continue
        op_type=$([ "$is_pull" = "1" ] && echo "$OP_CREATE_PR" || echo "$OP_CREATE_ISSUE")
        exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $op_type AND created_unix = $ct;")
        if [ "$exists" -gt 0 ]; then
          continue
        fi
        sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $op_type, $user_id, $repo_id, ''', 0, ''', $ct);"
        added_issues=$((added_issues + 1))
        inserted=$((inserted + 1))
      done < <(sql "SELECT id, repo_id, is_pull, created_unix FROM issue WHERE $issue_match;")
      [ "$added_issues" -gt 0 ] && echo "  +$added_issues issue/PR creates"

      added_comments=0
      while IFS='|' read -r comment_id repo_id is_pull ct; do
        [ -z "$comment_id" ] && continue
        op_type=$([ "$is_pull" = "1" ] && echo "$OP_COMMENT_PR" || echo "$OP_COMMENT_ISSUE")
        exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $op_type AND created_unix = $ct;")
        if [ "$exists" -gt 0 ]; then
          continue
        fi
        sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $op_type, $user_id, $repo_id, ''', 0, ''', $ct);"
        added_comments=$((added_comments + 1))
        inserted=$((inserted + 1))
      done < <(sql "SELECT c.id, i.repo_id, i.is_pull, c.created_unix FROM comment c JOIN issue i ON c.issue_id = i.id WHERE $comment_match AND c.type = 0;")
      [ "$added_comments" -gt 0 ] && echo "  +$added_comments issue/PR comments"

      added_releases=0
      while IFS='|' read -r release_id repo_id ct; do
        [ -z "$release_id" ] && continue
        exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $OP_PUBLISH_RELEASE AND created_unix = $ct;")
        if [ "$exists" -gt 0 ]; then
          continue
        fi
        sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $OP_PUBLISH_RELEASE, $user_id, $repo_id, ''', 0, ''', $ct);"
        added_releases=$((added_releases + 1))
        inserted=$((inserted + 1))
      done < <(sql "SELECT id, repo_id, created_unix FROM release WHERE publisher_id = $user_id;")
      [ "$added_releases" -gt 0 ] && echo "  +$added_releases releases"

      echo "Reconciliation complete: $inserted new action records."
    '';
  };

  systemd.timers.forgejo-heatmap-reconcile = {
    description = "Daily replay of barrettruth commit history into Forgejo's action table";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
}
