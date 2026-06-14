{
  config,
  pkgs,
  lib,
  modulesPath,
  inputs,
  identity,
  mkVpsSecret,
  ...
}:
let
  webDeployUser = "web-deploy";
  webDeployGroup = "web-deploy";
  webDeployPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF4QXLB3ZH77HJwTbcYB/52jg7kAT+E6BwACf1ianOXS forgejo-actions-web-deploy-2026-05-01";
  staticWebRoots = {
    "barrettruth.com" = "/srv/www/barrettruth.com/current";
    "philipmruth.com" = "/srv/www/philipmruth.com/current";
    "vimdoc-language-server.com" = "/srv/www/vimdoc-language-server.com/current";
  };
  mkStaticSiteHost = root: {
    enableACME = true;
    forceSSL = true;
    inherit root;
    extraConfig = ''
      limit_req zone=static_site_per_ip burst=120 nodelay;
      limit_conn static_site_conn_per_ip 40;
      error_page 404 /404.html;
    '';
    locations."/" = {
      tryFiles = "$uri $uri/ =404";
      extraConfig = ''
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      '';
    };
    locations."~* \\.(?:css|js|mjs|png|jpg|jpeg|gif|webp|svg|ico|pdf|ttf|otf|woff|woff2)$".extraConfig =
      ''
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
      '';
  };
  mkBarrettruthHost =
    root:
    lib.recursiveUpdate (mkStaticSiteHost root) {
      locations."~* ^/fonts/.*\\.(?:ttf|otf|woff|woff2)$".extraConfig = ''
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        add_header Access-Control-Allow-Origin "https://www.vimdoc-language-server.com" always;
        add_header Vary "Origin" always;
      '';
    };
  mkRedirectHost = target: {
    enableACME = true;
    forceSSL = true;
    locations."/".return = "301 https://${target}$request_uri";
  };
in
{
  imports = [
    ./finance.nix
    ./delta.nix
    ./headscale.nix
    ./disk-config.nix
    ./hardware-configuration.nix
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    devices = lib.mkForce [ "nodev" ];
    configurationLimit = 2;
  };

  documentation.enable = false;
  hardware.enableRedistributableFirmware = false;
  fonts.fontconfig.enable = false;

  networking = {
    hostName = "vps";
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
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${identity.email}"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6OeNUf0FNpeNSq/XKyJTl4XDlmaV/UcV2SpPzgn4ag forgejo-actions-delta-deploy-2026-05-10"
  ];

  users.groups.${webDeployGroup} = { };

  users.users.${webDeployUser} = {
    isSystemUser = true;
    group = webDeployGroup;
    home = "/var/lib/${webDeployUser}";
    createHome = true;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [ webDeployPublicKey ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = identity.email;
  };

  services.nginx = {
    enable = true;
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=static_site_per_ip:10m rate=20r/s;
      limit_conn_zone $binary_remote_addr zone=static_site_conn_per_ip:10m;
    '';
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";
    virtualHosts."www.${identity.domain}" = mkBarrettruthHost staticWebRoots."barrettruth.com";
    virtualHosts.${identity.domain} = mkRedirectHost "www.${identity.domain}";
    virtualHosts."www.barrettruth.sh" = mkBarrettruthHost staticWebRoots."barrettruth.com";
    virtualHosts."barrettruth.sh" = mkRedirectHost "www.barrettruth.sh";
    virtualHosts."www.philipmruth.com" = mkStaticSiteHost staticWebRoots."philipmruth.com";
    virtualHosts."philipmruth.com" = mkRedirectHost "www.philipmruth.com";
    virtualHosts."www.vimdoc-language-server.com" =
      mkStaticSiteHost
        staticWebRoots."vimdoc-language-server.com";
    virtualHosts."vimdoc-language-server.com" = mkRedirectHost "www.vimdoc-language-server.com";
    virtualHosts."vimdoc-language-server.${identity.domain}" =
      mkRedirectHost "www.vimdoc-language-server.com";
    virtualHosts."vault.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8222";
    };
  };

  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemKeepFree=2G
    RuntimeMaxUse=256M
    MaxRetentionSec=14day
  '';

  services.logrotate = {
    enable = true;
    settings.nginx = {
      frequency = "daily";
      rotate = 14;
      maxsize = "100M";
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

  systemd.tmpfiles.rules = [
    "d /srv/www 0755 root root -"
    "d /srv/www/barrettruth.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/barrettruth.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/philipmruth.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/philipmruth.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/vimdoc-language-server.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/vimdoc-language-server.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    nodejs_22
    pnpm
    rsync
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

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "";
  };

  # Keep only the current VPS system generation and one rollback generation.
  system.activationScripts.pruneVpsSystemGenerations.text = ''
    if [ -e /nix/var/nix/profiles/system ]; then
      ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +2
      ${config.nix.package}/bin/nix-store --gc
    fi
  '';

  nix.extraOptions = ''
    min-free = ${toString (100 * 1024 * 1024)}
    max-free = ${toString (1024 * 1024 * 1024)}
  '';

  system.stateVersion = "24.11";
}
