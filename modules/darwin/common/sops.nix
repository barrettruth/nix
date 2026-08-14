{ inputs, ... }:
let
  mkHostSecret =
    hostName: name: attrs:
    {
      sopsFile = ../../../secrets/${hostName}/${name};
      format = "binary";
    }
    // attrs;
in
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  _module.args = {
    inherit mkHostSecret;
    mkSharedSecret = mkHostSecret "shared";
  };

  sops.age = {
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    generateKey = false;
  };
}
