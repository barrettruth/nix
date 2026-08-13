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
}
