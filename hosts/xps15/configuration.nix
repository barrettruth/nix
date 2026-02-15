{
  config,
  lib,
  pkgs,
  ...
}:

let
  tuigreet = lib.getExe pkgs.greetd.tuigreet;
in
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
  ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 2;
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
  programs.hyprland.enable = true;

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
    vt = 1;
    settings.default_session = {
      command = "${tuigreet} --time --asterisks --cmd '${lib.getExe config.users.users.barrett.shell} --login' --theme 'border=dark-gray;text=white;prompt=blue;time=dark-gray;action=dark-gray;button=blue;container=black;input=white'";
      user = "greeter";
    };
  };

  services.openssh.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  xdg.portal = lib.mkIf config.programs.hyprland.enable {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-hyprland
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
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  system.stateVersion = "24.11";
}
