{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 2;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "ibt=off"
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

  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    prime = {
      offload.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
  hardware.graphics.enable = true;
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
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "barrett"
    ];
  };

  system.stateVersion = "24.11";
}
