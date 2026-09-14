{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.barrett.privacy;
  guard = pkgs.writeShellApplication {
    name = "ivpn-guard";
    runtimeInputs = [ pkgs.coreutils ];
    text = lib.replaceStrings
      [ "@ivpn@" ]
      [ (lib.escapeShellArg "/Applications/IVPN.app/Contents/MacOS/cli/ivpn") ]
      (builtins.readFile ../../../scripts/ivpn-guard.bash);
  };
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
    environment.systemPackages = [ ivpnCli ];
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
