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
      key = "m";
      path = "/Applications/Mattermost.app";
    }
    {
      path = "/Applications/Microsoft Outlook.app";
    }
    {
      path = "/Applications/zoom.us.app";
    }
  ];

  # Zoom's call windows resize themselves and fight the tiler.
  barrett.mac.floatingApps = lib.mkAfter [ "us.zoom.xos" ];
}
