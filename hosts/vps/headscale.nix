{
  config,
  identity,
  mkVpsSecret,
  ...
}:
let
  headscaleHost = "headscale.${identity.domain}";
  headscalePort = 8085;
in
{
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = headscalePort;
    settings = {
      server_url = "https://${headscaleHost}";
      dns = {
        magic_dns = true;
        base_domain = "ts.${identity.domain}";
        nameservers.global = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
      oidc = {
        issuer = "https://auth.finance.${identity.domain}";
        client_id = "headscale";
        client_secret_path = config.sops.secrets."headscale-oidc-client-secret".path;
        scope = [
          "openid"
          "profile"
          "email"
        ];
        allowed_domains = [ identity.domain ];
      };
    };
  };

  services.nginx.virtualHosts.${headscaleHost} = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString headscalePort}";
      proxyWebsockets = true;
    };
  };

  sops.secrets."headscale-oidc-client-secret" = mkVpsSecret "headscale-oidc-client-secret" {
    owner = "headscale";
    group = "headscale";
    mode = "0400";
    restartUnits = [ "headscale.service" ];
  };
}
