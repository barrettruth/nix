{
  lib,
  pkgs,
  hostConfig,
  ...
}:
{
  config = lib.mkIf hostConfig.enableX11 {
    users.users.${hostConfig.username}.packages = with pkgs; [
      xclip
      xrandr
      xdpyinfo
    ];
  };
}
