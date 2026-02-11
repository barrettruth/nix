{
  lib,
  isNixOS,
  ...
}:
{
  services.hypridle = {
    enable = true;
    package = lib.mkIf (!isNixOS) null;
    settings = {
      general = {
        lock_cmd = "wp lock && hyprlock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "wp lock && hyprlock";
        }
        {
          timeout = 600;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1800;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };
}
