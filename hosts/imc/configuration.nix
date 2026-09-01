{
  config,
  lib,
  pkgs,
  act,
  mkHostSecret,
  palettes,
  themeGenerators,
  ...
}:
let
  homeDirectory = config.barrett.user.homeDirectory;

  javaVersion = "17";

  devenvHost = "${config.barrett.user.name}-devschool.trading.imc.intra";

  spotlightExcluded = [
    "${homeDirectory}/.m2"
    "${homeDirectory}/Library/Caches"
    "${homeDirectory}/dev"
  ];

  repo = "${homeDirectory}/.config/nix";

  codexHome = "${homeDirectory}/.config/codex";

  repoEnv = "${pkgs.python3}/bin/python3 ${repo}/config/agents/hooks/repo-env.py";

  imcCaBundle = "/etc/ssl/certs/ca-certificates-imc.crt";

  codexThemes = pkgs.linkFarm "codex-themes" [
    {
      name = "daylight.tmTheme";
      path = pkgs.writeText "daylight.tmTheme" (
        themeGenerators.mkCodexPaletteTheme "Daylight" palettes.daylight
      );
    }
    {
      name = "midnight.tmTheme";
      path = pkgs.writeText "midnight.tmTheme" (themeGenerators.mkCodexAnsiTheme "Midnight");
    }
  ];

  codexConfig = (pkgs.formats.toml { }).generate "codex-config.toml" {
    model = "gpt-5.6-sol";
    model_reasoning_effort = "xhigh";

    approval_policy = "never";
    sandbox_mode = "danger-full-access";

    file_opener = "none";
    check_for_update_on_startup = false;

    sqlite_home = "${homeDirectory}/.local/state/codex";

    projects = {
      "${homeDirectory}".trust_level = "trusted";
      "${repo}".trust_level = "trusted";
    };

    mcp_servers = {
      gcalendar = {
        command = "npx";
        args = [
          "-y"
          "@cocal/google-calendar-mcp@2.6.2"
          "start"
        ];
        env.GOOGLE_OAUTH_CREDENTIALS = "${homeDirectory}/.config/mcp-google/gcp-oauth.keys.json";
        env_vars = [ "NPM_CONFIG_CACHE" ];
        startup_timeout_sec = 30;
        required = true;
      };

      gmail = {
        command = "npx";
        args = [
          "-y"
          "@gongrzhe/server-gmail-autoauth-mcp@1.1.11"
        ];
        env_vars = [ "NPM_CONFIG_CACHE" ];
        startup_timeout_sec = 30;
        required = true;
      };

      gdrive = {
        command = lib.getExe pkgs.mcp-gdrive;
        startup_timeout_sec = 30;
        required = true;
      };
    };

    tui = {
      theme = "midnight";
      vim_mode_default = true;
      status_line = [
        "model-with-reasoning"
        "run-state"
      ];
      status_line_use_colors = true;
    };

    hooks = {
      SessionStart = [
        {
          matcher = "startup|resume";
          hooks = [
            {
              type = "command";
              command = "${repoEnv} session";
              timeout = 5;
            }
          ];
        }
      ];
    };
  };

  brews = [ "imc/core/imc-claude" ];

  casks = [
    "imc/core/ark"
    "imc/core/jx"
    "jdk-zulu@11"
    "jdk-zulu@17"
    "jdk-zulu@21"
    "jdk-zulu@22"
  ];
