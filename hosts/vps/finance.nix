{
  config,
  pkgs,
  lib,
  identity,
  mkVpsSecret,
  ...
}:
let
  financeHost = "finance.${identity.domain}";
  authHost = "auth.${identity.domain}";
  cookieDomain = identity.domain;
  financeAutheliaSecretNames = [
    "finance-authelia-jwt-secret"
    "finance-authelia-session-secret"
    "finance-authelia-storage-key"
    "finance-authelia-smtp-password"
    "finance-authelia-users"
  ];
  hasFinanceAutheliaSecrets = lib.all (
    secretName: builtins.pathExists ../../secrets/vps/${secretName}
  ) financeAutheliaSecretNames;
in
{
  services.nginx.virtualHosts.${authHost} = lib.mkIf hasFinanceAutheliaSecrets {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:9091";
  };

  sops.secrets = lib.optionalAttrs hasFinanceAutheliaSecrets {
    "finance-authelia-jwt-secret" = mkVpsSecret "finance-authelia-jwt-secret" {
      owner = "authelia-finance";
      group = "authelia-finance";
      mode = "0400";
      restartUnits = [ "authelia-finance.service" ];
    };
    "finance-authelia-session-secret" = mkVpsSecret "finance-authelia-session-secret" {
      owner = "authelia-finance";
      group = "authelia-finance";
      mode = "0400";
      restartUnits = [ "authelia-finance.service" ];
    };
    "finance-authelia-storage-key" = mkVpsSecret "finance-authelia-storage-key" {
      owner = "authelia-finance";
      group = "authelia-finance";
      mode = "0400";
      restartUnits = [ "authelia-finance.service" ];
    };
    "finance-authelia-smtp-password" = mkVpsSecret "finance-authelia-smtp-password" {
      owner = "authelia-finance";
      group = "authelia-finance";
      mode = "0400";
      restartUnits = [ "authelia-finance.service" ];
    };
    "finance-authelia-users" = mkVpsSecret "finance-authelia-users" {
      owner = "authelia-finance";
      group = "authelia-finance";
      mode = "0400";
      path = "/run/secrets/finance-authelia-users.yaml";
      restartUnits = [ "authelia-finance.service" ];
    };
    "finance-authelia-oidc-issuer-key" = mkVpsSecret "finance-authelia-oidc-issuer-key" {
      owner = "authelia-finance";
      group = "authelia-finance";
      mode = "0400";
      restartUnits = [ "authelia-finance.service" ];
    };
    "finance-authelia-oidc-hmac" = mkVpsSecret "finance-authelia-oidc-hmac" {
      owner = "authelia-finance";
      group = "authelia-finance";
      mode = "0400";
      restartUnits = [ "authelia-finance.service" ];
    };
  };

  services.authelia.instances.finance = lib.mkIf hasFinanceAutheliaSecrets {
    enable = true;
    secrets = {
      jwtSecretFile = config.sops.secrets."finance-authelia-jwt-secret".path;
      sessionSecretFile = config.sops.secrets."finance-authelia-session-secret".path;
      storageEncryptionKeyFile = config.sops.secrets."finance-authelia-storage-key".path;
      oidcIssuerPrivateKeyFile = config.sops.secrets."finance-authelia-oidc-issuer-key".path;
      oidcHmacSecretFile = config.sops.secrets."finance-authelia-oidc-hmac".path;
    };
    environmentVariables = {
      AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE = config.sops.secrets."finance-authelia-smtp-password".path;
    };
    settings = {
      theme = "auto";
      default_2fa_method = "webauthn";
      server.address = "tcp://127.0.0.1:9091/";
      log = {
        level = "info";
        format = "text";
      };
      authentication_backend.file.path = config.sops.secrets."finance-authelia-users".path;
      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = [ authHost ];
            policy = "bypass";
          }
          {
            domain = [ financeHost ];
            policy = "two_factor";
          }
        ];
      };
      session = {
        name = "authelia_session";
        same_site = "lax";
        expiration = "8h";
        inactivity = "30m";
        remember_me = "1M";
        cookies = [
          {
            domain = cookieDomain;
            authelia_url = "https://${authHost}";
            default_redirection_url = "https://${identity.domain}";
          }
        ];
      };
      storage.local.path = "/var/lib/authelia-finance/db.sqlite3";
      notifier.smtp = {
        address = "submissions://smtp.resend.com:2465";
        timeout = "10s";
        username = "resend";
        sender = "barrettruth <noreply@${identity.domain}>";
        subject = "[barrettruth] {title}";
        startup_check_address = "br@${identity.domain}";
        tls.server_name = "smtp.resend.com";
      };
      webauthn.display_name = "barrettruth";
      identity_providers.oidc.clients = [
        {
          client_id = "headscale";
          client_name = "Headscale";
          client_secret = "$pbkdf2-sha512$310000$qJDvDKtAYGI.gNXjK9DYJQ$5DZkIUxr1W6HN0y4MNWC08SKLfMAVGhXhVjIMHCxqPYyvNStVK7iyXLICFhFviB5isVNx.XAQsOnb1YRzWjZaw";
          public = false;
          authorization_policy = "two_factor";
          consent_mode = "implicit";
          redirect_uris = [
            "https://headscale.${identity.domain}/oidc/callback"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
          ];
          token_endpoint_auth_method = "client_secret_basic";
        }
      ];
    };
  };

}
