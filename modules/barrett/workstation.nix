{
  config,
  pkgs,
  lib,
  identity,
  themeGenerators,
  palettes,
  act,
  isDarwin,
  ...
}:
let
  cfg = config.barrett.workstation;
  hasDisplay = isDarwin || (config.barrett.ui.enable or false);
  user = config.barrett.user;
  username = user.name;
  inherit (user) homeDirectory;
  XDG_CONFIG_HOME = "${homeDirectory}/.config";
  XDG_DATA_HOME = "${homeDirectory}/.local/share";
  XDG_STATE_HOME = "${homeDirectory}/.local/state";
  XDG_CACHE_HOME = "${homeDirectory}/.cache";
  repo = "${XDG_CONFIG_HOME}/nix";

  scriptsPath = "${repo}/scripts";

  inherit (act) runAsUser mkSymlink;

  mkDir = act.installDirMode "0755";

  mkPrivateDir = act.installDirMode "0700";

  readTheme = ''
    theme="$(cat "${XDG_STATE_HOME}/theme" 2>/dev/null)" || theme="midnight"
    [ -z "$theme" ] && theme="midnight"
  '';

  zshInit = pkgs.writeText "zsh-init" ''
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
    source ${pkgs.fzf}/share/fzf/key-bindings.zsh
    source ${pkgs.fzf}/share/fzf/completion.zsh
    eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
    alias ls="${pkgs.eza}/bin/eza --git"
    source ${repo}/config/zsh/zshrc
  '';

  fzfThemes = pkgs.runCommand "fzf-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight << 'FZFMIDNIGHT'
    ${themeGenerators.mkFzfTheme palettes.midnight}
    FZFMIDNIGHT

    cat > $out/daylight << 'FZFDAYLIGHT'
    ${themeGenerators.mkFzfTheme palettes.daylight}
    FZFDAYLIGHT
  '';

  ghosttyDarwinConf = pkgs.writeText "ghostty-config-darwin" ''
    config-file = ${repo}/config/ghostty/config
    macos-option-as-alt = false
    keybind = f18=esc:x
    keybind = super+r=reload_config
    keybind = super+y=copy_to_clipboard
    keybind = super+p=paste_from_clipboard
    keybind = super+shift+h=decrease_font_size:1
    keybind = super+shift+l=increase_font_size:1
    keybind = super+c=unbind
    keybind = super+v=unbind
    keybind = super+t=unbind
  '';

  ghosttyConfig = if isDarwin then "${ghosttyDarwinConf}" else "${repo}/config/ghostty/config";

  clangdConfigDir =
    if isDarwin then "${homeDirectory}/Library/Preferences/clangd" else "${XDG_CONFIG_HOME}/clangd";

  chromiumThemeCss = pkgs.writeText "chromium-theme.css" themeGenerators.mkChromeThemeCss;
  chromiumThemeJs = pkgs.writeText "chromium-theme.js" themeGenerators.mkChromeThemeJs;

  isImc = isDarwin && config.networking.hostName == "imc";

  agentPackages =
    lib.optionals (!isImc) [ pkgs.devin-cli ] ++ lib.optionals isImc [ pkgs.mcp-gdrive ];

  agentSkillDirs = [ "${homeDirectory}/.agents/skills" ];

  devinConfig = (pkgs.formats.json { }).generate "devin-config.json" {
    agent.model = "claude-opus-5-xhigh-fast";
    attribution = false;
    devin.org_id = "org-f27ebacf926a440d96985a94ab9b66bf";
    hooks = {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = "${pkgs.python3}/bin/python3 ${repo}/config/agents/hooks/repo-env.py session";
              timeout = 5;
            }
          ];
        }
      ];
      PostToolUse = [
        {
          matcher = "^exec$";
          hooks = [
            {
              type = "command";
              command = "${pkgs.python3}/bin/python3 ${repo}/config/agents/hooks/repo-env.py command-not-found";
              timeout = 5;
            }
          ];
        }
      ];
    };
    read_config_from = {
      claude = false;
      cursor = false;
      windsurf = false;
    };
    shell.setup_complete = true;
    show_hints = false;
    theme_auto_detect = "always";
    version = 1;
  };

  jjConf = pkgs.writeText "jj-config" ''
    [user]
    name = "${identity.fullName}"
    email = "${identity.email}"

    [signing]
    behavior = "drop"
    backend = "ssh"
    key = "${homeDirectory}/.ssh/id_ed25519.pub"

    [signing.backends.ssh]
    allowed-signers = "${repo}/config/git/allowed_signers"

    [ui]
    editor = "nvim"
    pager = "less -FRX"
    default-command = "log"
    diff-editor = ":builtin"
    merge-editor = "vimdiff"

    [git]
    sign-on-push = true
    fetch = ["glob:*"]

    [merge-tools.vimdiff]
    program = "nvim"

    [remotes.origin]
    auto-track-bookmarks = 'exact:"main" | exact:"master"'

    [experimental-advance-branches]
    enabled-branches = ["glob:*"]
    disabled-branches = ["glob:push-*"]

    [revset-aliases]
    "stack()" = "reachable(@, mutable())"
    "ready()" = 'stack() & ~empty() & ~description(exact:"")'
    "top()" = "heads(stack())"

    [aliases]
    h = ["hist"]
    restack = ["rebase", "-b", "@", "-o", "trunk()", "--skip-emptied"]
    rs = ["restack"]
    s = ["status"]
    sync = ["util", "exec", "--", "sh", "-c", "jj git fetch && jj restack && jj stack"]
    sy = ["sync"]
    up = ["git", "push", "-c", "ready()"]
    u = ["up"]
    pr = ["util", "exec", "--", "jj-pr"]
    g = ["git"]
    d = ["describe"]
    rb = ["rebase"]
    c = ["commit"]
    cf = ["config"]
    cp = ["duplicate"]
    lg = ["log"]
    t = ["tag"]
    ws = ["workspace"]
  '';

  personalGitConf = pkgs.writeText "git-personal" ''
    [user]
      email = ${identity.email}
  '';

  gitConf = pkgs.writeText "git-wrapper" ''
    [user]
      name = ${identity.fullName}
      email = ${config.barrett.user.gitEmail}
    [safe]
      directory = ${XDG_CACHE_HOME}/nix/tarball-cache-v2
    [include]
      path = ${repo}/config/git/config
    ${lib.concatMapStringsSep "\n" (dir: ''
      [includeIf "gitdir:${dir}"]
        path = ${personalGitConf}
    '') config.barrett.user.personalGitDirs}
    ${config.barrett.user.extraGitConfig}
  '';

  sshConf = pkgs.writeText "ssh-host-config" config.barrett.user.extraSshConfig;

  isLinux = !isDarwin;

  clangCli = pkgs.linkFarm "clang-cli" [
    {
      name = "bin/clang";
      path = "${pkgs.llvmPackages.clang-unwrapped}/bin/clang";
    }
    {
      name = "bin/clang++";
      path = "${pkgs.llvmPackages.clang-unwrapped}/bin/clang++";
    }
  ];

  sessionVariables = {
    inherit
      XDG_CONFIG_HOME
      XDG_DATA_HOME
      XDG_STATE_HOME
      XDG_CACHE_HOME
      ;
    EDITOR = "nvim";
    MANPAGER = "nvim +Man!";
    TERMINAL = "ghostty";
    TERM = "xterm-ghostty";
    TERMINFO = "${XDG_DATA_HOME}/terminfo";
    BROWSER = if isDarwin then "open" else "chromium";
    LESSHISTFILE = "-";
    BARRETT_NIX_CONFIG_DIR = "${repo}/config";
    FZF_DEFAULT_OPTS_FILE = "${XDG_CONFIG_HOME}/fzf/themes/theme";
    FZF_DEFAULT_OPTS = lib.concatStringsSep " " [
      "--bind=ctrl-a:select-all"
      "--bind=ctrl-f:half-page-down"
      "--bind=ctrl-b:half-page-up"
      "--no-scrollbar"
      "--no-info"
    ];
    FZF_DEFAULT_COMMAND = "rg --files --hidden";
    FZF_CTRL_T_COMMAND = "rg --files --hidden";
    FZF_ALT_C_COMMAND = "fd --type d --hidden";

    GIT_CONFIG_GLOBAL = "${XDG_CONFIG_HOME}/git/config";
    WGETRC = "${XDG_CONFIG_HOME}/wgetrc";
    LUAROCKS_CONFIG = "${XDG_CONFIG_HOME}/luarocks/config.lua";
    GRADLE_USER_HOME = "${XDG_CONFIG_HOME}/gradle";
    LIBVIRT_DEFAULT_URI = "qemu:///system";
    MBSYNCRC = "${XDG_CONFIG_HOME}/mbsync/config";
    PARALLEL_HOME = "${XDG_CONFIG_HOME}/parallel";
    PASSWORD_STORE_DIR = "${XDG_DATA_HOME}/pass";
    RIPGREP_CONFIG_PATH = "${XDG_CONFIG_HOME}/rg/config";
    CARGO_HOME = "${XDG_DATA_HOME}/cargo";
    GOPATH = "${XDG_DATA_HOME}/go";
    GOMODCACHE = "${XDG_CACHE_HOME}/go/mod";
    NPM_CONFIG_USERCONFIG = "${XDG_CONFIG_HOME}/npm/npmrc";
    NPM_CONFIG_PREFIX = "${XDG_DATA_HOME}/npm";
    NPM_CONFIG_CACHE = "${XDG_CACHE_HOME}/npm";
    NPM_CONFIG_INIT_MODULE = "${XDG_CONFIG_HOME}/npm/config/npm-init.js";
    NODE_REPL_HISTORY = "${XDG_STATE_HOME}/node_repl_history";
    PNPM_HOME = "${XDG_DATA_HOME}/pnpm";
    PNPM_NO_UPDATE_NOTIFIER = "true";
    PYTHONSTARTUP = "${XDG_CONFIG_HOME}/python/pythonrc";
    PYTHON_HISTORY = "${XDG_STATE_HOME}/python_history";
    PYTHONPYCACHEPREFIX = "${XDG_CACHE_HOME}/python";
    PYTHONUSERBASE = "${XDG_DATA_HOME}/python";
    MYPY_CACHE_DIR = "${XDG_CACHE_HOME}/mypy";
    JUPYTER_CONFIG_DIR = "${XDG_CONFIG_HOME}/jupyter";
    JUPYTER_PLATFORM_DIRS = "1";
    OPAMROOT = "${XDG_DATA_HOME}/opam";
    DOCKER_CONFIG = "${XDG_CONFIG_HOME}/docker";
    PSQL_HISTORY = "${XDG_STATE_HOME}/psql_history";
    SQLITE_HISTORY = "${XDG_STATE_HOME}/sqlite_history";
  }
  // lib.optionalAttrs (!isImc) {
    DEVIN_PERMISSION_MODE = "dangerous";
  };

  activationText = ''
        ${mkDir "${XDG_CONFIG_HOME}/zsh"}
        ${mkDir "${XDG_STATE_HOME}/zsh"}
        ${mkDir "${XDG_CONFIG_HOME}/ghostty"}
        ${mkDir "${XDG_CONFIG_HOME}/fzf"}
        ${mkDir "${XDG_CONFIG_HOME}/fzf/themes"}
        if [ ! -s "${XDG_STATE_HOME}/theme" ]; then
          tmp="$(mktemp)"
          printf '%s\n' midnight > "$tmp"
          install -Dm644 -o ${username} -g ${act.group} "$tmp" "${XDG_STATE_HOME}/theme"
          rm -f "$tmp"
        fi
        ${mkSymlink "${zshInit}" "${XDG_CONFIG_HOME}/zsh/.zshrc"}
        ${mkSymlink "${repo}/config/nvim" "${XDG_CONFIG_HOME}/nvim"}
        ${mkSymlink ghosttyConfig "${XDG_CONFIG_HOME}/ghostty/config"}
        ${mkSymlink "${repo}/config/ghostty/themes" "${XDG_CONFIG_HOME}/ghostty/themes"}
        ${mkSymlink "${fzfThemes}/midnight" "${XDG_CONFIG_HOME}/fzf/themes/midnight"}
        ${mkSymlink "${fzfThemes}/daylight" "${XDG_CONFIG_HOME}/fzf/themes/daylight"}
            ${mkDir "${XDG_CONFIG_HOME}"}
            ${mkDir "${homeDirectory}/.local"}
            ${mkDir "${homeDirectory}/.local/bin"}
            ${mkDir "${XDG_DATA_HOME}"}
            ${mkDir "${XDG_STATE_HOME}"}
            ${mkDir "${XDG_CACHE_HOME}"}
            ${mkDir "${XDG_CONFIG_HOME}/git"}
            ${mkDir "${XDG_CONFIG_HOME}/gh"}
            ${mkDir "${XDG_DATA_HOME}/gh/extensions/gh-stack"}
            ${mkDir "${XDG_CONFIG_HOME}/jj"}
            ${mkDir "${XDG_CONFIG_HOME}/rg"}
            ${mkDir "${XDG_CONFIG_HOME}/fd"}
            ${mkDir "${XDG_CONFIG_HOME}/npm"}
            ${mkDir "${XDG_CONFIG_HOME}/python"}
            ${mkDir "${XDG_CONFIG_HOME}/luarocks"}
            ${mkDir "${XDG_CONFIG_HOME}/github"}
            ${mkDir "${XDG_CONFIG_HOME}/direnv"}
            ${lib.optionalString (!isImc) (mkDir "${XDG_CONFIG_HOME}/devin")}
            ${mkDir clangdConfigDir}
            ${mkDir "${XDG_DATA_HOME}/nvim/site"}
            ${mkPrivateDir "${homeDirectory}/.ssh"}
            ${mkPrivateDir "${homeDirectory}/.ssh/config.d"}
            ${mkPrivateDir "${homeDirectory}/.gnupg"}
            ${mkPrivateDir "${XDG_CONFIG_HOME}/sops"}
            ${mkPrivateDir "${XDG_CONFIG_HOME}/sops/age"}
            ${mkSymlink "${gitConf}" "${XDG_CONFIG_HOME}/git/config"}
            ${mkSymlink "${repo}/config/git/ignore" "${XDG_CONFIG_HOME}/git/ignore"}
            ${mkSymlink "${repo}/config/git/hooks" "${XDG_CONFIG_HOME}/git/hooks"}
            ${mkSymlink "${repo}/config/ssh/config" "${homeDirectory}/.ssh/config"}
            ${mkSymlink "${sshConf}" "${homeDirectory}/.ssh/config.d/host.conf"}
            ${mkSymlink "${repo}/config/gh/config.yaml" "${XDG_CONFIG_HOME}/gh/config.yml"}
            ${mkSymlink "${pkgs.gh-stack}/bin/gh-stack" "${XDG_DATA_HOME}/gh/extensions/gh-stack/gh-stack"}
            ${mkSymlink "${jjConf}" "${XDG_CONFIG_HOME}/jj/config.toml"}
            ${mkSymlink "${repo}/config/rg/config" "${XDG_CONFIG_HOME}/rg/config"}
            ${mkSymlink "${repo}/config/fd/ignore" "${XDG_CONFIG_HOME}/fd/ignore"}
            ${mkSymlink "${repo}/config/python/pythonrc" "${XDG_CONFIG_HOME}/python/pythonrc"}
            ${mkSymlink "${repo}/config/wgetrc" "${XDG_CONFIG_HOME}/wgetrc"}
            ${mkSymlink "${repo}/config/luarocks/config.lua" "${XDG_CONFIG_HOME}/luarocks/config.lua"}
            ${mkSymlink "${repo}/config/github/ruleset.json" "${XDG_CONFIG_HOME}/github/ruleset.json"}
            ${mkSymlink "${repo}/config/direnv/direnvrc" "${XDG_CONFIG_HOME}/direnv/direnvrc"}
            ${mkSymlink "${repo}/config/direnv/config.toml" "${XDG_CONFIG_HOME}/direnv/config.toml"}
            ${lib.optionalString (!isImc) ''
              devinConfigPath="${XDG_CONFIG_HOME}/devin/config.json"
              devinConfigTmp="$(${pkgs.coreutils}/bin/mktemp "${XDG_CONFIG_HOME}/devin/config.json.XXXXXX")"
              trap '${pkgs.coreutils}/bin/rm -f "$devinConfigTmp"' EXIT
              if [ -f "$devinConfigPath" ]; then
                ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$devinConfigPath" "${devinConfig}" > "$devinConfigTmp"
              else
                ${pkgs.coreutils}/bin/cp "${devinConfig}" "$devinConfigTmp"
              fi
              if [ -L "$devinConfigPath" ]; then
                ${runAsUser} ${pkgs.coreutils}/bin/unlink "$devinConfigPath"
              fi
              ${pkgs.coreutils}/bin/install -m 0600 -o ${username} -g ${act.group} "$devinConfigTmp" "$devinConfigPath"
              ${pkgs.coreutils}/bin/rm -f "$devinConfigTmp"
              trap - EXIT
              ${mkSymlink "${repo}/config/agents/AGENTS.md" "${XDG_CONFIG_HOME}/devin/AGENTS.md"}
            ''}
            ${mkSymlink "${repo}/config/clangd/config.yaml" "${clangdConfigDir}/config.yaml"}
            ${mkSymlink "${pkgs.neovim.treesitter}/parser" "${XDG_DATA_HOME}/nvim/site/parser"}
            ${mkSymlink "${pkgs.neovim.treesitter}/queries" "${XDG_DATA_HOME}/nvim/site/queries"}
        ${mkSymlink "${chromiumThemeCss}" "${repo}/config/chromium/extension/theme.css"}
        ${mkSymlink "${chromiumThemeJs}" "${repo}/config/chromium/extension/theme.js"}

    ${readTheme}
    ${mkSymlink "${XDG_CONFIG_HOME}/fzf/themes/$theme" "${XDG_CONFIG_HOME}/fzf/themes/theme"}

    ${lib.concatMapStringsSep "\n            " mkDir agentSkillDirs}
            for skill in ${repo}/config/skills/*/ ${repo}/.devin/skills/*/; do
              [ -f "$skill/SKILL.md" ] || continue
              name="$(basename "$skill")"
              ${lib.concatMapStringsSep "\n              " (
                dir: ''${runAsUser} ${pkgs.coreutils}/bin/ln -sfnT "$skill" "${dir}/$name"''
              ) agentSkillDirs}
            done
            ${mkSymlink "${repo}/.devin/skills/recover/scripts/recover.py" "${homeDirectory}/.local/bin/recover"}

            ${lib.concatMapStringsSep "\n            " (dir: ''
              for link in ${dir}/*; do
                if [ -L "$link" ] && [ ! -e "$link" ]; then
                  ${runAsUser} ${pkgs.coreutils}/bin/rm "$link"
                fi
              done
            '') agentSkillDirs}

  '';

  direnvCachePrune = pkgs.writeShellScript "direnv-cache-prune" ''
    set -euo pipefail

    ${pkgs.direnv}/bin/direnv prune || true

    for root in "$HOME/dev" "$HOME/.config/nix"; do
      [ -d "$root" ] || continue

      ${pkgs.findutils}/bin/find "$root" -maxdepth 3 -type d -name .direnv -prune -print0 \
        | while IFS= read -r -d "" cache; do
            recent_cache=$(${pkgs.findutils}/bin/find "$cache" -mindepth 1 -maxdepth 2 \
              \( -name 'flake-profile*' -o -name 'nix-profile*' -o -path "$cache/flake-inputs/*" \) \
              -mtime -7 -print -quit)
            if [ -n "$recent_cache" ]; then
              continue
            fi

            ${pkgs.coreutils}/bin/rm -f -- "$cache"/flake-profile* "$cache"/nix-profile* "$cache"/*.rc
            if [ -d "$cache/flake-inputs" ]; then
              ${pkgs.findutils}/bin/find "$cache/flake-inputs" -mindepth 1 -delete
              ${pkgs.coreutils}/bin/rmdir "$cache/flake-inputs" 2>/dev/null || true
            fi
            ${pkgs.findutils}/bin/find "$cache" -type d -empty -delete
          done
    done
  '';

in
{
  options.barrett.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "barrett";
    };
    gitEmail = lib.mkOption {
      type = lib.types.str;
      default = identity.email;
      description = "Email git commits are authored with by default on this host.";
    };
    personalGitDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "gitdir patterns that keep the personal identity regardless of gitEmail.";
    };
    extraGitConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Git configuration appended for this host, overriding the shared file.";
    };
    extraSshConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "ssh configuration for this host, included ahead of the shared file.";
    };
    homeDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = (if isDarwin then "/Users/" else "/home/") + config.barrett.user.name;
    };
  };

  options.barrett.workstation.enable = lib.mkEnableOption "Barrett workstation extras";

  options.barrett.workstation.scriptsPath = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    internal = true;
    default = scriptsPath;
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        users.users.${username}.packages =
          (with pkgs; [
            tree
            jq
            wget
            unzip
            gnumake
            just
            file
            uv
            python3
            bash-language-server
            clangCli
            gcc
            gdb
            vscode-langservers-extracted
            prettier
            shfmt
            shellcheck
            nodejs
            tea
            git-lfs
            git-filter-repo
            glab
            gh
            jujutsu
            fzf
            eza
            zoxide
            ripgrep
            fd
            git
            neovim
            openssl
          ])
          ++ lib.optional (!isDarwin) (if hasDisplay then pkgs.ghostty else pkgs.ghostty.terminfo)
          ++ lib.optionals isDarwin (
            with pkgs;
            [
              coreutils
              gnused
              curl
              direnv
            ]
          )
          ++ lib.optionals isLinux [
            pkgs.psmisc
            pkgs.socat
          ]
          ++ agentPackages;

        environment.extraInit = ''
          export __NIX_SET_ENVIRONMENT_SYSTEM="$(readlink /run/current-system)"
          export PATH="${scriptsPath}:${homeDirectory}/.local/bin:$PATH"
          export PATH="${XDG_DATA_HOME}/cargo/bin:${XDG_DATA_HOME}/go/bin:${XDG_DATA_HOME}/pnpm:$PATH"
        '';

        programs.zsh.enable = true;
        programs.zsh.shellInit = ''
          if [ "$__NIX_SET_ENVIRONMENT_SYSTEM" != "$(readlink /run/current-system)" ]; then
            . ${config.system.build.setEnvironment}
          fi

          export ZDOTDIR="$HOME/.config/zsh"
          THEME="$(cat "''${XDG_STATE_HOME:-$HOME/.local/state}/theme" 2>/dev/null)" || THEME="midnight"
          [ -z "$THEME" ] && THEME="midnight"
          export THEME
        '';

        programs.gnupg.agent.enable = true;

      }

      (lib.optionalAttrs isLinux {
        systemd.tmpfiles.rules = [
          "d ${homeDirectory}/dev 0755 ${username} users -"
        ];

        environment.sessionVariables = sessionVariables;

        programs.direnv = {
          enable = true;
          enableZshIntegration = false;
          nix-direnv.enable = true;
          settings.global = {
            hide_env_diff = true;
            log_filter = "^direnv: ((loading|using flake|export )|nix-direnv: Using cached dev shell)";
          };
        };

        programs.gnupg.agent.pinentryPackage = pkgs.pinentry-curses;

        system.activationScripts.barrettWorkstationConfig = {
          deps = lib.optional config.barrett.ui.enable "barrettUiConfig";
          text = activationText;
        };

        systemd.user.services.direnv-cache-prune = {
          description = "Prune stale direnv and nix-direnv caches";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = direnvCachePrune;
          };
        };

        systemd.user.timers.direnv-cache-prune = {
          description = "Auto-prune stale direnv caches";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      })

      (lib.optionalAttrs isDarwin {
        environment.variables = sessionVariables;

        environment.extraInit = ''
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$TMPDIR}"
        '';

        system.activationScripts.postActivation.text = activationText;

        launchd.user.agents = {
          direnv-cache-prune = {
            script = "exec ${direnvCachePrune}";
            serviceConfig.StartCalendarInterval = [
              {
                Hour = 3;
                Minute = 30;
              }
            ];
          };

          wallpaper-gen = {
            script = ''
              [ -x "${scriptsPath}/ctl" ] || exit 0

              export PATH="${scriptsPath}:/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/nix/var/nix/profiles/default/bin:$PATH"
              export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$TMPDIR}"

              exec "${scriptsPath}/ctl" wallpaper gen
            '';
            serviceConfig.RunAtLoad = true;
          };
        };
      })
    ]
  );
}
