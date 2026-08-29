{
  description = "Barrett Ruth's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devin = {
      url = "github:charliemeyer2000/devin-cli-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    font-berkeley-mono = {
      url = "git+ssh://git@github.com/barrettruth/font-berkeley-mono.git";
      flake = false;
    };
    pierrejo = {
      url = "git+https://git.harivan.sh/harivansh-afk/pierrejo.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.nix-darwin.flakeModules.default
        ./modules/nixpkgs.nix
        ./modules/identity.nix
        ./modules/theme.nix
        ./modules/devshells.nix
        ./modules/hosts/laptop.nix
        ./modules/hosts/vps.nix
        ./modules/hosts/desktop.nix
        ./modules/hosts/mac.nix
        ./modules/hosts/imc.nix
      ];
    };
}
