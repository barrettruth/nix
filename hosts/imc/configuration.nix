{ lib, ... }:
{
  networking.hostName = "imc";

  barrett.user.name = "bruth";

  # The MDM owns sshd here and turns Remote Login back on, so inbound is
  # refused at the tailnet instead. Nothing sets
  # users.users.bruth.openssh.authorizedKeys.keys either, which leaves
  # /etc/ssh/nix_authorized_keys.d absent and key auth impossible.
  barrett.tailscale.shieldsUp = true;

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
      key = "m";
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
