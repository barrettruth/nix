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

  services.tailscale.enable = true;

  security.pam.services.sudo_local.touchIdAuth = true;

  programs.ssh.extraConfig = ''
    Host forge.barrettruth.com git.barrettruth.com
        HostName 100.64.0.1
        Port 2222
        HostKeyAlias forge.barrettruth.com
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
  '';

  programs.ssh.knownHosts."forge-tailnet" = {
    hostNames = [
      "[forge.barrettruth.com]:2222"
      "[git.barrettruth.com]:2222"
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJlaElaGlwSxKvtujoAnGWSrZWlxZRdviq3Y9TgZCLZ/";
  };

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
    age
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
    sops
    ssh-to-age
    tree
    wget
  ];
}
