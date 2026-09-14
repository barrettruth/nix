{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.barrett.privacy;
  runtimeLibrary = builtins.readFile ../../../scripts/ivpn-runtime.bash;
  runtimeTool = name: source: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.coreutils ];
    text = runtimeLibrary + "\n" + (lib.replaceStrings
      [ "@ivpn@" "@bypass_file@" ]
      [
        (lib.escapeShellArg "/Applications/IVPN.app/Contents/MacOS/cli/ivpn")
        (lib.escapeShellArg cfg.bypassFile)
      ]
      (builtins.readFile source));
  };
  guard = runtimeTool "ivpn-guard" ../../../scripts/ivpn-guard.bash;
  bypassRoot = runtimeTool "ivpn-bypass-root" ../../../scripts/ivpn-bypass.bash;
  bypassDialog = pkgs.writeText "ivpn-bypass.applescript" ''
    display dialog "Allow ordinary network access outside IVPN for five minutes? Your real IP may be exposed. Protection is restored by the guard after the deadline." buttons {"Cancel", "Allow five minutes"} default button "Cancel" cancel button "Cancel" with title "IVPN temporary bypass"
    do shell script ${builtins.toJSON (lib.getExe bypassRoot)} with administrator privileges
    display notification "Temporary bypass active for five minutes. Firewall recovery may take one guard interval afterward." with title "IVPN"
  '';
  bypassUi = pkgs.writeShellScriptBin "ivpn-bypass" ''
    exec /usr/bin/osascript ${bypassDialog}
  '';
  installIvpn = pkgs.writeShellApplication {
    name = "install-ivpn";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ../../../scripts/install-ivpn.bash;
  };
  ivpnCli = pkgs.writeShellScriptBin "ivpn" ''
    exec /Applications/IVPN.app/Contents/MacOS/cli/ivpn "$@"
  '';
in
{
  imports = [ ../../common/privacy.nix ];

  config = lib.mkIf cfg.enable {
    networking.dns = [ "::1" ];
    environment.systemPackages = [ ivpnCli ] ++ lib.optional cfg.alwaysOn bypassUi;
    services.skhd.skhdConfig = lib.mkIf cfg.alwaysOn ''
      lalt + shift - i : ${lib.getExe bypassUi}
    '';
    barrett.mac.apps = [
      {
        key = "i";
        path = "/Applications/IVPN.app";
        autostart = true;
      }
    ];

    system.activationScripts.extraActivation.text = ''
      ${lib.getExe installIvpn} ${pkgs.ivpn-bin}/IVPN.dmg /Applications/IVPN.app || exit 1
      if [ ! -d ${lib.escapeShellArg cfg.stateDirectory} ]; then
        /usr/bin/install -d -m 0755 -o root -g wheel ${lib.escapeShellArg cfg.stateDirectory}
      fi
    '';

    launchd.daemons.ivpn-policy = {
      command = lib.getExe cfg.policy;
      serviceConfig = {
        RunAtLoad = true;
        WatchPaths = [
          cfg.stateDirectory
          "${cfg.stateDirectory}/port.txt"
          "${cfg.stateDirectory}/settings.json"
        ];
        ThrottleInterval = 10;
        StandardOutPath = "/var/log/ivpn-policy.log";
        StandardErrorPath = "/var/log/ivpn-policy.log";
      };
    };

    launchd.daemons.ivpn-guard = lib.mkIf cfg.alwaysOn {
      command = lib.getExe guard;
      serviceConfig = {
        RunAtLoad = true;
        StartInterval = 15;
        ThrottleInterval = 15;
        WatchPaths = [ "/Library/LaunchDaemons/net.ivpn.client.Helper.plist" ];
        StandardOutPath = "/var/log/ivpn-guard.log";
        StandardErrorPath = "/var/log/ivpn-guard.log";
      };
    };

    services.dnscrypt-proxy.settings.user_name = "_dnscrypt-proxy";
    launchd.daemons.dnscrypt-proxy.serviceConfig = {
      UserName = lib.mkForce "root";
      GroupName = lib.mkForce "wheel";
      EnvironmentVariables.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
  };
}
