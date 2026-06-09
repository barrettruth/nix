{
  config,
  pkgs,
  lib,
  modulesPath,
  inputs,
  identity,
  mkVpsSecret,
  ...
}:
let
  forgejoSigningKeyId = "AEB0C5593951F51260C1388DF09FD58E4737029E";
  forgejoSigningTrustFingerprint = "F2CC7F7FD33F423B7A31B4E3A6C96C9349D2FC81";
  forgejoOauthSources = {
    github = {
      provider = "github";
      displayName = "GitHub";
    };
    google = {
      provider = "gplus";
      displayName = "Google";
    };
    gitlab = {
      provider = "gitlab";
      displayName = "GitLab";
    };
  };
  forgejoOauthSecretNames = lib.flatten (
    lib.mapAttrsToList (name: _: [
      "forgejo-oauth-${name}-id"
      "forgejo-oauth-${name}-secret"
    ]) forgejoOauthSources
  );
  webDeployUser = "web-deploy";
  webDeployGroup = "web-deploy";
  webDeployPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF4QXLB3ZH77HJwTbcYB/52jg7kAT+E6BwACf1ianOXS forgejo-actions-web-deploy-2026-05-01";
  staticWebRoots = {
    "barrettruth.com" = "/srv/www/barrettruth.com/current";
    "philipmruth.com" = "/srv/www/philipmruth.com/current";
    "vimdoc-language-server.com" = "/srv/www/vimdoc-language-server.com/current";
  };
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
        add_header Access-Control-Allow-Origin "https://www.vimdoc-language-server.com" always;
        add_header Vary "Origin" always;
      '';
    };
  mkRedirectHost = target: {
    enableACME = true;
    forceSSL = true;
    locations."/".return = "301 https://${target}$request_uri";
  };
  forgejoMutableAssetProxy = {
    proxyPass = "http://127.0.0.1:3000";
    extraConfig = ''
      proxy_hide_header Cache-Control;
      add_header Cache-Control $forgejo_asset_cache_control always;
    '';
  };
  forgejoStatsAssetProxy = {
    proxyPass = "http://127.0.0.1:3000";
    extraConfig = ''
      proxy_hide_header Cache-Control;
      add_header Cache-Control "public, max-age=900" always;
    '';
  };
  forgejoImmutableAssetProxy = {
    proxyPass = "http://127.0.0.1:3000";
    extraConfig = ''
      proxy_hide_header Cache-Control;
      add_header Cache-Control "public, max-age=31536000, immutable" always;
    '';
  };
  forgejoGpgAgentConf = pkgs.writeText "gpg-agent.conf" ''
    allow-loopback-pinentry
  '';
  forgejoGpgProgram = pkgs.writeShellScript "forgejo-gpg" ''
    exec ${pkgs.gnupg}/bin/gpg \
      --batch \
      --pinentry-mode loopback \
      --passphrase-file "$CREDENTIALS_DIRECTORY/gpg-passphrase" \
      "$@"
  '';
  forgejoBrandingSvg = pkgs.writeText "forgejo-delta-symbol.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
      <style>
        .delta { fill: #121212; }
        @media (prefers-color-scheme: dark) { .delta { fill: #e0e0e0; } }
      </style>
      <g transform="translate(171.5, 831) scale(1, -1)">
        <path class="delta" d="M629 0H28V28L317 662H355L629 28ZM310 539 108 80H495L314 539Z"/>
      </g>
    </svg>
  '';
  forgejoAvatarSvg = pkgs.writeText "forgejo-delta-avatar.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
      <rect width="1000" height="1000" fill="#ffffff"/>
      <g transform="translate(171.5, 831) scale(1, -1)">
        <path fill="#121212" d="M629 0H28V28L317 662H355L629 28ZM310 539 108 80H495L314 539Z"/>
      </g>
    </svg>
  '';
  forgejoBrandingAssets =
    pkgs.runCommand "forgejo-branding-assets"
      {
        nativeBuildInputs = [
          pkgs.librsvg
          pkgs.oxipng
        ];
      }
      ''
        mkdir -p $out
        cp ${forgejoBrandingSvg} $out/logo.svg
        cp ${forgejoBrandingSvg} $out/favicon.svg
        rsvg-convert -w 512 -h 512 ${forgejoBrandingSvg} > $out/logo.png
        rsvg-convert -w 192 -h 192 ${forgejoBrandingSvg} > $out/favicon.png
        rsvg-convert -w 180 -h 180 ${forgejoBrandingSvg} > $out/apple-touch-icon.png
        rsvg-convert -w 256 -h 256 ${forgejoAvatarSvg} > $out/avatar.png
        cp $out/avatar.png $out/avatar_default.png
        oxipng -o 4 --strip safe $out/*.png
      '';
  pierreForgejo = inputs.pierrejo.lib.mkPierreForgejo { inherit pkgs; };
  forgejoCustom = pkgs.callPackage ../../pkgs/forgejo-custom {
    inherit pierreForgejo;
    barrettWebfonts = inputs.fonts.packages.${pkgs.stdenv.hostPlatform.system}.web;
  };

  forgejoStixTwoFontFile = pkgs.runCommand "stix-two-text.ttf" { } ''
    cp '${pkgs.stix-two}/share/fonts/truetype/STIXTwoText[wght].ttf' $out
  '';

  forgejoFooterTmpl = pkgs.writeText "footer.tmpl" "";
  forgejoFooterContentTmpl = pkgs.writeText "footer_content.tmpl" "";
  forgejoMailFooterSimpleTmpl = pkgs.writeText "footer_simple.tmpl" "";
  forgejoMailActivateTmpl = pkgs.writeText "activate.tmpl" ''
    <!DOCTYPE html>
    <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <meta name="format-detection" content="telephone=no,date=no,address=no,email=no,url=no">
    </head>

    {{$activate_url := printf "%suser/activate?code=%s" AppUrl (QueryEscape .Code)}}
    <body>
      <p>{{.locale.Tr "mail.activate_account.text_1" (.DisplayName|DotEscape) AppName}}</p><br>
      <p>{{.locale.Tr "mail.activate_account.text_2" .ActiveCodeLives}}</p>
      <p><a href="{{$activate_url}}">{{$activate_url}}</a></p><br>
      <p>{{.locale.Tr "mail.link_not_working_do_paste"}}</p>
    </body>
    </html>
  '';
  forgejoMailActivateEmailTmpl = pkgs.writeText "activate_email.tmpl" ''
    <!DOCTYPE html>
    <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <meta name="format-detection" content="telephone=no,date=no,address=no,email=no,url=no">
    </head>

    {{$activate_url := printf "%suser/activate_email?code=%s&email=%s" AppUrl (QueryEscape .Code) (QueryEscape .Email)}}
    <body>
      <p>{{.locale.Tr "mail.hi_user_x" (.DisplayName|DotEscape)}}</p><br>
      <p>{{.locale.Tr "mail.activate_email.text" .ActiveCodeLives}}</p>
      <p><a href="{{$activate_url}}">{{$activate_url}}</a></p><br>
      <p>{{.locale.Tr "mail.link_not_working_do_paste"}}</p>
    </body>
    </html>
  '';
  forgejoMailResetPasswdTmpl = pkgs.writeText "reset_passwd.tmpl" ''
    <!DOCTYPE html>
    <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <meta name="format-detection" content="telephone=no,date=no,address=no,email=no,url=no">
    </head>

    {{$recover_url := printf "%suser/recover_account?code=%s" AppUrl (QueryEscape .Code)}}
    <body>
      <p>{{.locale.Tr "mail.hi_user_x" (.DisplayName|DotEscape)}}</p><br>
      <p>{{.locale.Tr "mail.reset_password.text" .ResetPwdCodeLives}}</p>
      <p><a href="{{$recover_url}}">{{$recover_url}}</a></p><br>
      <p>{{.locale.Tr "mail.link_not_working_do_paste"}}</p>
    </body>
    </html>
  '';
  forgejoMailRegisterNotifyTmpl = pkgs.writeText "register_notify.tmpl" ''
    <!DOCTYPE html>
    <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <meta name="format-detection" content="telephone=no,date=no,address=no,email=no,url=no">
    </head>

    {{$set_pwd_url := printf "%suser/forgot_password" AppUrl}}
    <body>
      <p>{{.locale.Tr "mail.hi_user_x" (.DisplayName|DotEscape)}}</p><br>
      <p>{{.locale.Tr "mail.register_notify.text_1" AppName}}</p><br>
      <p>{{.locale.Tr "mail.register_notify.text_2" .Username}}</p>
      <p><a href="{{AppUrl}}user/login">{{AppUrl}}user/login</a></p><br>
      <p>{{.locale.Tr "mail.register_notify.text_3" $set_pwd_url}}</p>
    </body>
    </html>
  '';
  forgejoOauthContainerTmpl = pkgs.writeText "oauth_container.tmpl" ''
    {{if or .OAuth2Providers .EnableOpenIDSignIn}}
    {{if or (and .PageIsSignUp (not .DisableRegistration)) (and .PageIsSignIn .EnableInternalSignIn)}}
      <div class="divider divider-text">
        {{ctx.Locale.Tr "sign_in_or"}}
      </div>
    {{end}}
    {{$oauthLabels := dict "github" "GitHub" "gitlab" "GitLab" "google" "Google"}}
    <div id="oauth2-login-navigator" class="tw-py-1">
      <div class="tw-flex tw-flex-col tw-justify-center">
        <div id="oauth2-login-navigator-inner" class="tw-flex tw-flex-col tw-flex-wrap tw-items-center tw-gap-2">
          {{range $provider := .OAuth2Providers}}
            {{$label := or (index $oauthLabels $provider.DisplayName) $provider.DisplayName}}
            <a class="{{$provider.Name}} ui button tw-flex tw-items-center tw-justify-center tw-py-2 tw-w-full oauth-login-link" href="{{AppSubUrl}}/user/oauth2/{{$provider.DisplayName}}">
              {{$provider.IconHTML 28}}
              {{ctx.Locale.Tr "sign_in_with_provider" $label}}
            </a>
          {{end}}
          {{if .EnableOpenIDSignIn}}
            <a class="openid ui button tw-flex tw-items-center tw-justify-center tw-py-2 tw-w-full" href="{{AppSubUrl}}/user/login/openid">
            {{svg "fontawesome-openid" 28 "tw-mr-2"}}
            {{ctx.Locale.Tr "auth.sign_in_openid"}}
            </a>
          {{end}}
        </div>
      </div>
    </div>
    {{end}}
  '';
in
{
  imports = [
    ./finance.nix
    ./delta.nix
    ./disk-config.nix
    ./hardware-configuration.nix
    pierreForgejo.nixosModule
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    devices = lib.mkForce [ "nodev" ];
    configurationLimit = 2;
  };

  documentation.enable = false;
  hardware.enableRedistributableFirmware = false;
  fonts.fontconfig.enable = false;

  networking = {
    hostName = "vps";
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "152.53.168.144";
          prefixLength = 22;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a0a:4cc0:2000:af7d:c8e4:dff:fe7f:c233";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "152.53.168.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];
  };

  services.openssh = {
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${identity.email}"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6OeNUf0FNpeNSq/XKyJTl4XDlmaV/UcV2SpPzgn4ag forgejo-actions-delta-deploy-2026-05-10"
  ];

  users.groups.${webDeployGroup} = { };

  users.users.${webDeployUser} = {
    isSystemUser = true;
    group = webDeployGroup;
    home = "/var/lib/${webDeployUser}";
    createHome = true;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [ webDeployPublicKey ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = identity.email;
  };

  services.nginx = {
    enable = true;
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=static_site_per_ip:10m rate=20r/s;
      limit_conn_zone $binary_remote_addr zone=static_site_conn_per_ip:10m;
      map $arg_v $forgejo_asset_cache_control {
        default "public, max-age=21600";
        "~.+" "public, max-age=31536000, immutable";
      }
    '';
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";
    virtualHosts."www.${identity.domain}" = mkBarrettruthHost staticWebRoots."barrettruth.com";
    virtualHosts.${identity.domain} = mkRedirectHost "www.${identity.domain}";
    virtualHosts."www.barrettruth.sh" = mkBarrettruthHost staticWebRoots."barrettruth.com";
    virtualHosts."barrettruth.sh" = mkRedirectHost "www.barrettruth.sh";
    virtualHosts."www.philipmruth.com" = mkStaticSiteHost staticWebRoots."philipmruth.com";
    virtualHosts."philipmruth.com" = mkRedirectHost "www.philipmruth.com";
    virtualHosts."www.vimdoc-language-server.com" =
      mkStaticSiteHost
        staticWebRoots."vimdoc-language-server.com";
    virtualHosts."vimdoc-language-server.com" = mkRedirectHost "www.vimdoc-language-server.com";
    virtualHosts."vimdoc-language-server.${identity.domain}" =
      mkRedirectHost "www.vimdoc-language-server.com";
    virtualHosts."vault.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8222";
    };
    virtualHosts."forge.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/".proxyPass = "http://127.0.0.1:3000";
        "= /assets/css/barrett-forgejo.css" = forgejoMutableAssetProxy;
        "= /assets/css/pierre-forgejo.css" = forgejoMutableAssetProxy;
        "= /assets/github-repo-stats.json" = forgejoStatsAssetProxy;
        "= /assets/js/barrett-forgejo.js" = forgejoMutableAssetProxy;
        "= /assets/js/pierre-forgejo.js" = forgejoMutableAssetProxy;
        "= /manifest.json" = forgejoMutableAssetProxy;
        "~* ^/assets/fonts/.*\\.(?:ttf|otf|woff|woff2)$" = forgejoImmutableAssetProxy;
        "~* ^/assets/.*\\.(?:css|js|mjs|png|jpg|jpeg|gif|webp|svg|ico)$" = forgejoMutableAssetProxy;
        "~* ^/avatars/[0-9a-f]+$" = forgejoImmutableAssetProxy;
      };
    };
    virtualHosts."git.${identity.domain}" = mkRedirectHost "forge.${identity.domain}";
  };

  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemKeepFree=2G
    RuntimeMaxUse=256M
    MaxRetentionSec=14day
  '';

  services.logrotate = {
    enable = true;
    settings.nginx = {
      frequency = "daily";
      rotate = 14;
      maxsize = "100M";
    };
  };

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
    config = {
      DOMAIN = "https://vault.${identity.domain}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
    };
  };

  sops.secrets =
    let
      mkForgejoSecret =
        restartUnits: name:
        mkVpsSecret name {
          owner = "git";
          group = "git";
          mode = "0400";
          inherit restartUnits;
        };
    in
    lib.genAttrs [
      "forgejo-resend-api-key"
      "forgejo-hcaptcha-sitekey"
      "forgejo-hcaptcha-secret"
    ] (mkForgejoSecret [ "forgejo.service" ])
    // lib.genAttrs forgejoOauthSecretNames (mkForgejoSecret [ "forgejo-oauth-sync.service" ])
    //
      lib.genAttrs
        [
          "forgejo-gpg-passphrase"
          "forgejo-gpg-secret.asc"
        ]
        (mkForgejoSecret [
          "forgejo.service"
          "forgejo-gpg-import.service"
        ]);

  services.forgejo = {
    enable = true;
    package = pierreForgejo.mkForgejoWithPierre (
      pkgs.callPackage ../../pkgs/forgejo-cm6-langs {
        frontendPatches = builtins.filter (
          p: lib.hasSuffix "expose-init-globals.patch" (toString p)
        ) pierreForgejo.patches;
      }
    );
    user = "git";
    group = "git";
    dump = {
      enable = true;
      backupDir = "/var/backup/forgejo";
      age = "3d";
    };
    secrets = {
      mailer.PASSWD = config.sops.secrets."forgejo-resend-api-key".path;
      service.HCAPTCHA_SITEKEY = config.sops.secrets."forgejo-hcaptcha-sitekey".path;
      service.HCAPTCHA_SECRET = config.sops.secrets."forgejo-hcaptcha-secret".path;
    };
    settings = {
      DEFAULT = {
        APP_NAME = identity.fullName;
      };
      server = {
        DOMAIN = "forge.${identity.domain}";
        ROOT_URL = "https://forge.${identity.domain}/";
        HTTP_PORT = 3000;
        SSH_DOMAIN = "forge.${identity.domain}";
        LANDING_PAGE = "/barrettruth";
      };
      service = {
        DISABLE_REGISTRATION = false;
        REGISTER_EMAIL_CONFIRM = true;
        ENABLE_NOTIFY_MAIL = true;
        ENABLE_CAPTCHA = true;
        REQUIRE_CAPTCHA_FOR_LOGIN = false;
        CAPTCHA_TYPE = "hcaptcha";
      };
      repository = {
        DEFAULT_PRIVATE = "private";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        UPDATE_AVATAR = true;
        USERNAME = "nickname";
      };
      security.GLOBAL_TWO_FACTOR_REQUIREMENT = "all";
      session.COOKIE_SECURE = true;
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.resend.com";
        SMTP_PORT = 2465;
        USER = "resend";
        FROM = "noreply@${identity.domain}";
      };
      mirror = {
        DEFAULT_INTERVAL = "15m";
        MIN_INTERVAL = "5m";
      };
      "git.config" = {
        "gpg.program" = "${forgejoGpgProgram}";
      };
      "repository.signing" = {
        SIGNING_KEY = forgejoSigningKeyId;
        INITIAL_COMMIT = "always";
        CRUD_ACTIONS = "always";
        MERGES = "always";
        WIKI = "never";
      };
      "markup.sanitizer.video-muted" = {
        ELEMENT = "video";
        ALLOW_ATTR = "muted";
      };
      "markup.sanitizer.video-loop" = {
        ELEMENT = "video";
        ALLOW_ATTR = "loop";
      };
      "markup.sanitizer.video-playsinline" = {
        ELEMENT = "video";
        ALLOW_ATTR = "playsinline";
      };
      ui = {
        DEFAULT_THEME = "midnight-auto";
        THEMES = "midnight-auto,midnight-light,midnight-dark";
      };
      "ui.meta" = {
        AUTHOR = identity.fullName;
        DESCRIPTION = "Personal code, experiments, and project history.";
        KEYWORDS = "git,code,barrett,ruth";
      };
      other = {
        SHOW_FOOTER_VERSION = false;
        SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
        SHOW_FOOTER_LICENSES_API = false;
        SHOW_FOOTER_POWERED_BY = false;
      };
    };
  };

  services.pierre-ssr.enable = true;

  systemd.services.forgejo = {
    after = [ "pierre-ssr.service" ];
    wants = [ "pierre-ssr.service" ];
    environment = {
      GNUPGHOME = "/var/lib/forgejo/.gnupg";
      PIERRE_SSR_SOCKET = config.services.pierre-ssr.socketPath;
    };
    restartTriggers = [
      forgejoCustom.frontend
      forgejoCustom.assets
      forgejoCustom.templates
      pierreForgejo.frontend
      pierreForgejo.assets
      pierreForgejo.templates
    ];
    serviceConfig.LoadCredential = lib.mkAfter [
      "gpg-passphrase:${config.sops.secrets."forgejo-gpg-passphrase".path}"
    ];
  };

  systemd.services.forgejo-gpg-import = {
    description = "Import Forgejo GPG signing key into git keyring (idempotent)";
    before = [ "forgejo.service" ];
    wantedBy = [ "forgejo.service" ];
    path = [ pkgs.gnupg ];
    serviceConfig = {
      Type = "oneshot";
      User = "git";
      Group = "git";
      LoadCredential = [
        "passphrase:${config.sops.secrets."forgejo-gpg-passphrase".path}"
        "secret:${config.sops.secrets."forgejo-gpg-secret.asc".path}"
      ];
      Environment = [ "GNUPGHOME=/var/lib/forgejo/.gnupg" ];
    };
    script = ''
      set -eu
      if gpg --list-secret-keys ${forgejoSigningKeyId} >/dev/null 2>&1; then
        exit 0
      fi
      gpg --batch --pinentry-mode loopback \
        --passphrase-file "$CREDENTIALS_DIRECTORY/passphrase" \
        --import "$CREDENTIALS_DIRECTORY/secret"
      printf '%s:6:\n' ${forgejoSigningTrustFingerprint} | gpg --import-ownertrust
    '';
  };

  systemd.services.forgejo-oauth-sync = {
    description = "Sync Forgejo OAuth2 authentication sources from on-disk credentials";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    wantedBy = [ "forgejo.service" ];
    path = [ pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "git";
      Group = "git";
      WorkingDirectory = "/var/lib/forgejo";
      LoadCredential = lib.flatten (
        lib.mapAttrsToList (name: _: [
          "${name}-id:${config.sops.secrets."forgejo-oauth-${name}-id".path}"
          "${name}-secret:${config.sops.secrets."forgejo-oauth-${name}-secret".path}"
        ]) forgejoOauthSources
      );
    };
    script =
      let
        forgejo = "${config.services.forgejo.package}/bin/forgejo --config /var/lib/forgejo/custom/conf/app.ini --work-path /var/lib/forgejo";
        syncOne = name: cfg: ''
          id=$(${forgejo} admin auth list | awk -F'\t' -v d="${cfg.displayName}" -v n="${name}" 'NR>1 && ($2==d || $2==n) {print $1; exit}')
          key=$(cat "$CREDENTIALS_DIRECTORY/${name}-id")
          secret=$(cat "$CREDENTIALS_DIRECTORY/${name}-secret")
          if [ -z "$id" ]; then
            ${forgejo} admin auth add-oauth \
              --name "${name}" \
              --provider "${cfg.provider}" \
              --key "$key" \
              --secret "$secret"
          else
            ${forgejo} admin auth update-oauth \
              --id "$id" \
              --name "${name}" \
              --key "$key" \
              --secret "$secret"
          fi
        '';
      in
      ''
        set -eu
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList syncOne forgejoOauthSources)}
      '';
  };

  systemd.services.forgejo-github-stats-cache = {
    description = "Cache public GitHub repository stats for Forgejo chrome";
    after = [
      "network-online.target"
      "forgejo.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "git";
      Group = "git";
      WorkingDirectory = "/var/lib/forgejo";
    };
    path = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    script = ''
      set -euo pipefail

      owner="barrettruth"
      stats_dir="/var/lib/forgejo/custom/public/assets"
      output="$stats_dir/github-repo-stats.json"
      pages_dir="$(mktemp -d)"
      tmp="$(mktemp "$stats_dir/github-repo-stats.json.tmp.XXXXXX")"
      trap 'rm -rf "$pages_dir" "$tmp"' EXIT

      page=1
      while [ "$page" -le 10 ]; do
        body="$pages_dir/page-$page.json"
        curl -fsSL \
          --connect-timeout 10 \
          --max-time 60 \
          --retry 3 \
          --retry-delay 5 \
          --header "Accept: application/vnd.github+json" \
          --header "User-Agent: barrett-forgejo-github-stats" \
          --header "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/users/$owner/repos?type=owner&sort=full_name&per_page=100&page=$page" \
          --output "$body"

        jq -e 'type == "array"' "$body" >/dev/null
        count="$(jq 'length' "$body")"
        if [ "$count" -eq 0 ]; then
          break
        fi
        page=$((page + 1))
      done

      generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      jq -s \
        --arg owner "$owner" \
        --arg generated_at "$generated_at" \
        '
          [ .[][] ] as $repos
          | {
              schema: 1,
              owner: $owner,
              generated_at: $generated_at,
              source: ("https://api.github.com/users/" + $owner + "/repos"),
              repos: (
                $repos
                | map({
                    key: (.name | ascii_downcase),
                    value: {
                      name,
                      full_name,
                      html_url,
                      description,
                      archived,
                      fork,
                      private,
                      stars: .stargazers_count,
                      forks: .forks_count,
                      open_issues: .open_issues_count,
                      watchers: .watchers_count,
                      default_branch,
                      language,
                      pushed_at,
                      updated_at
                    }
                  })
                | sort_by(.key)
                | from_entries
              )
            }
        ' "$pages_dir"/page-*.json > "$tmp"

      chmod 0644 "$tmp"
      mv "$tmp" "$output"
    '';
  };

  systemd.timers.forgejo-github-stats-cache = {
    description = "Refresh public GitHub repository stats for Forgejo chrome";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "6h";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };

  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };

  users.groups.git = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo/.gnupg 0700 git git -"
    "L+ /var/lib/forgejo/.gnupg/gpg-agent.conf - - - - ${forgejoGpgAgentConf}"
    "d /var/lib/forgejo/custom/public 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/img 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.svg - - - - ${forgejoBrandingAssets}/logo.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.png - - - - ${forgejoBrandingAssets}/logo.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.svg - - - - ${forgejoBrandingAssets}/favicon.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.png - - - - ${forgejoBrandingAssets}/favicon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/apple-touch-icon.png - - - - ${forgejoBrandingAssets}/apple-touch-icon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/avatar_default.png - - - - ${forgejoBrandingAssets}/avatar_default.png"
    "d /var/lib/forgejo/custom/public/assets/css 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-auto.css - - - - ${forgejoCustom.assets}/css/theme-midnight-auto.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-light.css - - - - ${forgejoCustom.assets}/css/theme-midnight-light.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-dark.css - - - - ${forgejoCustom.assets}/css/theme-midnight-dark.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-fonts.css - - - - ${forgejoCustom.assets}/css/theme-midnight-fonts.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-syntax.css - - - - ${forgejoCustom.assets}/css/theme-midnight-syntax.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/barrett-forgejo.css - - - - ${forgejoCustom.assets}/css/barrett-forgejo.css"
    "L+ /var/lib/forgejo/custom/public/assets/css/pierre-forgejo.css - - - - ${pierreForgejo.assets}/css/pierre-forgejo.css"
    "d /var/lib/forgejo/custom/public/assets/js 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/js/midnight-cm6.js - - - - ${forgejoCustom.assets}/js/midnight-cm6.js"
    "L+ /var/lib/forgejo/custom/public/assets/js/barrett-forgejo.js - - - - ${forgejoCustom.frontend}/js/barrett-forgejo.js"
    "L+ /var/lib/forgejo/custom/public/assets/js/pierre-forgejo.js - - - - ${pierreForgejo.frontend}/js/pierre-forgejo.js"
    "L+ /var/lib/forgejo/custom/public/assets/js/chunks - - - - ${pierreForgejo.frontend}/js/chunks"
    "d /var/lib/forgejo/custom/templates 0750 git git -"
    "d /var/lib/forgejo/custom/templates/custom 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/custom/header.tmpl - - - - ${forgejoCustom.templates}/custom/header.tmpl"
    "L+ /var/lib/forgejo/custom/templates/custom/footer.tmpl - - - - ${forgejoFooterTmpl}"
    "d /var/lib/forgejo/custom/templates/base 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/base/footer_content.tmpl - - - - ${forgejoFooterContentTmpl}"
    "d /var/lib/forgejo/custom/templates/mail 0750 git git -"
    "d /var/lib/forgejo/custom/templates/mail/auth 0750 git git -"
    "d /var/lib/forgejo/custom/templates/mail/common 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/mail/auth/activate.tmpl - - - - ${forgejoMailActivateTmpl}"
    "L+ /var/lib/forgejo/custom/templates/mail/auth/activate_email.tmpl - - - - ${forgejoMailActivateEmailTmpl}"
    "L+ /var/lib/forgejo/custom/templates/mail/auth/register_notify.tmpl - - - - ${forgejoMailRegisterNotifyTmpl}"
    "L+ /var/lib/forgejo/custom/templates/mail/auth/reset_passwd.tmpl - - - - ${forgejoMailResetPasswdTmpl}"
    "L+ /var/lib/forgejo/custom/templates/mail/common/footer_simple.tmpl - - - - ${forgejoMailFooterSimpleTmpl}"
    "d /var/lib/forgejo/custom/templates/repo 0750 git git -"
    "d /var/lib/forgejo/custom/templates/repo/diff 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/repo/diff/box.tmpl - - - - ${pierreForgejo.templates}/repo/diff/box.tmpl"
    "d /var/lib/forgejo/custom/templates/user 0750 git git -"
    "d /var/lib/forgejo/custom/templates/user/auth 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/user/auth/oauth_container.tmpl - - - - ${forgejoOauthContainerTmpl}"
    "d /var/lib/forgejo/custom/public/assets/fonts 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/nonicons.woff - - - - ${forgejoCustom.assets}/fonts/nonicons.woff"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/nonicons-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/nonicons-v1.woff2"
    "d /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro.ttf - - - - ${forgejoCustom.assets}/fonts/san-francisco-pro/SF-Pro.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro-Italic.ttf - - - - ${forgejoCustom.assets}/fonts/san-francisco-pro/SF-Pro-Italic.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro-latin-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/san-francisco-pro/SF-Pro-latin-v1.woff2"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro-Italic-latin-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/san-francisco-pro/SF-Pro-Italic-latin-v1.woff2"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/san-francisco-pro/SF-Pro-v1.woff2"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro-Italic-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/san-francisco-pro/SF-Pro-Italic-v1.woff2"
    "d /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Regular.ttf - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-Regular.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Italic.ttf - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-Italic.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Bold.ttf - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-Bold.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-BoldItalic.ttf - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-BoldItalic.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Regular-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-Regular-v1.woff2"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Italic-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-Italic-v1.woff2"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Bold-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-Bold-v1.woff2"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-BoldItalic-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/berkeley-mono/BerkeleyMono-BoldItalic-v1.woff2"
    "d /var/lib/forgejo/custom/public/assets/fonts/stix-two 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/stix-two/STIXTwoText.ttf - - - - ${forgejoStixTwoFontFile}"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/stix-two/STIXTwoText-v1.woff2 - - - - ${forgejoCustom.assets}/fonts/stix-two/STIXTwoText-v1.woff2"
    "d /srv/www 0755 root root -"
    "d /srv/www/barrettruth.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/barrettruth.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/philipmruth.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/philipmruth.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/vimdoc-language-server.com 0755 ${webDeployUser} ${webDeployGroup} -"
    "d /srv/www/vimdoc-language-server.com/releases 0755 ${webDeployUser} ${webDeployGroup} -"
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    nodejs_22
    pnpm
    rsync
  ];

  systemd.services.vaultwarden-r2-backup = {
    description = "Backup Vaultwarden to Cloudflare R2";
    after = [ "backup-vaultwarden.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/vaultwarden-r2-backup.env";
    };
    path = [
      pkgs.awscli2
      pkgs.gawk
    ];
    script = ''
      export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
      export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
      ENDPOINT="$R2_ENDPOINT"
      DATE=$(date +%Y-%m-%d)

      aws s3 cp /var/backup/vaultwarden/db.sqlite3 \
        "s3://vaultwarden/$DATE/db.sqlite3" \
        --endpoint-url "$ENDPOINT"

      CUTOFF=$(date -d '30 days ago' +%Y-%m-%d)
      aws s3 ls s3://vaultwarden/ --endpoint-url "$ENDPOINT" \
        | awk '{print $2}' | tr -d '/' \
        | while read dir; do
            if [ "$dir" \< "$CUTOFF" ]; then
              aws s3 rm "s3://vaultwarden/$dir" --recursive --endpoint-url "$ENDPOINT"
            fi
          done
    '';
  };

  systemd.timers.vaultwarden-r2-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.services.forgejo-dump.preStart = ''
    find /var/backup/forgejo -maxdepth 1 -type f -name 'forgejo-dump-*' -mtime +3 -delete

    free_bytes=$(df --output=avail -B1 /var/backup/forgejo | tail -n 1 | tr -d ' ')
    min_free_bytes=$((20 * 1024 * 1024 * 1024))
    if [ "$free_bytes" -lt "$min_free_bytes" ]; then
      echo "Refusing Forgejo dump: less than 20G free in /var/backup/forgejo"
      exit 1
    fi
  '';

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "";
  };

  # Keep only the current VPS system generation and one rollback generation.
  system.activationScripts.pruneVpsSystemGenerations.text = ''
    if [ -e /nix/var/nix/profiles/system ]; then
      ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +2
      ${config.nix.package}/bin/nix-store --gc
    fi
  '';

  systemd.services.forgejo-heatmap-reconcile = {
    description = "Replay barrettruth commit history into Forgejo's action table to backfill heatmap";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "git";
      Group = "git";
    };
    path = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnused
      pkgs.sqlite
    ];
    script = ''
      set -euo pipefail

      DB="/var/lib/forgejo/data/forgejo.db"
      REPOS_ROOT="/var/lib/forgejo/repositories"
      OWNER_NAME="barrettruth"
      OP_COMMIT=5
      OP_CREATE_ISSUE=6
      OP_CREATE_PR=7
      OP_COMMENT_ISSUE=10
      OP_COMMENT_PR=23
      OP_PUBLISH_RELEASE=24

      sql() {
        sqlite3 -bail -batch "$DB" ".timeout 5000" "$1"
      }

      user_id=$(sql "SELECT id FROM \"user\" WHERE lower_name = '$OWNER_NAME';")
      if [ -z "$user_id" ]; then
        echo "no forgejo user named $OWNER_NAME found" >&2
        exit 1
      fi
      echo "Reconciling heatmap for $OWNER_NAME (id=$user_id)"

      emails_file=$(mktemp)
      trap 'rm -f "$emails_file"' EXIT
      sql "SELECT email FROM email_address WHERE uid = $user_id;" > "$emails_file"
      sql "SELECT email FROM \"user\" WHERE id = $user_id;" >> "$emails_file"
      sort -u -o "$emails_file" "$emails_file"

      inserted=0

      while IFS='|' read -r repo_id repo_name default_branch; do
        [ -z "$repo_id" ] && continue
        bare="$REPOS_ROOT/$OWNER_NAME/$repo_name.git"
        [ -d "$bare" ] || continue

        default_ref="refs/heads/$default_branch"
        if ! git -C "$bare" rev-parse --verify --quiet "$default_ref" >/dev/null; then
          continue
        fi

        repo_added=0
        while IFS='|' read -r sha ct ae; do
          [ -z "$sha" ] && continue
          if ! grep -Fxq "$ae" "$emails_file"; then
            continue
          fi
          exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $OP_COMMIT AND created_unix = $ct;")
          if [ "$exists" -gt 0 ]; then
            continue
          fi
          content=$(printf '%s\n%s' "$default_branch" "$sha")
          sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $OP_COMMIT, $user_id, $repo_id, '$default_ref', 0, '$content', $ct);"
          repo_added=$((repo_added + 1))
          inserted=$((inserted + 1))
        done < <(git -C "$bare" log --branches --format='%H|%ct|%ae')

        if [ "$repo_added" -gt 0 ]; then
          echo "  $OWNER_NAME/$repo_name: +$repo_added"
        fi
      done < <(sql "SELECT id, name, default_branch FROM repository WHERE owner_id = $user_id AND is_private = 0;")

      echo "Backfilling issues / PRs / comments / releases authored by $OWNER_NAME ..."

      issue_match="(poster_id = $user_id OR (poster_id = -1 AND original_author = '$OWNER_NAME'))"
      comment_match="(c.poster_id = $user_id OR (c.poster_id = -1 AND c.original_author = '$OWNER_NAME'))"

      added_issues=0
      while IFS='|' read -r issue_id repo_id is_pull ct; do
        [ -z "$issue_id" ] && continue
        op_type=$([ "$is_pull" = "1" ] && echo "$OP_CREATE_PR" || echo "$OP_CREATE_ISSUE")
        exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $op_type AND created_unix = $ct;")
        if [ "$exists" -gt 0 ]; then
          continue
        fi
        sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $op_type, $user_id, $repo_id, ''', 0, ''', $ct);"
        added_issues=$((added_issues + 1))
        inserted=$((inserted + 1))
      done < <(sql "SELECT id, repo_id, is_pull, created_unix FROM issue WHERE $issue_match;")
      [ "$added_issues" -gt 0 ] && echo "  +$added_issues issue/PR creates"

      added_comments=0
      while IFS='|' read -r comment_id repo_id is_pull ct; do
        [ -z "$comment_id" ] && continue
        op_type=$([ "$is_pull" = "1" ] && echo "$OP_COMMENT_PR" || echo "$OP_COMMENT_ISSUE")
        exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $op_type AND created_unix = $ct;")
        if [ "$exists" -gt 0 ]; then
          continue
        fi
        sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $op_type, $user_id, $repo_id, ''', 0, ''', $ct);"
        added_comments=$((added_comments + 1))
        inserted=$((inserted + 1))
      done < <(sql "SELECT c.id, i.repo_id, i.is_pull, c.created_unix FROM comment c JOIN issue i ON c.issue_id = i.id WHERE $comment_match AND c.type = 0;")
      [ "$added_comments" -gt 0 ] && echo "  +$added_comments issue/PR comments"

      added_releases=0
      while IFS='|' read -r release_id repo_id ct; do
        [ -z "$release_id" ] && continue
        exists=$(sql "SELECT COUNT(*) FROM action WHERE user_id = $user_id AND repo_id = $repo_id AND op_type = $OP_PUBLISH_RELEASE AND created_unix = $ct;")
        if [ "$exists" -gt 0 ]; then
          continue
        fi
        sql "INSERT INTO action (user_id, op_type, act_user_id, repo_id, ref_name, is_private, content, created_unix) VALUES ($user_id, $OP_PUBLISH_RELEASE, $user_id, $repo_id, ''', 0, ''', $ct);"
        added_releases=$((added_releases + 1))
        inserted=$((inserted + 1))
      done < <(sql "SELECT id, repo_id, created_unix FROM release WHERE publisher_id = $user_id;")
      [ "$added_releases" -gt 0 ] && echo "  +$added_releases releases"

      echo "Reconciliation complete: $inserted new action records."
    '';
  };

  systemd.timers.forgejo-heatmap-reconcile = {
    description = "Daily replay of barrettruth commit history into Forgejo's action table";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };

  nix.extraOptions = ''
    min-free = ${toString (100 * 1024 * 1024)}
    max-free = ${toString (1024 * 1024 * 1024)}
  '';

  system.stateVersion = "24.11";
}
