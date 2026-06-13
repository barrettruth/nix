{
  identity,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIX/I64qCTMz4854Nms0bDTj4D7Ca7y6TYtCo+U3nC2t nix-remote-builder"
    ];
  };

  nix.settings.trusted-users = [
    "root"
    "nixremote"
  ];

  system.stateVersion = "24.11";
}
