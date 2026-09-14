{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../../common/privacy.nix ];

  config = lib.mkIf config.barrett.privacy.enable {
    networking.dns = [ "::1" ];

    launchd.daemons.dnscrypt-proxy.serviceConfig.EnvironmentVariables.SSL_CERT_FILE =
      "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };
}
