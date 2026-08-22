{
  config,
  lib,
  pkgs,
  act,
  themeGenerators,
  ...
}:
let
  username = config.barrett.user.name;
  homeDirectory = config.barrett.user.homeDirectory;
  screenshotDir = "${homeDirectory}/Pictures/Screenshots";

  hidKeyboardUsage = usage: 30064771072 + usage;
  capsLock = hidKeyboardUsage 57;
  leftControl = hidKeyboardUsage 224;
  rightCommand = hidKeyboardUsage 231;
  f18 = hidKeyboardUsage 109;

  chromePkg = pkgs.google-chrome;

  ghosttyApp = "/Applications/Nix Apps/Ghostty.app";
  trexApp = "/Applications/Nix Apps/TRex.app";

  chrome = config.barrett.mac.chrome;
  chromeApp = chrome.app;

  midnightExtension = pkgs.callPackage ../../../pkgs/midnight-extension {
    themeCss = pkgs.writeText "chromium-theme.css" themeGenerators.mkChromeThemeCss;
    themeJs = pkgs.writeText "chromium-theme.js" themeGenerators.mkChromeThemeJs;
    version = "1.0";
  };

  unpackedDir = "${homeDirectory}/.config/chromium/extension";

  launchApps = config.barrett.mac.apps;

  aerospace = "${config.services.aerospace.package}/bin/aerospace";

  scripts = config.barrett.workstation.scriptsPath;

  workspaces = map toString (lib.range 1 9);

  appBindings = lib.concatMapStringsSep "\n" (
    app:
    let
      switch = lib.optionalString (app.space != null) "${aerospace} workspace ${toString app.space}; ";
    in
    ''lalt - ${app.key} : ${switch}/usr/bin/open -a "${app.path}"''
  ) (lib.filter (app: app.key != null) launchApps);

  aerospaceBindings = lib.concatStringsSep "\n" (
    map (n: "lalt - ${n} : ${aerospace} workspace ${n}") workspaces
    ++ map (n: "lalt + shift - ${n} : ${aerospace} move-node-to-workspace ${n}") workspaces
  );

  asUser = ''launchctl asuser "$(id -u -- ${username})" sudo --user=${username} --'';

  pinnedApps = lib.filter (app: app.space != null && app.bundleId != null) launchApps;

  trexCapture = pkgs.writeShellScript "trex-capture" ''
    exec /usr/bin/open -a "${trexApp}" "trex://capture"
  '';

  # Chrome holds Preferences in memory and rewrites it on exit, so seeding a
  # running browser is silently undone. Skipped rather than lost.
  seedChromeShortcuts = pkgs.writeShellScript "seed-chrome-shortcuts" ''
    set -eu
    if /usr/bin/pgrep -qf "Google Chrome.app/Contents/MacOS/Google Chrome"; then
      echo "seed-chrome-shortcuts: chrome is running, skipping" >&2
      exit 0
    fi
    for profile in "$HOME/Library/Application Support/Google/Chrome/Default" \
                   "$HOME/Library/Application Support/Google/Chrome/Profile "*; do
      [ -f "$profile/Preferences" ] || continue
      ${pkgs.python3}/bin/python3 \
        "${config.barrett.user.homeDirectory}/.config/nix/config/chromium/seed_shortcuts.py" \
        mac "$profile/Preferences"
    done
  '';
