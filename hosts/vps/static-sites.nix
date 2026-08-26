{
  pkgs,
  lib,
  identity,
  ...
}:
let
  webDeployUser = "web-deploy";
  webDeployGroup = "web-deploy";
  webDeployUid = 990;
  webDeployGid = 988;
  webDeployPublicKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF4QXLB3ZH77HJwTbcYB/52jg7kAT+E6BwACf1ianOXS forgejo-actions-web-deploy-2026-05-01"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINc5ql/WCnABQZEQmekLW5LT7Ej2u/APFP13PjM3Y9Zs forgejo-actions-ts-deploy-2026-07-08"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBkw93EYiycZClQlKB2tynntKA2OqzCLq1VjMrsXUC25 github-actions-web-deploy-2026-08-26"
  ];
  staticWebRoots = {
    "barrettruth.com" = "/srv/www/barrettruth.com/current";
    "philipmruth.com" = "/srv/www/philipmruth.com/current";
    "ts.barrettruth.com" = "/srv/www/ts.barrettruth.com/current";
    "bazel-language-server.com" = "/srv/www/bazel-language-server.com/current";
    "vimdoc-language-server.com" = "/srv/www/vimdoc-language-server.com/current";
  };
  fontOrigins = [
    "https://www.bazel-language-server.com"
    "https://www.vimdoc-language-server.com"
  ];
  githubOwner = "barrettruth";
  mkStaticSiteHost = root: {
    enableACME = true;
    forceSSL = true;
    inherit root;
    extraConfig = ''
      limit_req zone=static_site_per_ip burst=120 nodelay;
      limit_conn static_site_conn_per_ip 40;
      error_page 404 /404.html;
    '';
    locations."/" = {
      tryFiles = "$uri $uri/ =404";
      extraConfig = ''
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      '';
    };
    locations."~* \\.(?:css|js|mjs|png|jpg|jpeg|gif|webp|svg|ico|pdf|ttf|otf|woff|woff2)$".extraConfig =
      ''
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
      '';
  };
  mkBarrettruthHost =
    root:
    lib.recursiveUpdate (mkStaticSiteHost root) {
      locations."~* ^/fonts/.*\\.(?:ttf|otf|woff|woff2)$".extraConfig = ''
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        add_header Access-Control-Allow-Origin $font_cors_origin always;
        add_header Vary "Origin" always;
      '';
    };
  mkRedirectHost = target: {
    enableACME = true;
    forceSSL = true;
    locations."/".return = "301 https://${target}$request_uri";
  };
  mkForgeRedirectHost = {
    enableACME = true;
    forceSSL = true;
    locations."= /".return = "301 https://github.com/${githubOwner}";
    locations."/".return = "301 https://github.com$request_uri";
  };
in
{
  services.nginx = {
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=static_site_per_ip:10m rate=20r/s;
      limit_conn_zone $binary_remote_addr zone=static_site_conn_per_ip:10m;

      map $http_origin $font_cors_origin {
        default "";
        ${lib.concatMapStringsSep "\n  " (o: ''"${o}" $http_origin;'') fontOrigins}
      }
    '';
    virtualHosts."www.${identity.domain}" = mkBarrettruthHost staticWebRoots."barrettruth.com";
    virtualHosts.${identity.domain} = mkRedirectHost "www.${identity.domain}";
    virtualHosts."www.barrettruth.sh" = mkBarrettruthHost staticWebRoots."barrettruth.com";
    virtualHosts."barrettruth.sh" = mkRedirectHost "www.barrettruth.sh";
    virtualHosts."www.philipmruth.com" = mkStaticSiteHost staticWebRoots."philipmruth.com";
    virtualHosts."philipmruth.com" = mkRedirectHost "www.philipmruth.com";
    virtualHosts."ts.${identity.domain}" = mkStaticSiteHost staticWebRoots."ts.barrettruth.com";
    virtualHosts."forge.${identity.domain}" = mkForgeRedirectHost;
    virtualHosts."git.${identity.domain}" = mkForgeRedirectHost;
    virtualHosts."www.vimdoc-language-server.com" =
      mkStaticSiteHost
        staticWebRoots."vimdoc-language-server.com";
    virtualHosts."vimdoc-language-server.com" = mkRedirectHost "www.vimdoc-language-server.com";
    virtualHosts."vimdoc-language-server.${identity.domain}" =
      mkRedirectHost "www.vimdoc-language-server.com";
    virtualHosts."www.bazel-language-server.com" =
      mkStaticSiteHost
        staticWebRoots."bazel-language-server.com";
    virtualHosts."bazel-language-server.com" = mkRedirectHost "www.bazel-language-server.com";
    virtualHosts."bazel-language-server.${identity.domain}" =
      mkRedirectHost "www.bazel-language-server.com";
  };

  users.groups.${webDeployGroup}.gid = webDeployGid;

  users.users.${webDeployUser} = {
    isSystemUser = true;
    uid = webDeployUid;
    group = webDeployGroup;
    home = "/var/lib/${webDeployUser}";
    createHome = true;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = webDeployPublicKeys;
  };

  systemd.tmpfiles.rules = [
    "d /srv/www 0755 root root -"
    "d /srv/www/barrettruth.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/barrettruth.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/philipmruth.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/philipmruth.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/ts.barrettruth.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/ts.barrettruth.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/vimdoc-language-server.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/vimdoc-language-server.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/bazel-language-server.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/bazel-language-server.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
  ];
}
