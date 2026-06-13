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
  imports = [ inputs.sops-nix.nixosModules.sops ];

  _module.args = {
    inherit mkHostSecret;
    mkVpsSecret = mkHostSecret "vps";
    mkLaptopSecret = mkHostSecret "laptop";
    mkDesktopSecret = mkHostSecret "desktop";
  };

  sops.age = {
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    generateKey = false;
  };
}
