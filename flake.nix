{
  description = "Barrett Ruth's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code.url = "github:ryoppippi/claude-code-overlay";
    hyprland.url = "github:hyprwm/Hyprland";
    neovim-nightly.url = "github:nix-community/neovim-nightly-overlay";
    nixpkgs-whisper.url = "github:nixos/nixpkgs/a499dfba7b52aac86504356512836550e9d49a5a";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    direnv-instant.url = "github:Mic92/direnv-instant";
    vimdoc-language-server.url = "github:barrettruth/vimdoc-language-server";
    codex.url = "github:sadjow/codex-cli-nix";
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
