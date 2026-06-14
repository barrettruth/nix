{
  identity,
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
}
