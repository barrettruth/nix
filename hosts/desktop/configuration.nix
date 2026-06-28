{
  config,
  lib,
  identity,
  pkgs,
  mkDesktopSecret,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ./disk-config.nix
    ./forgejo.nix
    ./static-sites.nix
    ./delta.nix
    ./vaultwarden.nix
    ./finance.nix
    ./ddns.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    configurationLimit = 5;
    mirroredBoots = [
      {
        path = "/boot";
        efiSysMountPoint = "/efi";
        devices = [ "nodev" ];
      }
    ];
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/efi";
  boot.tmp.cleanOnBoot = true;

  hardware.enableRedistributableFirmware = true;

  networking.hostName = "desktop";
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General.EnableNetworkConfiguration = true;
      Network.NameResolvingService = "resolvconf";
      Settings.AutoConnect = true;
    };
  };

  systemd.services.wifi-powersave-off = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.iw ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for dev in /sys/class/net/wl*; do
        [ -e "$dev" ] && iw dev "$(basename "$dev")" set power_save off || true
      done
    '';
  };

  i18n.defaultLocale = "en_US.UTF-8";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${identity.email}"
  ];
  users.users.root.initialPassword = "root";

  users.groups.nixremote = { };
  users.users.nixremote = {
    isSystemUser = true;
    group = "nixremote";
    home = "/var/lib/nixremote";
    createHome = true;
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIX/I64qCTMz4854Nms0bDTj4D7Ca7y6TYtCo+U3nC2t nix-remote-builder"
    ];
  };

  users.users.barrett = {
    isNormalUser = true;
    home = "/home/barrett";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${identity.email}"
    ];
  };

  systemd.user.slices.rbuild = {
    description = "rbuild remote build resource pool";
    sliceConfig = {
      CPUQuota = "400%";
      MemoryMax = "24G";
      TasksMax = 4096;
    };
  };

  environment.systemPackages = [ pkgs.rsync ];

  nix.settings.trusted-users = [
    "root"
    "nixremote"
  ];
  nix.settings.min-free = 21474836480;
  nix.settings.max-free = 53687091200;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  users.groups.forgejo-runner-secrets = { };

  sops.secrets."forgejo-runner-token" = mkDesktopSecret "forgejo-runner-token" {
    mode = "0440";
    group = "forgejo-runner-secrets";
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.desktop = {
      enable = true;
      name = "desktop";
      url = "http://127.0.0.1:${toString config.services.forgejo.settings.server.HTTP_PORT}";
      tokenFile = config.sops.secrets."forgejo-runner-token".path;
      labels = [
        "nix:host"
        "desktop:host"
      ];
      settings.runner.envs = {
        CARGO_HOME = "/var/cache/gitea-runner/cargo";
        RUSTUP_HOME = "/var/cache/gitea-runner/rustup";
        npm_config_cache = "/var/cache/gitea-runner/npm";
        BUN_INSTALL_CACHE_DIR = "/var/cache/gitea-runner/bun";
        PIP_CACHE_DIR = "/var/cache/gitea-runner/pip";
        UV_CACHE_DIR = "/var/cache/gitea-runner/uv";
        GOCACHE = "/var/cache/gitea-runner/go-build";
        GOMODCACHE = "/var/cache/gitea-runner/go-mod";
        XDG_CACHE_HOME = "/var/cache/gitea-runner/xdg-cache";
        XDG_DATA_HOME = "/var/cache/gitea-runner/xdg-data";
        npm_config_manage_package_manager_versions = "false";
        COREPACK_ENABLE_AUTO_PIN = "0";
      };
      hostPackages = [
        pkgs.bash
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.gitMinimal
        pkgs.gnused
        pkgs.nodejs
        pkgs.wget
        pkgs.cacert
        config.nix.package
      ];
    };
  };

  users.groups.gitea-runner = { };
  users.users.gitea-runner = {
    isSystemUser = true;
    group = "gitea-runner";
    home = "/var/lib/gitea-runner/desktop";
  };

  systemd.services.gitea-runner-desktop.serviceConfig = {
    SupplementaryGroups = [ "forgejo-runner-secrets" ];
    CacheDirectory = "gitea-runner";
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "gitea-runner";
    Group = lib.mkForce "gitea-runner";
  };

  systemd.services.nscd.startLimitIntervalSec = 0;

  networking.hosts."127.0.0.1" = [
    "forge.barrettruth.com"
    "git.barrettruth.com"
  ];

  programs.ssh.extraConfig = ''
    Host forge.barrettruth.com git.barrettruth.com
        Port 2222
  '';

  programs.ssh.knownHosts."forge-self" = {
    hostNames = [
      "[forge.barrettruth.com]:2222"
      "[git.barrettruth.com]:2222"
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJlaElaGlwSxKvtujoAnGWSrZWlxZRdviq3Y9TgZCLZ/";
  };

  systemd.services.gitea-runner-cache-prune = {
    description = "Prune stale Forgejo runner build caches";
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -d /var/cache/gitea-runner ]; then
        ${pkgs.findutils}/bin/find /var/cache/gitea-runner -mindepth 1 -depth -mtime +14 -delete 2>/dev/null || true
      fi
    '';
  };

  systemd.timers.gitea-runner-cache-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  system.stateVersion = "24.11";
}
