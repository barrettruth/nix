{ lib, ... }:
{
  networking.hostName = "imc";

  barrett.user.name = "bruth";

  barrett.tailscale.shieldsUp = true;
  barrett.tailscale.useAuthKey = false;

  barrett.mac.chrome = {
    app = "/Applications/Google Chrome.app";
    package = null;
  };

  barrett.mac.dock.apps = lib.mkAfter [
    "/Applications/Microsoft Outlook.app"
    "/Applications/Mattermost.app"
  ];

  barrett.mac.apps = lib.mkAfter [
    {
      key = "s";
      space = 4;
      bundleId = "Mattermost.Desktop";
      path = "/Applications/Mattermost.app";
    }
    {
      key = "m";
      space = 3;
      bundleId = "com.microsoft.Outlook";
      path = "/Applications/Microsoft Outlook.app";
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
