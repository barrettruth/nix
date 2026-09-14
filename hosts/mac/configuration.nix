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

  browserPolicies = {
    SearchSuggestEnabled = true;
    HttpsOnlyMode = "force_enabled";
    BookmarkBarEnabled = false;
    PasswordManagerEnabled = false;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    ImportBookmarks = false;
    DnsOverHttpsMode = "off";
    BlockThirdPartyCookies = true;
    CookieAllowedForUrls = [ "[*.]shibidp.virginia.edu" ];
    RestoreOnStartup = 1;
  };

  browserPolicyDomain = config.barrett.mac.browser.bundleId;

  browserPolicyPlist = pkgs.writeText "${browserPolicyDomain}.plist" (
    lib.generators.toPlist { escape = true; } browserPolicies
  );

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
    if ! cmp -s ${browserPolicyPlist} "/Library/Managed Preferences/${browserPolicyDomain}.plist"; then
      browsertmp=$(mktemp "/Library/Managed Preferences/.${browserPolicyDomain}.plist.XXXXXX")
      install -m 0644 ${browserPolicyPlist} "$browsertmp"
      mv -f "$browsertmp" "/Library/Managed Preferences/${browserPolicyDomain}.plist"
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

  services.openssh.extraConfig = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';
}
