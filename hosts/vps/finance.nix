{
  config,
  pkgs,
  lib,
  identity,
  mkVpsSecret,
  ...
}:
let
  financeDir = "/opt/finance";
  financeHost = "finance.${identity.domain}";
  financeAuthHost = "auth.finance.${identity.domain}";
  financeCookieDomain = "finance.${identity.domain}";
  financePort = 3002;
  hasFinanceEnvSecret = builtins.pathExists ../../secrets/vps/finance-env;
  financeAutheliaSecretNames = [
    "finance-authelia-jwt-secret"
    "finance-authelia-session-secret"
    "finance-authelia-storage-key"
    "finance-authelia-users"
  ];
  hasFinanceAutheliaSecrets = lib.all (
    secretName: builtins.pathExists ../../secrets/vps/${secretName}
  ) financeAutheliaSecretNames;
in
{
  services.nginx.virtualHosts.${financeHost} = lib.mkMerge [
    {
      enableACME = true;
      forceSSL = true;
    }
    (
      if hasFinanceAutheliaSecrets then
        {
          locations = {
            "/" = {
              proxyPass = "http://127.0.0.1:${toString financePort}";
              extraConfig = ''
                auth_request /internal/authelia/authz;
                auth_request_set $user $upstream_http_remote_user;
                auth_request_set $groups $upstream_http_remote_groups;
                auth_request_set $name $upstream_http_remote_name;
                auth_request_set $email $upstream_http_remote_email;
                auth_request_set $redirection_url $upstream_http_location;
                error_page 401 =302 $redirection_url;
                proxy_set_header Remote-User $user;
                proxy_set_header Remote-Groups $groups;
                proxy_set_header Remote-Email $email;
                proxy_set_header Remote-Name $name;
              '';
            };
            "/internal/authelia/authz" = {
              proxyPass = "http://127.0.0.1:9091/api/authz/auth-request";
              extraConfig = ''
                internal;
                proxy_pass_request_body off;
                proxy_set_header Content-Length "";
                proxy_set_header Connection "";
                proxy_set_header X-Original-Method $request_method;
                proxy_set_header X-Original-URL $scheme://$host$request_uri;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-Host $host;
                proxy_set_header X-Forwarded-URI $request_uri;
                proxy_set_header X-Forwarded-For $remote_addr;
              '';
            };
          };
        }
      else
        {
          locations."/".return = "503";
        }
    )
  ];

  services.nginx.virtualHosts.${financeAuthHost} = lib.mkIf hasFinanceAutheliaSecrets {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:9091";
  };

  sops.secrets =
    (lib.optionalAttrs hasFinanceEnvSecret {
      "finance-env" = mkVpsSecret "finance-env" {
        owner = "finance";
        group = "finance";
        mode = "0400";
        restartUnits = [ "finance.service" ];
      };
    })
    // (lib.optionalAttrs hasFinanceAutheliaSecrets {
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
      "finance-authelia-users" = mkVpsSecret "finance-authelia-users" {
        owner = "authelia-finance";
        group = "authelia-finance";
        mode = "0400";
        restartUnits = [ "authelia-finance.service" ];
      };
    });

  services.authelia.instances.finance = lib.mkIf hasFinanceAutheliaSecrets {
    enable = true;
    secrets = {
      jwtSecretFile = config.sops.secrets."finance-authelia-jwt-secret".path;
      sessionSecretFile = config.sops.secrets."finance-authelia-session-secret".path;
      storageEncryptionKeyFile = config.sops.secrets."finance-authelia-storage-key".path;
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
            domain = [ financeAuthHost ];
            policy = "bypass";
          }
          {
            domain = [ financeHost ];
            policy = "two_factor";
          }
        ];
      };
      session = {
        name = "finance_authelia_session";
        same_site = "lax";
        expiration = "8h";
        inactivity = "30m";
        remember_me = "1M";
        cookies = [
          {
            domain = financeCookieDomain;
            authelia_url = "https://${financeAuthHost}";
            default_redirection_url = "https://${financeHost}";
          }
        ];
      };
      storage.local.path = "/var/lib/authelia-finance/db.sqlite3";
      notifier.filesystem.filename = "/var/lib/authelia-finance/notification.txt";
      webauthn.display_name = "finance";
    };
  };

  users.users.finance = {
    isSystemUser = true;
    home = financeDir;
    group = "finance";
  };

  users.groups.finance = { };

  systemd.tmpfiles.rules = [ "d ${financeDir} 0750 finance finance -" ];

  systemd.services.finance = {
    description = "finance - private finance shell";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig =
      {
        Type = "simple";
        WorkingDirectory = financeDir;
        ExecStart = "${pkgs.nodejs_22}/bin/node .next/standalone/server.js";
        Restart = "on-failure";
        RestartSec = 5;
        User = "finance";
        Group = "finance";
        StateDirectory = "finance";
        ConditionPathExists = "${financeDir}/.next/standalone/server.js";
      }
      // lib.optionalAttrs hasFinanceEnvSecret {
        EnvironmentFile = config.sops.secrets."finance-env".path;
      };
    environment = {
      NODE_ENV = "production";
      PORT = toString financePort;
      HOSTNAME = "127.0.0.1";
      FINANCE_PUBLIC_ORIGIN = "https://${financeHost}";
      FINANCE_AUTH_USER_HEADERS = "remote-user,x-auth-request-user,x-forwarded-user";
      FINANCE_AUTH_NAME_HEADERS = "remote-name,x-auth-request-name,x-forwarded-name";
      FINANCE_AUTH_EMAIL_HEADERS = "remote-email,x-auth-request-email,x-forwarded-email";
      FINANCE_AUTH_GROUPS_HEADERS = "remote-groups,x-auth-request-groups,x-forwarded-groups";
    };
  };
}
