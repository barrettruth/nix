{ pkgs, modulesPath, ... }:

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
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM br.barrettruth@gmail.com"
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "br.barrettruth@gmail.com";
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";
    virtualHosts."vault.barrettruth.com" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8222";
    };
    virtualHosts."git.barrettruth.com" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };
  };

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
    config = {
      DOMAIN = "https://vault.barrettruth.com";
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
        DOMAIN = "git.barrettruth.com";
        ROOT_URL = "https://git.barrettruth.com/";
        HTTP_PORT = 3000;
        SSH_DOMAIN = "git.barrettruth.com";
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

  users.groups.git = { };

  environment.systemPackages = with pkgs; [
    vim
    git
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

      gh_repos=$(curl -sf -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/user/repos?per_page=100&type=owner" \
        | jq -r '.[].full_name')

      fg_repos=$(curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
        "$FORGEJO_URL/api/v1/user/repos?limit=50" \
        | jq -r '.[].name')

      for full_name in $gh_repos; do
        repo_name=''${full_name#*/}

        if echo "$fg_repos" | grep -qx "$repo_name"; then
          curl -sf -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            "$FORGEJO_URL/api/v1/repos/$FORGEJO_OWNER/$repo_name/mirror-sync" \
            || echo "sync failed: $repo_name" >&2
        else
          echo "creating mirror: $repo_name"
          curl -sf -X POST \
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
            || echo "migrate failed: $repo_name" >&2
        fi
      done
    '';
  };

  systemd.timers.forgejo-mirror-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 3d";
  };

  nix.extraOptions = ''
    min-free = ${toString (100 * 1024 * 1024)}
    max-free = ${toString (1024 * 1024 * 1024)}
  '';

  system.stateVersion = "24.11";
}
