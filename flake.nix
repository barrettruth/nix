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
    nixpkgs-whisper.url = "github:nixos/nixpkgs/a499dfba7b52aac86504356512836550e9d49a5a";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    devin = {
      url = "github:charliemeyer2000/devin-cli-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fonts = {
      url = "git+ssh://git@github.com/barrettruth/fonts.git";
      inputs.nixpkgs.follows = "nixpkgs";
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