in
{
  networking.hostName = "imc";

  barrett.user.name = "bruth";

  barrett.user.gitEmail = "barrett.ruth@imc.com";
  barrett.user.personalGitDirs = [
    "~/dev/"
    "~/.config/nix/"
  ];
  barrett.user.extraGitConfig = ''
    [http]
      emptyAuth = true
  '';
  barrett.user.extraSshConfig = ''
    Include ${homeDirectory}/.colima/ssh_config

    Host devschool ${devenvHost}
      HostName ${devenvHost}
      User ${config.barrett.user.name}
      IdentityFile ${config.sops.secrets."devenv-private-key".path}
      Port 22
      StrictHostKeyChecking no
      CheckHostIP no
      UserKnownHostsFile /dev/null
      Compression yes
  '';

  sops.secrets."devenv-private-key" = mkHostSecret config.networking.hostName "devenv-private-key" {
    owner = config.barrett.user.name;
    mode = "0400";
  };

  barrett.tailscale.shieldsUp = true;
  barrett.tailscale.useAuthKey = false;

  homebrew = {
    inherit brews casks;
    enable = true;
    onActivation.cleanup = "none";
    taps = [
      {
        name = "imc/core";
        clone_target = "https://gitlab.trading.imc.intra/all/homebrew-imc";
        trusted = true;
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    bazelisk
    codex
  ];

  nix.settings.ssl-cert-file = imcCaBundle;

  environment.variables = {
    CODEX_HOME = codexHome;
    CURL_CA_BUNDLE = imcCaBundle;
    SSL_CERT_FILE = imcCaBundle;
  };

  environment.systemPath = lib.mkOrder 1100 [ "${config.homebrew.prefix}/bin" ];

  environment.extraInit = lib.optionalString (lib.elem "jdk-zulu@${javaVersion}" casks) ''
    export JAVA_HOME="$(/usr/libexec/java_home -v ${javaVersion})"
  '';

  system.activationScripts.extraActivation.text =
    lib.concatMapStrings (dir: ''
      if [ -d "${dir}" ]; then
        ${pkgs.coreutils}/bin/install -m 0644 -o ${config.barrett.user.name} -g ${act.group} \
          /dev/null "${dir}/.metadata_never_index"
      fi
    '') spotlightExcluded
    + ''
      caBundleTmp=$(${pkgs.coreutils}/bin/mktemp "${imcCaBundle}.XXXXXX")
      trap '${pkgs.coreutils}/bin/rm -f "$caBundleTmp"' EXIT
      {
        ${pkgs.coreutils}/bin/cat ${config.environment.etc."ssl/certs/ca-certificates.crt".source}
        /usr/bin/security find-certificate -a -p -c CAIMC03 /Library/Keychains/System.keychain
      } >"$caBundleTmp"
      ${pkgs.coreutils}/bin/install -m 0644 -o root -g wheel "$caBundleTmp" "${imcCaBundle}"
      ${pkgs.coreutils}/bin/rm -f "$caBundleTmp"
      trap - EXIT

      ${act.installDirMode "0700" codexHome}
      ${act.installDirMode "0755" "${codexHome}/themes"}
      ${act.installDirMode "0755" "${homeDirectory}/.local/state/codex"}
      if [ -L "${codexHome}/config.toml" ]; then
        ${act.runAsUser} ${pkgs.coreutils}/bin/unlink "${codexHome}/config.toml"
      fi
      ${pkgs.coreutils}/bin/install -m 0600 -o ${config.barrett.user.name} -g ${act.group} \
        "${codexConfig}" "${codexHome}/config.toml"
      ${act.mkSymlink "${repo}/config/agents/AGENTS.md" "${codexHome}/AGENTS.md"}
      ${act.mkSymlink "${codexThemes}/midnight.tmTheme" "${codexHome}/themes/midnight.tmTheme"}
      ${act.mkSymlink "${codexThemes}/daylight.tmTheme" "${codexHome}/themes/daylight.tmTheme"}
      if [ -L "${codexHome}/themes/midnight-auto.tmTheme" ]; then
        ${act.runAsUser} ${pkgs.coreutils}/bin/unlink "${codexHome}/themes/midnight-auto.tmTheme"
      fi
    '';

  barrett.mac.chrome = {
    app = "/Applications/Google Chrome.app";
    package = null;
    flags = [ "--silent-debugger-extension-api" ];
    unpackedMidnight = true;
  };

  barrett.mac.dock.apps = lib.mkAfter [
    "/Applications/Microsoft Outlook.app"
    "/Applications/Mattermost.app"
  ];

  barrett.mac.apps = lib.mkAfter [
    {
      key = "m";
      space = 8;
      bundleId = "Mattermost.Desktop";
      path = "/Applications/Mattermost.app";
      autostart = true;
    }
    {
      key = "o";
      space = 9;
      bundleId = "com.microsoft.Outlook";
      path = "/Applications/Microsoft Outlook.app";
      autostart = true;
    }
    {
      key = "z";
      space = 5;
      bundleId = "us.zoom.xos";
      path = "/Applications/zoom.us.app";
    }
    {
      path = "/Applications/DevEnv.app";
      autostart = true;
    }
  ];

  barrett.mac.floatingApps = lib.mkAfter [ "us.zoom.xos" ];
}
