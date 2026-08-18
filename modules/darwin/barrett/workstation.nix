{
  config,
  lib,
  pkgs,
  act,
  ...
}:
let
  username = config.barrett.user.name;
  screenshotDir = "${config.barrett.user.homeDirectory}/Pictures/Screenshots";

  hidKeyboardUsage = usage: 30064771072 + usage;
  capsLock = hidKeyboardUsage 57;
  leftControl = hidKeyboardUsage 224;
  rightCommand = hidKeyboardUsage 231;
  f18 = hidKeyboardUsage 109;

  chromeFlags = [ "--silent-debugger-extension-api" ];

  chromePkg = pkgs.google-chrome.override {
    commandLineArgs = lib.concatStringsSep " " chromeFlags;
  };

  ghosttyApp = "/Applications/Nix Apps/Ghostty.app";
  trexApp = "/Applications/Nix Apps/TRex.app";

  chromeApp = config.barrett.mac.chrome.app;

  amethystApp = "${pkgs.amethyst}/Applications/Amethyst.app";

  launchApps = config.barrett.mac.apps;

  appBindings = lib.concatMapStringsSep "\n" (
    app: ''lalt - ${app.key} : /usr/bin/open -a "${app.path}"''
  ) (lib.filter (app: app.key != null) launchApps);

  spaceBindings = lib.concatMapStringsSep "\n" (
    n: ''lalt - ${n} : ${pkgs.skhd}/bin/skhd -k "ctrl - ${n}"''
  ) (map toString (lib.range 1 9));

  asUser = ''launchctl asuser "$(id -u -- ${username})" sudo --user=${username} --'';

  spaceKeyCodes = [
    18
    19
    20
    21
    23
    22
    26
    28
    25
  ];

  spaceHotkeys = lib.concatStringsSep "\n" (
    lib.imap0 (
      i: code:
      let
        id = toString (118 + i);
        plist = pkgs.writeText "symbolic-hotkey-${id}.plist" (
          lib.generators.toPlist { } {
            enabled = true;
            value = {
              parameters = [
                65535
                code
                262144
              ];
              type = "standard";
            };
          }
        );
      in
      ''${asUser} /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add ${id} "$(cat ${plist})"''
    ) spaceKeyCodes
  );

  mod1 = key: {
    mod = "mod1";
    inherit key;
  };
  mod2 = key: {
    mod = "mod2";
    inherit key;
  };

  disabledCommands =
    lib.genAttrs [
      "focus-main"
      "select-tall-layout"
      "select-wide-layout"
      "select-fullscreen-layout"
      "select-column-layout"
      "toggle-focus-follows-mouse"
      "increase-window-max-count"
      "decrease-window-max-count"
    ] (_: false)
    // lib.listToAttrs (
      lib.concatMap (n: [
        (lib.nameValuePair "focus-screen-${toString n}" false)
        (lib.nameValuePair "throw-screen-${toString n}" false)
      ]) (lib.range 1 5)
    );

  amethystConfig = (pkgs.formats.yaml { }).generate "amethyst.yml" (
    {
      layouts = [
        "tall"
        "wide"
        "fullscreen"
        "column"
      ];

      mod1 = [ "option" ];
      mod2 = [
        "option"
        "shift"
      ];

      focus-ccw = mod1 "a";
      focus-cw = mod1 "f";
      swap-ccw = mod1 "u";
      swap-cw = mod1 "d";
      swap-main = mod1 "enter";

      shrink-main = mod1 "h";
      expand-main = mod1 "l";
      decrease-main = mod1 "j";
      increase-main = mod1 "k";

      cycle-layout = mod1 "space";
      cycle-layout-backward = mod2 "space";
      toggle-float = mod1 "c";
      toggle-tiling = mod2 "t";
      display-current-layout = mod1 "i";

      focus-screen-ccw = mod1 ",";
      focus-screen-cw = mod1 ".";
      swap-screen-ccw = mod2 ",";
      swap-screen-cw = mod2 ".";

      throw-space-left = mod2 "left";
      throw-space-right = mod2 "right";

      reevaluate-windows = mod2 "r";
      relaunch-amethyst = mod2 "z";

      floating = config.barrett.mac.floatingApps;
      floating-is-blacklist = true;

      window-margins = false;
      window-resize-step = 5;
      focus-follows-mouse = false;
      mouse-follows-focus = false;
      follow-space-thrown-windows = false;
      restore-layouts-on-launch = true;
      hide-menu-bar-icon = false;
      enables-layout-hud = false;
      enables-layout-hud-on-space-change = false;
      enables-window-count-hud = false;
    }
    // lib.listToAttrs (
      map (n: lib.nameValuePair "throw-space-${toString n}" (mod2 (toString n))) (lib.range 1 9)
    )
    // disabledCommands
  );

  trexCapture = pkgs.writeShellScript "trex-capture" ''
    exec /usr/bin/open -a "${trexApp}" "trex://capture"
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
        };
      }
    );
    default = [ ];
    description = "Applications reachable from the launch prefix.";
  };

  options.barrett.mac.floatingApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "CFBundleIdentifiers Amethyst leaves floating rather than tiling.";
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

    nix.enable = false;

    programs.zsh.enable = true;

    barrett.workstation.enable = true;

    security.pam.services.sudo_local.touchIdAuth = true;

    services.skhd = {
      enable = true;
      skhdConfig = ''
        ${appBindings}
        ${spaceBindings}
        lalt - n : open -a Finder
        lalt - o : ${trexCapture}

        lalt - tab : ${pkgs.skhd}/bin/skhd -k "cmd - tab"
        lalt + shift - tab : ${pkgs.skhd}/bin/skhd -k "cmd + shift - tab"
        lalt - 0x32 : ${pkgs.skhd}/bin/skhd -k "cmd - 0x32"
        lalt - q : ${pkgs.skhd}/bin/skhd -k "cmd - w"
        lalt + shift - q : ${pkgs.skhd}/bin/skhd -k "cmd - q"
      '';
    };

    launchd.user.agents.amethyst = {
      command = ''"${amethystApp}/Contents/MacOS/Amethyst"'';
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = true;
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

    fonts.packages = lib.optional (pkgs ? barrett-fonts) pkgs.barrett-fonts;

    system.activationScripts.extraActivation.text = ''
      # power.sleep drives systemsetup, which only writes the AC profile.
      # The battery profile keeps macOS defaults of 1 and 2 minutes.
      /usr/bin/pmset -b displaysleep 5 sleep 15 disksleep 10 lessbright 0

      # login(1) prints "Last login:" unless this exists.
      install -m 0644 -o ${username} -g staff /dev/null "${config.barrett.user.homeDirectory}/.hushlogin"

      ${act.installDirMode "0755" screenshotDir}

      ${act.installDirMode "0755" "${config.barrett.user.homeDirectory}/.config/amethyst"}
      ${act.mkSymlink amethystConfig "${config.barrett.user.homeDirectory}/.config/amethyst/amethyst.yml"}

      ${spaceHotkeys}
      ${asUser} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

      tmp=$(mktemp)
      awk '
        $0 == "# BEGIN nix-darwin tailnet" { skip = 1; next }
        $0 == "# END nix-darwin tailnet"   { skip = 0; next }
        !skip { print }
      ' /etc/hosts >"$tmp"
      install -m 0644 -o root -g wheel "$tmp" /etc/hosts
      rm -f "$tmp"

      # The laptop prunes to +5 and the vps to +2; nix-darwin has no
      # equivalent, and determinate ships no scheduled collection, so do it
      # here. nix.enable is off, so use the determinate nix-env directly.
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
        mru-spaces = false;
        expose-animation-duration = 0.0;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.0;
        launchanim = false;
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
      command = ''/usr/bin/open -a "${chromeApp}" --args ${lib.concatStringsSep " " chromeFlags}'';
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
        amethyst
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
