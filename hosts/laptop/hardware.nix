{ ... }:

{
  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "ibt=off"
  ];

  hardware.nvidia = {
    open = false;
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    prime = {
      offload.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  hardware.graphics.enable = true;
}
