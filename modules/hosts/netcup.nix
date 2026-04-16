{ inputs, identity, ... }:
{
  flake.nixosConfigurations.netcup = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.disko.nixosModules.disko
      ../../hosts/netcup/configuration.nix
      ../nixos/common/nix.nix
      ../nixos/common/ssh.nix
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
    specialArgs = { inherit identity; };
  };
}
