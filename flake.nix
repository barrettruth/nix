{
  description = "Barrett Ruth's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code.url = "github:ryoppippi/claude-code-overlay";
    neovim-nightly.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nixos-hardware,
      zen-browser,
      claude-code,
      neovim-nightly,
      ...
    }:
    let
      overlays = [
        claude-code.overlays.default
        neovim-nightly.overlays.default
      ];

      sharedUnfree = [
        "slack"
        "claude-code"
        "claude"
        "apple_cursor"
        "graphite-cli"
      ];

      mkPkgs =
        system: extraUnfree:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg: builtins.elem (nixpkgs.lib.getName pkg) (sharedUnfree ++ extraUnfree);
          inherit overlays;
        };

      xps15Config = {
        isNixOS = true;
        isLinux = true;
        isDarwin = false;
        gpu = "nvidia";
        backlightDevice = "intel_backlight";
        platform = "x86_64-linux";
      };

      macConfig = {
        isNixOS = false;
        isLinux = false;
        isDarwin = true;
        gpu = "apple";
        backlightDevice = null;
        platform = "aarch64-darwin";
      };

      macWorkConfig = {
        isNixOS = false;
        isLinux = false;
        isDarwin = true;
        gpu = "apple";
        backlightDevice = null;
        platform = "aarch64-darwin";
      };

      linuxWorkConfig = {
        isNixOS = false;
        isLinux = true;
        isDarwin = false;
        gpu = null;
        backlightDevice = null;
        platform = "x86_64-linux";
      };

      mkHome =
        hostConfig:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs hostConfig.platform [ ];
          extraSpecialArgs = {
            inherit zen-browser hostConfig;
          };
          modules = [ ./home/home.nix ];
        };
    in
    {
      formatter.x86_64-linux = (mkPkgs "x86_64-linux" [ ]).nixfmt-tree;

      nixosConfigurations.xps15 = nixpkgs.lib.nixosSystem {
        modules = [
          nixos-hardware.nixosModules.dell-xps-15-9500-nvidia
          ./hosts/xps15/configuration.nix
          {
            nixpkgs.hostPlatform = "x86_64-linux";
            nixpkgs.overlays = overlays;
            nixpkgs.config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) (
                sharedUnfree
                ++ [
                  "nvidia-x11"
                  "nvidia-settings"
                  "tailscale"
                  "libfprint-2-tod1-goodix"
                ]
              );
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.users.barrett = import ./home/home.nix;
            home-manager.extraSpecialArgs = {
              inherit zen-browser;
              hostConfig = xps15Config;
            };
          }
        ];
        specialArgs = {
          inherit nixpkgs;
        };
      };

      homeConfigurations = {
        "barrett@mac" = mkHome macConfig;
        "barrett@mac-work" = mkHome macWorkConfig;
        "barrett@linux-work" = mkHome linuxWorkConfig;
      };
    };
}
