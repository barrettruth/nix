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
    nixpkgs-master.url = "github:nixos/nixpkgs/a499dfba7b52aac86504356512836550e9d49a5a";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    direnv-instant.url = "github:Mic92/direnv-instant";
    vimdoc-language-server.url = "github:barrettruth/vimdoc-language-server";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-master,
      home-manager,
      nixos-hardware,
      zen-browser,
      claude-code,
      neovim-nightly,
      disko,
      direnv-instant,
      vimdoc-language-server,
      ...
    }:
    let
      pinnedPkgs = import nixpkgs-master { system = "x86_64-linux"; };

      overlays = [
        claude-code.overlays.default
        neovim-nightly.overlays.default
        (_: _: { bitwarden-desktop = pinnedPkgs.bitwarden-desktop; })
      ];

      sharedUnfree = [
        "slack"
        "claude-code"
        "claude"
        "apple_cursor"
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
          modules = [
            direnv-instant.homeModules.direnv-instant
            ./home/home.nix
          ];
        };
    in
    {
      formatter.x86_64-linux = (mkPkgs "x86_64-linux" [ ]).nixfmt-tree;

      devShells.x86_64-linux =
        let
          pkgs = mkPkgs "x86_64-linux" [ ];
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.deadnix
              pkgs.statix
              pkgs.nixfmt
              pkgs.pre-commit
              pkgs.nodePackages.prettier
              pkgs.shfmt
              pkgs.stylua
              pkgs.selene
            ];
          };
          neovim = pkgs.mkShell {
            packages = [
              pkgs.prettier
              pkgs.stylua
              pkgs.selene
              pkgs.lua-language-server
              vimdoc-language-server.packages.x86_64-linux.default
              (pkgs.luajit.withPackages (ps: [
                ps.busted
                ps.nlua
              ]))
            ];
          };
        };

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
                  "brgenml1lpr"
                  "cuda_cccl"
                  "cuda_cudart"
                  "libcublas"
                  "cuda_nvcc"
                ]
              );
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.sharedModules = [ direnv-instant.homeModules.direnv-instant ];
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

      nixosConfigurations.netcup = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          ./hosts/netcup/configuration.nix
          { nixpkgs.hostPlatform = "x86_64-linux"; }
        ];
      };
    };
}
