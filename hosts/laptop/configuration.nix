{
  config,
  pkgs,
  identity,
  mkLaptopSecret,
  desktopBuildPool,
  ...
}:

let
  username = config.barrett.user.name;
in
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    useOSProber = true;
    configurationLimit = 5;
    gfxmodeEfi = "1920x1200,auto";
    fontSize = 36;
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
  boot.kernelParams = [
    "loglevel=3"
    "quiet"
    "i8042.noaux"
  ];
  boot.tmp.cleanOnBoot = true;

  boot.kernel.sysctl = {
    "net.ipv4.ipfrag_time" = 3;
    "net.ipv4.ipfrag_high_thresh" = 134217728;
    "net.core.rmem_max" = 2147483647;
  };

  networking.hostName = "laptop";
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General.EnableNetworkConfiguration = true;
      Network.NameResolvingService = "resolvconf";
      Settings.AutoConnect = true;
    };
  };

  services.automatic-timezoned.enable = true;
  services.geoclue2.enable = true;
  services.pcscd.enable = true;
  services.fwupd.enable = true;
  documentation.man = {
    enable = true;
    cache.enable = true;
  };

  i18n.defaultLocale = "en_US.UTF-8";

  security.pam.services.hyprlock = { };

  security.doas = {
    enable = true;
    extraRules = [
      {
        groups = [ "wheel" ];
        persist = true;
      }
    ];
  };

  environment.binsh = "${pkgs.dash}/bin/dash";

  users.users.root.openssh.authorizedKeys.keys = identity.sshKeys;

  users.users.${username} = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = identity.sshKeys;
    extraGroups = [
      "wheel"
      "docker"
      "libvirt"
      "storage"
      "power"
    ];
    shell = pkgs.zsh;
  };

  programs.chromium = {
    enable = true;
    extraOpts = {
      BrowserSigninEnabled = 1;
      SyncDisabled = false;
      SpellCheckServiceEnabled = true;
      SearchSuggestEnabled = true;
      UrlKeyedAnonymizedDataCollectionEnabled = true;
      HttpsOnlyMode = "force_enabled";
      BookmarkBarEnabled = false;
      PasswordManagerEnabled = false;
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;
      TranslateEnabled = true;
      ImportBookmarks = false;
      SafeBrowsingProtectionLevel = 1;
      DnsOverHttpsMode = "automatic";
      BlockThirdPartyCookies = true;
      CookieAllowedForUrls = [ "[*.]shibidp.virginia.edu" ];
      RestoreOnStartup = 1;
      NewTabPageLocation = "chrome-extension://demmbkpegigoeiappcbliinlijmeoaop/newtab.html";
    };
    extensions = [
      # Bitwarden Password Manager
      "nngceckbapebfimnlniiiahkandclblb"
      # uBlock Origin Lite
      "ddkjiahejlhfcafbddmgiahcphecmpfh"
      # React Developer Tools
      "fmkadmapgofadopljbjfkapdkoienihi"
    ];
  };

  # programs.hyprland = {
  #   enable = true;
  #   portalPackage = pkgs.xdg-desktop-portal-hyprland;
  # };

  hardware.bluetooth.enable = true;

  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          capslock = "overload(control, esc)";
          leftcontrol = "capslock";
          leftmeta = "A-x";
          rightalt = "f13";
        };
      };
    };
  };

  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
      hplip
      brlaser
      brgenml1lpr
      brgenml1cupswrapper
    ];
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    jack.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  services.upower.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
    config.common = {
      default = [
        "hyprland"
        "gtk"
      ];
    };
  };

  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  security.sudo.enable = true;
  security.rtkit.enable = true;

  fonts.packages = with pkgs; [
    dejavu_fonts
    freefont_ttf
    gyre-fonts
    liberation_ttf
    unifont
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "SF Pro Display" ];
    monospace = [ "Berkeley Mono" ];
    serif = [ "Times New Roman" ];
  };

  environment.systemPackages = with pkgs; [
    wget
    git
    dash
    cloudflared
    ntfs3g
    efibootmgr
    dmidecode
    alsa-utils
  ];

  programs.ssh.extraConfig = ''
    Host desktop-builder
        HostName desktop
        User nixremote
        IdentityFile /run/secrets/desktop-builder-key
        IdentitiesOnly yes
        BatchMode yes
    Host spark
        HostName spark-1
        User barrett
        HostKeyAlias spark
    Host forge.barrettruth.com git.barrettruth.com
        Port 2222
  '';

  nix.settings = {
    use-xdg-base-directories = true;
    trusted-users = [
      "root"
      username
    ];
  };

  nix.distributedBuilds = false;
  nix.settings.builders-use-substitutes = true;
  nix.buildMachines = [
    {
      hostName = "desktop";
      sshUser = "nixremote";
      sshKey = config.sops.secrets."desktop-builder-key".path;
      systems = [ "x86_64-linux" ];
      maxJobs = desktopBuildPool.cpuSlots;
      speedFactor = 2;
      supportedFeatures = [
        "big-parallel"
        "kvm"
        "nixos-test"
        "benchmark"
      ];
    }
  ];

  sops.secrets."desktop-builder-key" = mkLaptopSecret "desktop-builder-key" {
    owner = username;
    group = "users";
    mode = "0400";
  };

  networking.hosts = identity.tailnetHosts;

  programs.ssh.knownHosts.desktop = {
    hostNames = [
      "desktop"
      "desktop.ts.barrettruth.com"
      "100.64.0.1"
    ];
    publicKey = identity.hostKeys.desktop;
  };

  programs.ssh.knownHosts."forge-tailnet" = {
    hostNames = [
      "[forge.barrettruth.com]:2222"
      "[git.barrettruth.com]:2222"
    ];
    publicKey = identity.hostKeys.forge-tailnet;
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "";
  };

  system.activationScripts.pruneLaptopSystemGenerations.text = ''
    if [ -e /nix/var/nix/profiles/system ]; then
      ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5
    fi
  '';

  systemd.services.nix-gc.serviceConfig.ExecStartPre =
    "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5";

  systemd.services.nix-gc.serviceConfig.ExecStartPost =
    "/nix/var/nix/profiles/system/bin/switch-to-configuration boot";

  system.stateVersion = "24.11";
}
