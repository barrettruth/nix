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

  ghosttyApp = "/Applications/Nix Apps/Ghostty.app";
  chromeApp = "/Applications/Nix Apps/Google Chrome.app";

  # ctl idle had no macOS analogue worth porting; caffeinate is built in.
  idleToggle = pkgs.writeShellScript "idle-toggle" ''
    if /usr/bin/pgrep -x caffeinate >/dev/null 2>&1; then
      /usr/bin/killall caffeinate
    else
      /usr/bin/caffeinate -d &
    fi
  '';

  chromePolicyPlist = pkgs.writeText "com.google.Chrome.plist" (
    lib.generators.toPlist { escape = true; } chromePolicies
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

  services.skhd = {
    enable = true;
    skhdConfig = ''
      alt + ctrl - t : open -a "${ghosttyApp}"
      alt + ctrl - b : open -a "${chromeApp}"
      alt + shift - return : open -a "${ghosttyApp}"
      alt + shift - b : open -a "${chromeApp}"
      alt + ctrl - i : ${idleToggle}
    '';
  };

  power.sleep = {
    computer = 30;
    display = 10;
    harddisk = 30;
  };

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
        IdentityFile /Users/${username}/.ssh/id_ed25519
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
    NSGlobalDomain."com.apple.swipescrolldirection" = false;
  };

  environment.systemPackages = with pkgs; [
    age
    google-chrome
    rectangle
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
