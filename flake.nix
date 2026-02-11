{
  description = "Barrett Ruth's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    neovim-nightly.url = "github:nix-community/neovim-nightly-overlay";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code.url = "github:ryoppippi/claude-code-overlay";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nixos-hardware,
      neovim-nightly,
      zen-browser,
      claude-code,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "slack"
            "claude-code"
            "claude"
            "nvidia-x11"
            "nvidia-settings"
            "apple_cursor"
          ];
        overlays = [
          neovim-nightly.overlays.default
          claude-code.overlays.default
        ];
      };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      nixosConfigurations.xps15 = nixpkgs.lib.nixosSystem {
        modules = [
          nixos-hardware.nixosModules.dell-xps-15-9500-nvidia
          ./hosts/xps15/configuration.nix
          {
            nixpkgs.hostPlatform = system;
            nixpkgs.overlays = [
              neovim-nightly.overlays.default
              claude-code.overlays.default
            ];
            nixpkgs.config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "slack"
                "claude-code"
                "claude"
                "nvidia-x11"
                "nvidia-settings"
                "apple_cursor"
              ];
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.users.barrett = import ./home/home.nix;
            home-manager.extraSpecialArgs = {
              inherit zen-browser;
              hostPlatform = system;
            };
          }
        ];
        specialArgs = {
          inherit nixpkgs;
        };
      };

      homeConfigurations.barrett = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit zen-browser;
          hostPlatform = system;
        };
        modules = [ ./home/home.nix ];
      };
    };
}
