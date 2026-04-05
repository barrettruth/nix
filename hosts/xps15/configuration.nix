{
  lib,
  pkgs,
  hostConfig,
  ...
}:

let
  inherit (hostConfig) username homeDirectory;
  tuigreet = lib.getExe pkgs.tuigreet;
  hyprSession = pkgs.writeShellScript "hypr-session" ''
    [ -e /etc/set-environment ] && . /etc/set-environment
    _tf="''${XDG_STATE_HOME:-$HOME/.local/state}/theme"
    THEME="$(cat "$_tf" 2>/dev/null)" || THEME="midnight"
    export THEME
    unset _tf
    exec start-hyprland
  '';
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
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ipfrag_time" = 3;
    "net.ipv4.ipfrag_high_thresh" = 134217728;
    "net.core.rmem_max" = 2147483647;
  };

  networking.hostName = "xps15";
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General.EnableNetworkConfiguration = true;
      Settings.AutoConnect = true;
    };
  };

  services.automatic-timezoned.enable = true;
  services.geoclue2.enable = true;
  services.pcscd.enable = true;
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
        keepEnv = true;
      }
    ];
  };

  environment.etc."gitconfig".text = ''
    [safe]
      directory = ${homeDirectory}/.config/nix
      directory = ${homeDirectory}/.cache/nix/tarball-cache
      directory = ${homeDirectory}/.cache/nix/tarball-cache-v2
  '';

  environment.binsh = "${pkgs.dash}/bin/dash";

  users.users.${username} = {
    isNormalUser = true;
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

  programs.zsh = {
    enable = true;
    shellInit = ''
      export ZDOTDIR="$HOME/.config/zsh"
      THEME="$(cat "''${XDG_STATE_HOME:-$HOME/.local/state}/theme" 2>/dev/null)" || THEME="midnight"
      [ -z "$THEME" ] && THEME="midnight"
      export THEME
    '';
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

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${tuigreet} --time --asterisks --cmd ${hyprSession}";
      user = "greeter";
    };
  };

  services.openssh.enable = true;
  services.tailscale.enable = true;

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

  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "SF Pro Display" ];
    monospace = [ "Berkeley Mono" ];
    serif = [ "Times New Roman" ];
  };

  environment.systemPackages = with pkgs; [
    wget
    git
    dash
    ntfs3g
    efibootmgr
    dmidecode
  ];

  nix.settings = {
    auto-optimise-store = true;
    use-xdg-base-directories = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      username
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  systemd.services.nix-gc.serviceConfig.ExecStartPost =
    "/nix/var/nix/profiles/system/bin/switch-to-configuration boot";

  system.stateVersion = "24.11";
}
