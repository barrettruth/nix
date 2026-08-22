{
  config,
  identity,
  pkgs,
  act,
  ...
}:
let
  homeDirectory = config.barrett.user.homeDirectory;

  authorizedKeys = pkgs.writeText "authorized_keys" (
    builtins.concatStringsSep "\n" identity.sshKeys + "\n"
  );
in
{
  system.activationScripts.extraActivation.text = ''
    ${act.installDirMode "0700" "${homeDirectory}/.ssh"}
    ${pkgs.coreutils}/bin/install -m 0600 -o ${config.barrett.user.name} -g ${act.group} \
      ${authorizedKeys} "${homeDirectory}/.ssh/authorized_keys"
  '';

  programs.ssh.extraConfig = ''
    Host forge.barrettruth.com git.barrettruth.com
        HostName 100.64.0.1
        Port 2222
        HostKeyAlias forge.barrettruth.com
        IdentityFile ${homeDirectory}/.ssh/id_ed25519
        IdentitiesOnly yes
  '';

  programs.ssh.knownHosts.desktop = {
    hostNames = [
      "desktop"
      "desktop.${identity.tailnetDomain}"
      "100.64.0.1"
    ];
    publicKey = identity.hostKeys.desktop;
  };

  programs.ssh.knownHosts.laptop = {
    hostNames = [
      "laptop"
      "laptop.${identity.tailnetDomain}"
      "100.64.0.2"
    ];
    publicKey = identity.hostKeys.laptop;
  };

  programs.ssh.knownHosts.mac = {
    hostNames = [
      "mac"
      "mac.${identity.tailnetDomain}"
      "100.64.0.4"
    ];
    publicKey = identity.hostKeys.mac;
  };

  programs.ssh.knownHosts."forge-tailnet" = {
    hostNames = [
      "[forge.barrettruth.com]:2222"
      "[git.barrettruth.com]:2222"
    ];
    publicKey = identity.hostKeys.forge-tailnet;
  };
}
