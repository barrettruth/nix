{
  config,
  lib,
  pkgs,
  identity,
  mkHostSecret,
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
    ExtensionInstallForcelist = map (id: "${id};https://clients2.google.com/service/update2/crx") [
      # Bitwarden Password Manager
      "nngceckbapebfimnlniiiahkandclblb"
      # uBlock Origin Lite
      "ddkjiahejlhfcafbddmgiahcphecmpfh"
      # React Developer Tools
      "fmkadmapgofadopljbjfkapdkoienihi"
    ];
    PolicyListMultipleSourceMergeList = [ "ExtensionInstallForcelist" ];
    NTPFooterManagementNoticeEnabled = false;
    NTPFooterExtensionAttributionEnabled = false;
  };

  chromePolicyPlist = pkgs.writeText "com.google.Chrome.plist" (
    lib.generators.toPlist { escape = true; } chromePolicies
  );

  tailnetHostsBlock = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (ip: names: "${ip} ${lib.concatStringsSep " " names}") identity.tailnetHosts
  );
in
{
  networking.hostName = "mac";
  networking.computerName = "mac";

  barrett.user.name = username;

  barrett.mac.determinateInstalled = true;

  system.activationScripts.extraActivation.text = ''
    install -d -m 0755 "/Library/Managed Preferences"
    if ! cmp -s ${chromePolicyPlist} "/Library/Managed Preferences/com.google.Chrome.plist"; then
      chrometmp=$(mktemp "/Library/Managed Preferences/.com.google.Chrome.plist.XXXXXX")
      install -m 0644 ${chromePolicyPlist} "$chrometmp"
      mv -f "$chrometmp" "/Library/Managed Preferences/com.google.Chrome.plist"
      killall cfprefsd || true
    fi

    tmp=$(mktemp)
    {
      awk '
        $0 == "# BEGIN nix-darwin tailnet" { skip = 1; next }
        $0 == "# END nix-darwin tailnet"   { skip = 0; next }
        !skip { print }
      ' /etc/hosts
      echo "# BEGIN nix-darwin tailnet"
      echo "${tailnetHostsBlock}"
      echo "# END nix-darwin tailnet"
    } >"$tmp"
    install -m 0644 -o root -g wheel "$tmp" /etc/hosts
    rm -f "$tmp"
  '';

  sops.secrets."chrome-enrollment-token" =
    mkHostSecret config.networking.hostName "chrome-enrollment-token"
      {
        mode = "0400";
      };

  system.activationScripts.postActivation.text = lib.mkOrder 1600 ''
    install -d -m 0755 -o root -g wheel /Library/Google/Chrome
    install -m 0644 -o root -g wheel \
      ${config.sops.secrets."chrome-enrollment-token".path} \
      /Library/Google/Chrome/CloudManagementEnrollmentToken
  '';

  users.users.${username}.openssh.authorizedKeys.keys = identity.sshKeys;

  services.openssh.extraConfig = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';
}
