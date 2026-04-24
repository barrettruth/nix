{
  description = "Barrett Ruth's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    devin = {
      url = "github:charliemeyer2000/devin-cli-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-whisper.url = "github:nixos/nixpkgs/a499dfba7b52aac86504356512836550e9d49a5a";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    direnv-instant.url = "github:Mic92/direnv-instant";
    codex.url = "github:sadjow/codex-cli-nix";
    tmux-mosaic = {
      url = "github:barrettruth/tmux-mosaic";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      imports = [
        ./modules/nixpkgs.nix
        ./modules/identity.nix
        ./modules/theme.nix
        ./modules/devshells.nix
        ./modules/hosts/xps15.nix
        ./modules/hosts/netcup.nix
      ];
    };
}
