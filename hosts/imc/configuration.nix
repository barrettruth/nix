{ lib, ... }:
{
  networking.hostName = "imc";

  barrett.user.name = "bruth";

  barrett.user.gitEmail = "Barrett.Ruth@imc.com";
  barrett.user.personalGitDirs = [
    "~/dev/"
    "~/.config/nix/"
  ];

  barrett.tailscale.shieldsUp = true;
  barrett.tailscale.useAuthKey = false;

  barrett.mac.chrome = {
    app = "/Applications/Google Chrome.app";
    package = null;
    flags = [ "--silent-debugger-extension-api" ];
    unpackedMidnight = true;
  };

  barrett.mac.dock.apps = lib.mkAfter [
    "/Applications/Microsoft Outlook.app"
    "/Applications/Mattermost.app"
  ];

  barrett.mac.apps = lib.mkAfter [
    {
      key = "m";
      space = 8;
      bundleId = "Mattermost.Desktop";
      path = "/Applications/Mattermost.app";
      autostart = true;
    }
    {
      key = "o";
      space = 9;
      bundleId = "com.microsoft.Outlook";
      path = "/Applications/Microsoft Outlook.app";
      autostart = true;
    }
    {
      key = "z";
      space = 5;
      bundleId = "us.zoom.xos";
      path = "/Applications/zoom.us.app";
    }
  ];

  barrett.mac.floatingApps = lib.mkAfter [ "us.zoom.xos" ];
}
