{ lib, ... }:
{
  networking.hostName = "imc";

  barrett.user.name = "bruth";

  barrett.mac.chrome = {
    app = "/Applications/Google Chrome.app";
    package = null;
  };

  barrett.mac.dock.apps = lib.mkAfter [
    "/Applications/Microsoft Outlook.app"
    "/Applications/Mattermost.app"
  ];

  barrett.mac.workspaceApps = lib.mkAfter [
    {
      workspace = "3";
      path = "/Applications/Mattermost.app";
      bundleId = "Mattermost.Desktop";
    }
    {
      workspace = "4";
      path = "/Applications/Microsoft Outlook.app";
      bundleId = "com.microsoft.Outlook";
    }
    {
      workspace = "5";
      path = "/Applications/zoom.us.app";
      bundleId = "us.zoom.xos";
    }
  ];
}
