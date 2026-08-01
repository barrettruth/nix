{ pkgs, ... }:
let
  username = "barrett";
in
{
  networking.hostName = "mac";
  networking.computerName = "mac";

  system.primaryUser = username;
  system.stateVersion = 6;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  nix.enable = false;

  programs.zsh.enable = true;

  system.defaults = {
    dock = {
      autohide = true;
      show-recents = false;
      persistent-apps = [
        { app = "/Applications/Nix Apps/Chromium.app"; }
        { app = "/Applications/Nix Apps/Ghostty.app"; }
      ];
      persistent-others = [ ];
    };
    NSGlobalDomain."com.apple.swipescrolldirection" = true;
  };

  environment.systemPackages = with pkgs; [
    chromium
    curl
    fd
    fzf
    eza
    zoxide
    ghostty
    git
    gh
    jq
    just
    neovim
    ripgrep
    tree
    wget
  ];
}
