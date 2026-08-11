{ config, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    open = false;
    nvidiaSettings = false;
    nvidiaPersistenced = true;
  };
  hardware.graphics.enable = true;
}
