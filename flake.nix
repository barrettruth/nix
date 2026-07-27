{
  description = "Barrett Ruth's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixpkgs-whisper.url = "github:nixos/nixpkgs/a499dfba7b52aac86504356512836550e9d49a5a";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    codex.url = "github:sadjow/codex-cli-nix";
    devin = {
      url = "github:charliemeyer2000/devin-cli-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    googleworkspace-cli = {
      url = "github:googleworkspace/cli/a3768d0e82ad83cca2da97724e46bea4ff0e6dbd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fonts = {
      url = "git+ssh://git@forge.barrettruth.com/barrettruth/fonts.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    delta = {
      url = "git+ssh://git@forge.barrettruth.com/barrettruth/delta.git";
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
    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        ./modules/nixpkgs.nix
        ./modules/identity.nix
        ./modules/theme.nix
        ./modules/devshells.nix
        ./modules/hosts/laptop.nix
        ./modules/hosts/vps.nix
        ./modules/hosts/desktop.nix
      ];
    };
}
