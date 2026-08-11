{ identity, ... }:
{
  networking.firewall.allowedTCPPorts = [
    80
    443
    2222
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = identity.email;
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";
  };
}
