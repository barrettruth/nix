{
  config,
  pkgs,
  lib,
  identity,
  ...
}:
let
  financeDir = "/opt/finance";
  financeHost = "finance.${identity.domain}";
  authHost = "auth.${identity.domain}";
  financePort = 3002;
  hasFinanceEnvSecret = builtins.pathExists ../../secrets/desktop/finance-env;
in
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
          proxy_set_header Host ${authHost};
          proxy_pass_request_body off;
          proxy_set_header X-Original-Method $request_method;
          proxy_set_header X-Original-URL $scheme://$host$request_uri;
        '';
      };
    };
  };

  users.users.finance = {
    isSystemUser = true;
    home = financeDir;
    group = "finance";
  };

  users.groups.finance = { };

  systemd.tmpfiles.rules = [ "d ${financeDir} 0755 finance finance -" ];

  systemd.services.finance = {
    description = "finance - private finance shell";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "${financeDir}/.next/standalone/server.js";
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = financeDir;
      ExecStart = "${pkgs.nodejs_22}/bin/node .next/standalone/server.js";
      Restart = "on-failure";
      RestartSec = 5;
      User = "finance";
      Group = "finance";
      StateDirectory = "finance";
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

  systemd.services.finance-deploy = {
    description = "Build and release finance from /opt/finance";
    after = [
      "network-online.target"
      "forgejo.service"
    ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gitMinimal
      pkgs.nodejs_22
      pkgs.pnpm
    ];
    environment = {
      HOME = "/root";
      NODE_ENV = "production";
      npm_config_manage_package_manager_versions = "false";
      COREPACK_ENABLE_AUTO_PIN = "0";
    };
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = financeDir;
      ExecStart = pkgs.writeShellScript "finance-deploy" ''
        set -euo pipefail
        git config --global --add safe.directory "*" || true
        bash ${financeDir}/scripts/deploy.sh
        chown -R finance:finance ${financeDir}
      '';
    };
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "finance-deploy.service" &&
          subject.user == "gitea-runner") {
        return polkit.Result.YES;
      }
    });
  '';
}
