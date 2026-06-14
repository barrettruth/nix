{ inputs, identity, ... }:
{
  flake.nixosConfigurations.desktop = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.determinate.nixosModules.default
      inputs.disko.nixosModules.disko
      ../../hosts/desktop/configuration.nix
      ../nixos/common/nix.nix
      ../nixos/common/nix-ld.nix
      ../nixos/common/ssh.nix
      ../nixos/common/sops.nix
      ../nixos/common/tailscale.nix
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
    specialArgs = { inherit identity inputs; };
  };
}
