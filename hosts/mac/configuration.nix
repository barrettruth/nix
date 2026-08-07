{
  config,
  lib,
  pkgs,
  act,
  identity,
  ...
}:
let
  username = "barrett";
  screenshotDir = "${config.barrett.user.homeDirectory}/Pictures/Screenshots";

  hidKeyboardUsage = usage: 30064771072 + usage;
  capsLock = hidKeyboardUsage 57;
  leftControl = hidKeyboardUsage 224;
  rightCommand = hidKeyboardUsage 231;
  f18 = hidKeyboardUsage 109;

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

  chromeFlags = [ "--silent-debugger-extension-api" ];

  chromePkg = pkgs.google-chrome.override {
    commandLineArgs = lib.concatStringsSep " " chromeFlags;
  };

  # nix-darwin has no networking.hosts. Without these the public A records
  # win, and they point at an address that does not answer, so every
  # request to a self-hosted service stalls until it times out.
  tailnetHostsBlock = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (ip: names: "${ip} ${lib.concatStringsSep " " names}") identity.tailnetHosts
  );

  ghosttyApp = "/Applications/Nix Apps/Ghostty.app";
  chromeApp = "/Applications/Nix Apps/Google Chrome.app";
  rectangleApp = "/Applications/Nix Apps/Rectangle.app";

  # ctl idle had no macOS analogue worth porting; caffeinate is built in.
  idleToggle = pkgs.writeShellScript "idle-toggle" ''
    if /usr/bin/pgrep -x caffeinate >/dev/null 2>&1; then
      /usr/bin/killall caffeinate
    else
      /usr/bin/caffeinate -d &
    fi
  '';

  rectangleAction = pkgs.writeShellScript "rectangle-action" ''
    exec /usr/bin/open -g -a "${rectangleApp}" "rectangle://execute-action?name=$1"
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
      ralt - t : open -a "${ghosttyApp}"
      ralt - b : open -a "${chromeApp}"
      ralt - f : open -a Finder
      ralt - i : ${idleToggle}

      ralt - tab : ${pkgs.skhd}/bin/skhd -k "cmd - tab"
      ralt + shift - tab : ${pkgs.skhd}/bin/skhd -k "cmd + shift - tab"
      ralt - 0x32 : ${pkgs.skhd}/bin/skhd -k "cmd - 0x32"
      ralt - q : ${pkgs.skhd}/bin/skhd -k "cmd - q"
      ralt - w : ${pkgs.skhd}/bin/skhd -k "cmd - w"

      ralt - return : ${rectangleAction} maximize
      ralt - left : ${rectangleAction} left-half
      ralt - right : ${rectangleAction} right-half
      ralt - up : ${rectangleAction} top-half
      ralt - down : ${rectangleAction} bottom-half
      ralt - c : ${rectangleAction} center
    '';
  };

  launchd.user.agents.skhd.serviceConfig.ProgramArguments = lib.mkForce [
    "/bin/sh"
    "-c"
    "/bin/wait4path /nix/store && exec ${pkgs.skhd}/bin/skhd -c ${
      config.environment.etc."skhdrc".source
    }"
  ];

  launchd.user.agents.rectangle = {
    command = ''"${rectangleApp}/Contents/MacOS/Rectangle"'';
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
    };
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
        HIDKeyboardModifierMappingDst = f18;
      }
    ];
  };

  launchd.user.agents.keyboard-mapping = {
    command = "/usr/bin/hidutil property --set '${
      builtins.toJSON { UserKeyMapping = config.system.keyboard.userKeyMapping; }
    }'";
    serviceConfig.RunAtLoad = true;
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
    if ! cmp -s ${chromePolicyPlist} "/Library/Managed Preferences/com.google.Chrome.plist"; then
      chrometmp=$(mktemp "/Library/Managed Preferences/.com.google.Chrome.plist.XXXXXX")
      install -m 0644 ${chromePolicyPlist} "$chrometmp"
      mv -f "$chrometmp" "/Library/Managed Preferences/com.google.Chrome.plist"
    fi

    # power.sleep drives systemsetup, which only writes the AC profile.
    # The battery profile keeps macOS defaults of 1 and 2 minutes.
    /usr/bin/pmset -b displaysleep 5 sleep 15 disksleep 10 lessbright 0

    # login(1) prints "Last login:" unless this exists.
    install -m 0644 -o ${username} -g staff /dev/null "/Users/${username}/.hushlogin"

    ${act.installDirMode "0755" screenshotDir}

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
    screencapture.location = screenshotDir;
    NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically = false;
    NSGlobalDomain."com.apple.swipescrolldirection" = true;
    CustomUserPreferences."com.apple.loginwindow" = {
      TALLogoutSavesState = false;
      LoginwindowLaunchesRelaunchApps = false;
    };
  };

  launchd.user.agents.ghostty = {
    command = ''/usr/bin/open -a "/Applications/Nix Apps/Ghostty.app"'';
    serviceConfig.RunAtLoad = true;
  };

  launchd.user.agents.google-chrome = {
    command = ''/usr/bin/open -a "${chromeApp}" --args ${lib.concatStringsSep " " chromeFlags}'';
    serviceConfig.RunAtLoad = true;
  };

  launchd.daemons.activate-system.serviceConfig = {
    StandardOutPath = "/var/log/activate-system.log";
    StandardErrorPath = "/var/log/activate-system.log";
  };

  environment.systemPackages = with pkgs; [
    age
    chromePkg
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
