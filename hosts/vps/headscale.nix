{
  config,
  identity,
  mkVpsSecret,
  pkgs,
  ...
}:
let
  headscaleHost = "headscale.${identity.domain}";
  headscalePort = 8085;
  waitForOidc = pkgs.writeShellScript "wait-for-oidc" ''
    for _ in $(seq 1 60); do
      ${pkgs.curl}/bin/curl -fsS -o /dev/null \
        https://auth.${identity.domain}/.well-known/openid-configuration && exit 0
      sleep 1
    done
    echo "authelia did not serve OIDC discovery within 60s" >&2
    exit 1
  '';
in
{
  systemd.services.headscale = {
    after = [
      "nginx.service"
      "authelia-finance.service"
    ];
    wants = [
      "nginx.service"
      "authelia-finance.service"
    ];
    serviceConfig.ExecStartPre = [ "${waitForOidc}" ];
  };

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = headscalePort;
    settings = {
      server_url = "https://${headscaleHost}";
      dns = {
        magic_dns = true;
        base_domain = identity.tailnetDomain;
        nameservers.global = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
      oidc = {
        issuer = "https://auth.${identity.domain}";
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
