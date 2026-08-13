{
  lib,
  pkgs,
  identity,
  ...
}:
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
    DnsOverHttpsMode = "off";
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
    lib.generators.toPlist { escape = true; } chromePolicies
  );

  # nix-darwin has no networking.hosts. Without these the public A records
  # win, and they point at an address that does not answer, so every
  # request to a self-hosted service stalls until it times out.
  tailnetHostsBlock = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (ip: names: "${ip} ${lib.concatStringsSep " " names}") identity.tailnetHosts
  );
in
{
  networking.hostName = "mac";
  networking.computerName = "mac";

  barrett.user.name = username;

  system.activationScripts.extraActivation.text = ''
    install -d -m 0755 "/Library/Managed Preferences"
    if ! cmp -s ${chromePolicyPlist} "/Library/Managed Preferences/com.google.Chrome.plist"; then
      chrometmp=$(mktemp "/Library/Managed Preferences/.com.google.Chrome.plist.XXXXXX")
      install -m 0644 ${chromePolicyPlist} "$chrometmp"
      mv -f "$chrometmp" "/Library/Managed Preferences/com.google.Chrome.plist"
    fi

    tmp=$(mktemp)
    awk '
      $0 == "# BEGIN nix-darwin tailnet" { skip = 1; next }
      $0 == "# END nix-darwin tailnet"   { skip = 0; next }
      !skip { print }
    ' /etc/hosts >"$tmp"
    {
      echo "# BEGIN nix-darwin tailnet"
      echo "${tailnetHostsBlock}"
      echo "# END nix-darwin tailnet"
    } >>"$tmp"
    install -m 0644 -o root -g wheel "$tmp" /etc/hosts
    rm -f "$tmp"
  '';

  programs.ssh.extraConfig = ''
    Host forge.barrettruth.com git.barrettruth.com
        HostName 100.64.0.1
        Port 2222
        HostKeyAlias forge.barrettruth.com
        IdentityFile /Users/${username}/.ssh/id_ed25519
        IdentitiesOnly yes
  '';

  programs.ssh.knownHosts.desktop = {
    hostNames = [
      "desktop"
      "desktop.${identity.tailnetDomain}"
      "100.64.0.1"
    ];
    publicKey = identity.hostKeys.desktop;
  };

  programs.ssh.knownHosts.laptop = {
    hostNames = [
      "laptop"
      "laptop.${identity.tailnetDomain}"
      "100.64.0.2"
    ];
    publicKey = identity.hostKeys.laptop;
  };

  programs.ssh.knownHosts."forge-tailnet" = {
    hostNames = [
      "[forge.barrettruth.com]:2222"
      "[git.barrettruth.com]:2222"
    ];
    publicKey = identity.hostKeys.forge-tailnet;
  };
}