in
{
  options.barrett.mac.dock.apps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Absolute paths of the applications pinned to the Dock, in order.";
  };

  options.barrett.mac.apps = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          key = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "skhd key, pressed with lalt. Null pins the app without a binding.";
          };
          path = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path of the application bundle.";
          };
          bundleId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "CFBundleIdentifier, required to pin the app to a workspace.";
          };
          space = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "AeroSpace workspace the app's windows open on.";
          };
        };
      }
    );
    default = [ ];
    description = "Applications reachable from the launch prefix.";
  };

  options.barrett.mac.floatingApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "CFBundleIdentifiers left floating rather than tiled.";
  };

  options.barrett.mac.chrome = {
    app = lib.mkOption {
      type = lib.types.str;
      default = "/Applications/Nix Apps/Google Chrome.app";
      description = "Absolute path of the Google Chrome application bundle.";
    };
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = chromePkg;
      description = "Chrome to install, or null when the machine already has one.";
    };
    flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Switches the login agent passes on a cold start.";
    };
    unpackedMidnight = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Stage Midnight for a manual unpacked load, for hosts that cannot reach a policy location.";
    };
  };

  config = {
    barrett.mac.dock.apps = [
      chromeApp
      ghosttyApp
    ];

    barrett.mac.apps = [
      {
        key = "t";
        path = ghosttyApp;
      }
      {
        key = "b";
        path = chromeApp;
      }
    ];

    barrett.mac.floatingApps = [ "com.apple.finder" ];

    system.stateVersion = 6;
    system.primaryUser = username;

    users.users.${username} = {
      name = username;
      home = config.barrett.user.homeDirectory;
    };

    programs.zsh.enable = true;

    barrett.workstation.enable = true;

    security.pam.services.sudo_local.touchIdAuth = true;

    services.skhd = {
      enable = true;
      skhdConfig = ''
        ${appBindings}
        lalt - n : open -a Finder

        ralt - o : ${trexCapture}
        ralt - t : ${scripts}/theme

        lalt - a : ${aerospace} focus --boundaries-action wrap-around-the-workspace dfs-next
        lalt - f : ${aerospace} focus --boundaries-action wrap-around-the-workspace dfs-prev
        lalt - u : ${aerospace} swap --wrap-around dfs-prev
        lalt - d : ${aerospace} swap --wrap-around dfs-next

        lalt - h : ${aerospace} resize width -50
        lalt - l : ${aerospace} resize width +50
        lalt - j : ${aerospace} resize height +50
        lalt - k : ${aerospace} resize height -50
        lalt - 0x18 : ${aerospace} balance-sizes

        lalt - return : ${aerospace} fullscreen
        lalt - c : ${aerospace} layout floating tiling
        lalt - space : ${aerospace} layout tiles accordion
        lalt + shift - space : ${aerospace} layout horizontal vertical

        lalt - 0x2B : ${aerospace} focus-monitor prev
        lalt - 0x2F : ${aerospace} focus-monitor next
        lalt + shift - 0x2B : ${aerospace} move-node-to-monitor prev
        lalt + shift - 0x2F : ${aerospace} move-node-to-monitor next

        lalt - tab : ${aerospace} workspace-back-and-forth
        lalt + shift - r : ${aerospace} flatten-workspace-tree

        ${aerospaceBindings}

        lalt + shift - tab : ${pkgs.skhd}/bin/skhd -k "cmd + shift - tab"
        lalt - 0x32 : ${pkgs.skhd}/bin/skhd -k "cmd - 0x32"
        lalt - q : ${aerospace} close
        lalt + shift - q : ${pkgs.skhd}/bin/skhd -k "cmd - q"
      '';
    };

    services.aerospace = {
      enable = true;
      settings = {
        default-root-container-layout = "tiles";
        default-root-container-orientation = "auto";
        on-window-detected =
          map (id: {
            "if".app-id = id;
            run = "layout floating";
          }) config.barrett.mac.floatingApps
          ++ map (app: {
            "if".app-id = app.bundleId;
            run = "move-node-to-workspace ${toString app.space}";
          }) pinnedApps;
      };
    };

    launchd.user.agents.skhd.serviceConfig.ProgramArguments = lib.mkForce [
      "/bin/sh"
      "-c"
      "/bin/wait4path /nix/store && exec ${pkgs.skhd}/bin/skhd -c ${
        config.environment.etc."skhdrc".source
      }"
    ];

    launchd.user.agents.trex = {
      command = ''"${trexApp}/Contents/MacOS/TRex"'';
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

    # nix.gc prunes by age alone, and the count matters as much here as it does
    # on the laptop, so the schedule is its own rather than nix-darwin's.
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

    fonts.packages = lib.optional (pkgs ? barrett-fonts) pkgs.barrett-fonts;

    system.activationScripts.extraActivation.text = ''
      # power.sleep drives systemsetup, which only writes the AC profile.
      # The battery profile keeps macOS defaults of 1 and 2 minutes.
      /usr/bin/pmset -b displaysleep 5 sleep 15 disksleep 10 lessbright 0

      # login(1) prints "Last login:" unless this exists.
      install -m 0644 -o ${username} -g staff /dev/null "${config.barrett.user.homeDirectory}/.hushlogin"

      ${act.installDirMode "0755" screenshotDir}

      ${lib.optionalString chrome.unpackedMidnight ''
        ${act.installDirMode "0755" "${homeDirectory}/.config/chromium"}
        ${act.mkSymlink "${midnightExtension}" unpackedDir}
      ''}

      ${asUser} ${seedChromeShortcuts} || true

      tmp=$(mktemp)
      awk '
        $0 == "# BEGIN nix-darwin tailnet" { skip = 1; next }
        $0 == "# END nix-darwin tailnet"   { skip = 0; next }
        !skip { print }
      ' /etc/hosts >"$tmp"
      install -m 0644 -o root -g wheel "$tmp" /etc/hosts
      rm -f "$tmp"

      # The laptop prunes to +5 and the vps to +2; nix-darwin has no
      # equivalent, so do it here.
      /nix/var/nix/profiles/default/bin/nix-env \
        --profile /nix/var/nix/profiles/system --delete-generations +5
    '';

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
        persistent-apps = map (app: { inherit app; }) config.barrett.mac.dock.apps;
        persistent-others = [ ];
        expose-animation-duration = 0.0;
        autohide-delay = 0.0;
        launchanim = false;
        # macOS ships Quick Note (14) on the bottom-right corner; 1 is the
        # no-op action, which is how the corner is switched off.
        wvous-br-corner = 1;
      };
      spaces.spans-displays = true;
      screencapture.location = screenshotDir;
      NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically = false;
      NSGlobalDomain."com.apple.swipescrolldirection" = true;
      NSGlobalDomain.NSAutomaticWindowAnimationsEnabled = false;
      NSGlobalDomain.NSWindowResizeTime = 0.001;
      CustomUserPreferences."com.apple.loginwindow" = {
        TALLogoutSavesState = false;
        LoginwindowLaunchesRelaunchApps = false;
      };
    };

    launchd.user.agents.ghostty = {
      command = ''/usr/bin/open -a "${ghosttyApp}"'';
      serviceConfig.RunAtLoad = true;
    };

    launchd.user.agents.google-chrome = {
      command =
        ''/usr/bin/open -a "${chromeApp}"''
        + lib.optionalString (chrome.flags != [ ]) " --args ${lib.concatStringsSep " " chrome.flags}";
      serviceConfig.RunAtLoad = true;
    };

    launchd.daemons.activate-system.serviceConfig = {
      StandardOutPath = "/var/log/activate-system.log";
      StandardErrorPath = "/var/log/activate-system.log";
    };

    environment.systemPackages =
      lib.optional (config.barrett.mac.chrome.package != null) config.barrett.mac.chrome.package
      ++ (with pkgs; [
        age
        trex
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
      ]);
  };
}
