{ inputs, identity, ... }:
{
  flake.nixosConfigurations.netcup = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.disko.nixosModules.disko
      ../../hosts/netcup/configuration.nix
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
    specialArgs = { inherit identity; };
  };
}
