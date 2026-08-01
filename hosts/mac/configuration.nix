{ lib, pkgs, ... }:
let
  username = "barrett";

  # Mirrors programs.chromium.extraOpts on the laptop. macOS has no
  # equivalent module, so the policies are rendered to the managed
  # preferences domain by hand.
  chromePolicies = {
    BrowserSigninEnabled = 1;
    SyncDisabled = false;
    SpellCheckServiceEnabled = true;
    SearchSuggestEnabled = true;
    UrlKeyedAnonymizedDataCollectionEnabled = true;
    HttpsOnlyMode = "force_enabled";
    BookmarkBarEnabled = false;
    PasswordManagerEnabled = false;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    TranslateEnabled = true;
    ImportBookmarks = false;
    SafeBrowsingProtectionLevel = 1;
    DnsOverHttpsMode = "automatic";
    BlockThirdPartyCookies = true;
    CookieAllowedForUrls = [ "[*.]shibidp.virginia.edu" ];
    RestoreOnStartup = 1;
    NewTabPageLocation = "chrome-extension://demmbkpegigoeiappcbliinlijmeoaop/newtab.html";
    ExtensionInstallForcelist = map (id: "${id};https://clients2.google.com/service/update2/crx") [
      # Bitwarden Password Manager
      "nngceckbapebfimnlniiiahkandclblb"
      # uBlock Origin Lite
      "ddkjiahejlhfcafbddmgiahcphecmpfh"
      # React Developer Tools
      "fmkadmapgofadopljbjfkapdkoienihi"
    ];
  };

  chromePolicyPlist = pkgs.writeText "com.google.Chrome.plist" (
    lib.generators.toPlist { } chromePolicies
  );
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

  barrett.workstation.enable = true;

  security.pam.services.sudo_local.touchIdAuth = true;

  fonts.packages = [ pkgs.barrett-fonts ];

  system.activationScripts.extraActivation.text = ''
    install -d -m 0755 "/Library/Managed Preferences"
    install -m 0644 ${chromePolicyPlist} "/Library/Managed Preferences/com.google.Chrome.plist"
  '';

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
        { app = "/Applications/Nix Apps/Google Chrome.app"; }
        { app = "/Applications/Nix Apps/Ghostty.app"; }
      ];
      persistent-others = [ ];
    };
    NSGlobalDomain."com.apple.swipescrolldirection" = true;
  };

  environment.systemPackages = with pkgs; [
    age
    google-chrome
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
