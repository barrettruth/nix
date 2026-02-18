{
  config,
  lib,
  pkgs,
  hyprland,
  ...
}:

let
  tuigreet = lib.getExe pkgs.tuigreet;
  loginShell = pkgs.writeShellScript "login-shell" ''
    exec $(getent passwd $(id -un) | cut -d: -f7) -l
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
    device = "nodev";
    useOSProber = true;
    configurationLimit = 2;
    gfxmodeEfi = "1920x1200,auto";
    fontSize = 36;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [
    "loglevel=3"
    "quiet"
  ];

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
    generateCaches = true;
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
      directory = /home/barrett/.config/nix
      directory = /home/barrett/.cache/nix/tarball-cache
  '';

  environment.binsh = "${pkgs.dash}/bin/dash";

  users.users.barrett = {
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

  programs.zsh = {
    enable = true;
    shellInit = ''
      export ZDOTDIR="$HOME/.config/zsh"
      export THEME="midnight"
    '';
  };
  programs.hyprland = {
    enable = true;
    package = hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
  };

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
      command = "${tuigreet} --time --asterisks --cmd ${loginShell}";
      user = "greeter";
    };
  };

  services.openssh.enable = true;
  services.tailscale.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  xdg.portal = lib.mkIf config.programs.hyprland.enable {
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

  security.sudo.enable = true;

  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "SF Pro Display" ];
    monospace = [ "Berkeley Mono" ];
    serif = [ "Times New Roman" ];
  };

  environment.systemPackages = with pkgs; [
    vim
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
      "barrett"
    ];
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  system.stateVersion = "24.11";
}
