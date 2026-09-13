{ config, pkgs, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv = {
      enable = true;
      package = pkgs.nix-direnv.override { nix = config.nix.package; };
    };
    settings = builtins.fromTOML (builtins.readFile ../../config/direnv/config.toml);
  };
}
