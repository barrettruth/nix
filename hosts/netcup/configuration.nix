{
  pkgs,
  lib,
  modulesPath,
  identity,
  ...
}:

let
  cacheRoot = "/var/cache/github-runner";

  sanitize =
    repo:
    lib.toLower (
      lib.replaceStrings
        [
          "."
        ]
        [
          "-"
        ]
        repo
    );

  repos = [
    {
      repo = "barrettruth.com";
      class = "general";
    }
    {
      repo = "blink-cmp-ghostty";
      class = "general";
    }
    {
      repo = "blink-cmp-ssh";
      class = "general";
    }
    {
      repo = "blink-cmp-tmux";
      class = "general";
    }
    {
      repo = "canola.nvim";
      class = "general";
    }
    {
      repo = "canola-collection";
      class = "general";
    }
    {
      repo = "cp.nvim";
      class = "general";
    }
    {
      repo = "delta";
      class = "general";
    }
    {
      repo = "diffs.nvim";
      class = "general";
    }
    {
      repo = "forge.nvim";
      class = "general";
    }
    {
      repo = "http-codes.nvim";
      class = "general";
    }
    {
      repo = "import-cost.nvim";
      class = "general";
    }
    {
      repo = "likewise";
      class = "general";
    }
    {
      repo = "live-server.nvim";
      class = "general";
    }
    {
      repo = "midnight.nvim";
      class = "general";
    }
    {
      repo = "nonicons.nvim";
      class = "general";
    }
    {
      repo = "pending.nvim";
      class = "general";
    }
    {
      repo = "philipmruth.com";
      class = "general";
    }
    {
      repo = "preview.nvim";
      class = "general";
    }
    {
      repo = "sioyek-dev";
      class = "general";
    }
    {
      repo = "vimdoc-language-server";
      class = "general";
    }
  ];

  workDir = { repo, class }: "/var/lib/github-runner/work/${class}/${repo}";

  cacheDirs = [
    "${cacheRoot}/cargo"
    "${cacheRoot}/npm"
    "${cacheRoot}/pip"
    "${cacheRoot}/pre-commit"
    "${cacheRoot}/rustup"
    "${cacheRoot}/uv"
    "${cacheRoot}/xdg-cache"
    "${cacheRoot}/xdg-data"
  ];

  mkRunner =
    { repo, class }:
    let
      runnerId = sanitize repo;
    in
    lib.nameValuePair runnerId {
      enable = true;
      url = "https://github.com/barrettruth/${repo}";
      tokenFile = "/etc/github-runner/token";
      tokenType = "access";
      name = "netcup-${runnerId}";
      replace = true;
      user = "github-runner";
      group = "github-runner";
      workDir = workDir { inherit repo class; };
      extraLabels = [
        "netcup"
        "nix"
        "cache"
        class
      ];
      extraPackages = with pkgs; [
        curl
        diffutils
        docker
        fd
        gh
        gnumake
        jq
        nodejs_22
        pkg-config
        pnpm
        python3
        python3Packages.pip
        ripgrep
        stdenv.cc
        unzip
        uv
        wget
        xz
        zip
        (runCommand "sudo-wrapper" { } ''
          mkdir -p $out/bin
          ln -s /run/wrappers/bin/sudo $out/bin/sudo
        '')
      ];
      extraEnvironment = {
        CARGO_HOME = "${cacheRoot}/cargo";
        PIP_CACHE_DIR = "${cacheRoot}/pip";
        PRE_COMMIT_HOME = "${cacheRoot}/pre-commit";
        RUSTUP_HOME = "${cacheRoot}/rustup";
        UV_CACHE_DIR = "${cacheRoot}/uv";
        XDG_CACHE_HOME = "${cacheRoot}/xdg-cache";
        XDG_DATA_HOME = "${cacheRoot}/xdg-data";
        npm_config_cache = "${cacheRoot}/npm";
      };
      serviceOverrides = {
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
        Nice = 10;
        ProtectSystem = lib.mkForce false;
        PrivateTmp = lib.mkForce false;
        BindPaths = lib.mkForce [ ];
        ProtectProc = lib.mkForce "default";
        ProtectControlGroups = lib.mkForce false;
        RestrictNamespaces = lib.mkForce false;
        SystemCallFilter = lib.mkForce [ ];
        ProtectKernelTunables = lib.mkForce false;
        ProtectKernelModules = lib.mkForce false;
        ProtectKernelLogs = lib.mkForce false;
        ExecStartPre = [
          "${pkgs.coreutils}/bin/ln -sfn ${pkgs.github-runner}/lib/externals /var/lib/github-runner/${runnerId}/externals"
        ];
      };
    };
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
    configurationLimit = 3;
  };

  documentation.enable = false;
  hardware.enableRedistributableFirmware = false;
  fonts.fontconfig.enable = false;

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      icu
      openssl
      stdenv.cc.cc
      zlib
    ];
  };

  networking = {
    hostName = "netcup";
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "152.53.168.144";
          prefixLength = 22;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a0a:4cc0:2000:af7d:c8e4:dff:fe7f:c233";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "152.53.168.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${identity.email}"
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = identity.email;
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";
    virtualHosts."vault.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8222";
    };
    virtualHosts."git.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };
    virtualHosts."delta.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3001";
    };
  };

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
    config = {
      DOMAIN = "https://vault.${identity.domain}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
    };
  };

  services.forgejo = {
    enable = true;
    user = "git";
    group = "git";
    settings = {
      server = {
        DOMAIN = "git.${identity.domain}";
        ROOT_URL = "https://git.${identity.domain}/";
        HTTP_PORT = 3000;
        SSH_DOMAIN = "git.${identity.domain}";
      };
      service.DISABLE_REGISTRATION = true;
      session.COOKIE_SECURE = true;
      mirror = {
        DEFAULT_INTERVAL = "1h";
        MIN_INTERVAL = "10m";
      };
    };
  };

  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };

  virtualisation.docker.enable = true;

  security.sudo.extraRules = [
    {
      users = [ "github-runner" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
    home = "/var/lib/github-runner";
    extraGroups = [ "docker" ];
  };

  users.groups.git = { };
  users.groups.github-runner = { };

  systemd.tmpfiles.rules = [
    "d /etc/github-runner 0750 root root -"
    "d /var/cache/github-runner 0750 github-runner github-runner -"
    "d /var/lib/github-runner 0750 github-runner github-runner -"
    "d /var/lib/github-runner/work 0750 github-runner github-runner -"
    "d /var/lib/github-runner/work/general 0750 github-runner github-runner -"
    "d /var/lib/github-runner/work/heavy 0750 github-runner github-runner -"
  ]
  ++ map (dir: "d ${dir} 0750 github-runner github-runner -") cacheDirs
  ++ map (repoCfg: "d ${workDir repoCfg} 0750 github-runner github-runner -") repos;

  services.github-runners = lib.listToAttrs (map mkRunner repos);

  environment.systemPackages = with pkgs; [
    vim
    git
    nodejs_22
    pnpm
  ];

  systemd.services.vaultwarden-r2-backup = {
    description = "Backup Vaultwarden to Cloudflare R2";
    after = [ "backup-vaultwarden.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/vaultwarden-r2-backup.env";
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

  systemd.services.forgejo-mirror-sync = {
    description = "Auto-discover and sync GitHub repos to Forgejo mirrors";
    after = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/forgejo-mirror.env";
    };
    path = with pkgs; [
      curl
      jq
    ];
    script = ''
      set -euo pipefail

      log() { echo "[forgejo-mirror-sync] $1"; }
      err() { echo "[forgejo-mirror-sync] ERROR: $1" >&2; }

      api_call() {
        local response http_code body
        response=$(curl -s -w "\n%{http_code}" "$@")
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        if [ "$http_code" -ge 400 ]; then
          err "HTTP $http_code from $2"
          err "Response: $body"
          return 1
        fi
        echo "$body"
      }

      log "validating GitHub token..."
      gh_user=$(api_call -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/user" | jq -r '.login') \
        || { err "GitHub token is invalid or expired"; exit 1; }
      log "authenticated to GitHub as $gh_user"

      log "validating Forgejo token..."
      fg_user=$(api_call -H "Authorization: token $FORGEJO_TOKEN" \
        "$FORGEJO_URL/api/v1/user" | jq -r '.login') \
        || { err "Forgejo token is invalid or expired — regenerate at $FORGEJO_URL/user/settings/applications"; exit 1; }
      log "authenticated to Forgejo as $fg_user"

      log "fetching GitHub repos..."
      gh_repos=""
      gh_page=1
      while true; do
        page_data=$(api_call -H "Authorization: token $GITHUB_TOKEN" \
          "https://api.github.com/user/repos?per_page=100&type=owner&page=$gh_page") \
          || { err "failed to fetch GitHub repos (page $gh_page)"; exit 1; }
        page_repos=$(echo "$page_data" | jq -r '.[].full_name')
        [ -z "$page_repos" ] && break
        gh_repos="''${gh_repos:+$gh_repos
      }$page_repos"
        gh_page=$((gh_page + 1))
      done
      gh_count=$(echo "$gh_repos" | grep -c . || true)
      log "found $gh_count GitHub repos"

      log "fetching Forgejo repos..."
      fg_repos=""
      fg_page=1
      while true; do
        page_data=$(api_call -H "Authorization: token $FORGEJO_TOKEN" \
          "$FORGEJO_URL/api/v1/user/repos?limit=50&page=$fg_page") \
          || { err "failed to fetch Forgejo repos (page $fg_page)"; exit 1; }
        page_repos=$(echo "$page_data" | jq -r '.[].name')
        [ -z "$page_repos" ] && break
        fg_repos="''${fg_repos:+$fg_repos
      }$page_repos"
        fg_page=$((fg_page + 1))
      done
      fg_count=$(echo "$fg_repos" | grep -c . || true)
      log "found $fg_count Forgejo repos"

      synced=0
      created=0
      failed=0

      for full_name in $gh_repos; do
        repo_name=''${full_name#*/}

        if echo "$fg_repos" | grep -qx "$repo_name"; then
          log "syncing $repo_name..."
          if api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            "$FORGEJO_URL/api/v1/repos/$FORGEJO_OWNER/$repo_name/mirror-sync" \
            > /dev/null; then
            synced=$((synced + 1))
          else
            err "sync failed for $repo_name"
            failed=$((failed + 1))
          fi
        else
          log "creating mirror: $repo_name..."
          if api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            "$FORGEJO_URL/api/v1/repos/migrate" \
            -d "$(jq -n \
              --arg addr "https://github.com/$full_name.git" \
              --arg name "$repo_name" \
              --arg owner "$FORGEJO_OWNER" \
              --arg token "$GITHUB_TOKEN" \
              '{
                clone_addr: $addr,
                repo_name: $name,
                repo_owner: $owner,
                mirror: true,
                auth_token: $token,
                service: "github"
              }')" \
            > /dev/null; then
            created=$((created + 1))
          else
            err "migrate failed for $repo_name"
            failed=$((failed + 1))
          fi
        fi
      done

      log "done: $synced synced, $created created, $failed failed"
      [ "$failed" -eq 0 ]
    '';
  };

  systemd.timers.forgejo-mirror-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
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
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/opt/delta";
      ExecStart = "${pkgs.nodejs_22}/bin/node .next/standalone/server.js";
      Restart = "on-failure";
      RestartSec = 5;
      User = "delta";
      Group = "delta";
      StateDirectory = "delta";
      EnvironmentFile = "/var/lib/delta/env";
    };
    environment = {
      NODE_ENV = "production";
      PORT = "3001";
      HOSTNAME = "127.0.0.1";
      DATABASE_URL = "/var/lib/delta/data.db";
    };
  };

  systemd.services.delta-r2-backup = {
    description = "Backup delta SQLite to Cloudflare R2";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/delta-r2-backup.env";
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
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    keep-outputs = true;
    trusted-users = lib.mkForce [
      "root"
      "github-runner"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.extraOptions = ''
    min-free = ${toString (100 * 1024 * 1024)}
    max-free = ${toString (1024 * 1024 * 1024)}
  '';

  system.stateVersion = "24.11";
}
