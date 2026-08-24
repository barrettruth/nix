{
  config,
  lib,
  pkgs,
  act,
  mkHostSecret,
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

  brews = [ "imc/core/imc-claude" ];

  casks = [
    "imc/core/ark"
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

  environment.systemPath = lib.mkOrder 1100 [ "${config.homebrew.prefix}/bin" ];

  environment.extraInit = lib.optionalString (lib.elem "jdk-zulu@${javaVersion}" casks) ''
    export JAVA_HOME="$(/usr/libexec/java_home -v ${javaVersion})"
  '';

  system.activationScripts.extraActivation.text = lib.concatMapStrings (dir: ''
    if [ -d "${dir}" ]; then
      ${pkgs.coreutils}/bin/install -m 0644 -o ${config.barrett.user.name} -g ${act.group} \
        /dev/null "${dir}/.metadata_never_index"
    fi
  '') spotlightExcluded;

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
  ];

  barrett.mac.floatingApps = lib.mkAfter [ "us.zoom.xos" ];
}
