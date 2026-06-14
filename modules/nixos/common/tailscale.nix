{
  config,
  identity,
  mkHostSecret,
  ...
}:
{
  sops.secrets."headscale-authkey" = mkHostSecret config.networking.hostName "headscale-authkey" {
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."headscale-authkey".path;
    extraUpFlags = [
      "--login-server"
      "https://headscale.${identity.domain}"
    ];
  };
}
