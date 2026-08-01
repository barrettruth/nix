{
  lib,
  pkgs,
  identity,
  ...
}:
let
  username = "barrett";

  hidKeyboardUsage = usage: 30064771072 + usage;
  capsLock = hidKeyboardUsage 57;
  leftControl = hidKeyboardUsage 224;
  rightCommand = hidKeyboardUsage 231;
  f14 = hidKeyboardUsage 105;

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

  # nixpkgs applies commandLineArgs only to bin/google-chrome-stable on
  # darwin; the .app is copied unwrapped, so Dock launches would miss the
  # flag. Chrome is signed with library validation, so the bundle cannot be
  # patched in place. Ship a small launcher bundle instead that execs the
  # signed binary. The flag silences the debugger banner the Midnight
  # extension triggers via Emulation.setAutoDarkModeOverride.
  chromeFlags = [ "--silent-debugger-extension-api" ];

  chromeWrapped = pkgs.runCommand "google-chrome-wrapped" { } ''
    real="${pkgs.google-chrome}/Applications/Google Chrome.app"
    app="$out/Applications/Google Chrome.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$out/bin"

    cp "$real/Contents/Resources/app.icns" "$app/Contents/Resources/app.icns"

    cat >"$app/Contents/Info.plist" <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key><string>chrome</string>
      <key>CFBundleIdentifier</key><string>com.barrettruth.google-chrome</string>
      <key>CFBundleName</key><string>Google Chrome</string>
      <key>CFBundleDisplayName</key><string>Google Chrome</string>
      <key>CFBundleIconFile</key><string>app.icns</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>${pkgs.google-chrome.version}</string>
      <key>LSMinimumSystemVersion</key><string>11.0</string>
      <key>LSRequiresNativeExecution</key><true/>
      <key>LSArchitecturePriority</key><array><string>${pkgs.stdenv.hostPlatform.darwinArch}</string></array>
    </dict>
    </plist>
    PLIST

    cat >"$app/Contents/MacOS/chrome" <<EOF
    #!/bin/sh
    exec /usr/bin/arch -${pkgs.stdenv.hostPlatform.darwinArch} "$real/Contents/MacOS/Google Chrome" ${builtins.concatStringsSep " " chromeFlags} "\$@"
    EOF
    chmod +x "$app/Contents/MacOS/chrome"

    cat >"$out/bin/google-chrome-stable" <<EOF
    #!/bin/sh
    exec /usr/bin/arch -${pkgs.stdenv.hostPlatform.darwinArch} "$real/Contents/MacOS/Google Chrome" ${builtins.concatStringsSep " " chromeFlags} "\$@"
    EOF
    chmod +x "$out/bin/google-chrome-stable"
  '';

  # nix-darwin has no networking.hosts. Without these the public A records
  # win, and they point at an address that does not answer, so every
  # request to a self-hosted service stalls until it times out.
  tailnetHostsBlock = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (ip: names: "${ip} ${lib.concatStringsSep " " names}") identity.tailnetHosts
  );

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

  system.keyboard = {
    enableKeyMapping = true;
    userKeyMapping = [
      {
        HIDKeyboardModifierMappingSrc = capsLock;
        HIDKeyboardModifierMappingDst = leftControl;
      }
      {
        HIDKeyboardModifierMappingSrc = leftControl;
        HIDKeyboardModifierMappingDst = capsLock;
      }
      {
        HIDKeyboardModifierMappingSrc = rightCommand;
        HIDKeyboardModifierMappingDst = f14;
      }
    ];
  };

  # nix.enable is off, so nix.gc is never emitted: everything under
  # managedConfig is gated on it, which is also why nix.settings would be
  # silently dropped here. Determinate ships no collection of its own.
  launchd.daemons.nix-gc = {
    serviceConfig.StartCalendarInterval = [
      {
        Hour = 4;
        Minute = 0;
      }
    ];
    script = ''
      nix=/nix/var/nix/profiles/default/bin
      "$nix/nix-env" --profile /nix/var/nix/profiles/system --delete-generations +5
      "$nix/nix-collect-garbage" --delete-older-than 30d
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

    # power.sleep drives systemsetup, which only writes the AC profile.
    # The battery profile keeps macOS defaults of 1 and 2 minutes.
    /usr/bin/pmset -b displaysleep 5 sleep 15 disksleep 10

    # login(1) prints "Last login:" unless this exists.
    install -m 0644 -o ${username} -g staff /dev/null "/Users/${username}/.hushlogin"

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

    # The laptop prunes to +5 and the vps to +2; nix-darwin has no
    # equivalent, and determinate ships no scheduled collection, so do it
    # here. nix.enable is off, so use the determinate nix-env directly.
    /nix/var/nix/profiles/default/bin/nix-env \
      --profile /nix/var/nix/profiles/system --delete-generations +5
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
      "desktop.ts.barrettruth.com"
      "100.64.0.1"
    ];
    publicKey = identity.hostKeys.desktop;
  };

  programs.ssh.knownHosts.laptop = {
    hostNames = [
      "laptop"
      "laptop.ts.barrettruth.com"
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

  # No nix-darwin option exists for the ambient light sensor, so write the
  # domain directly. It is the "Automatically adjust brightness" toggle in
  # System Settings > Displays.
  # The domain must be an absolute path: CustomSystemPreferences emits a bare
  # `defaults write <domain>` as root, which would land in
  # /var/root/Library/Preferences rather than the system-wide location.
  system.defaults.CustomSystemPreferences."/Library/Preferences/com.apple.iokit.AmbientLightSensor" =
    {
      "Automatic Display Enabled" = false;
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
    chromeWrapped
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
