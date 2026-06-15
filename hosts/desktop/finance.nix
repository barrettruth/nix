{
  config,
  pkgs,
  lib,
  identity,
  mkDesktopSecret,
  ...
}:
let
  inherit (import ../../modules/nixos/common/service-helpers.nix { inherit pkgs lib; })
    mkNextjsApp
    mkDeployService
    ;
  financeDir = "/opt/finance";
  financeHost = "finance.${identity.domain}";
  authHost = "auth.${identity.domain}";
  financePort = 3002;
  hasFinanceEnvSecret = builtins.pathExists ../../secrets/desktop/finance-env;
in
lib.mkMerge [
  (mkNextjsApp {
    name = "finance";
    dir = financeDir;
    user = "finance";
    group = "finance";
    port = financePort;
    description = "finance - private finance shell";
    environmentFile = if hasFinanceEnvSecret then config.sops.secrets."finance-env".path else null;
    environment = {
      FINANCE_PUBLIC_ORIGIN = "https://${financeHost}";
      FINANCE_AUTH_USER_HEADERS = "remote-user,x-auth-request-user,x-forwarded-user";
      FINANCE_AUTH_NAME_HEADERS = "remote-name,x-auth-request-name,x-forwarded-name";
      FINANCE_AUTH_EMAIL_HEADERS = "remote-email,x-auth-request-email,x-forwarded-email";
      FINANCE_AUTH_GROUPS_HEADERS = "remote-groups,x-auth-request-groups,x-forwarded-groups";
    };
  })
  (mkDeployService {
    name = "finance";
    dir = financeDir;
    user = "root";
    group = "root";
    after = [
      "network-online.target"
      "forgejo.service"
    ];
    safeDirectories = [
      financeDir
      "/var/lib/forgejo/repositories/barrettruth/finance.git"
    ];
    postScript = "chown -R finance:finance ${financeDir}";
  })
  {
    services.nginx.virtualHosts.${financeHost} = {
      enableACME = true;
      forceSSL = true;
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
            proxy_set_header X-Auth-Request-User "";
            proxy_set_header X-Auth-Request-Name "";
            proxy_set_header X-Auth-Request-Email "";
            proxy_set_header X-Auth-Request-Groups "";
            proxy_set_header X-Forwarded-User "";
            proxy_set_header X-Forwarded-Name "";
            proxy_set_header X-Forwarded-Email "";
            proxy_set_header X-Forwarded-Groups "";
            proxy_set_header Remote-User $user;
            proxy_set_header Remote-Groups $groups;
            proxy_set_header Remote-Email $email;
            proxy_set_header Remote-Name $name;
          '';
        };
        "/internal/authelia/authz" = {
          proxyPass = "https://${authHost}/api/authz/auth-request";
          recommendedProxySettings = false;
          extraConfig = ''
            internal;
            proxy_ssl_server_name on;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
            proxy_ssl_verify_depth 3;
            proxy_set_header Host ${authHost};
            proxy_pass_request_body off;
            proxy_set_header X-Original-Method $request_method;
            proxy_set_header X-Original-URL $scheme://$host$request_uri;
          '';
        };
      };
    };
  }
  (lib.optionalAttrs hasFinanceEnvSecret {
    sops.secrets."finance-env" = mkDesktopSecret "finance-env" {
      owner = "finance";
      group = "finance";
      mode = "0400";
      restartUnits = [ "finance.service" ];
    };
  })
]
