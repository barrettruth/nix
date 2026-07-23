{
  config,
  pkgs,
  lib,
  identity,
  themeGenerators ? null,
  palettes ? null,
  whisperPkgs ? pkgs,
  ...
}:
let
  cfg = config.barrett.workstation;
  ui = config.barrett.ui;
  user = config.barrett.user;
  username = user.name;
  homeDirectory = user.homeDirectory;
  XDG_CONFIG_HOME = "${homeDirectory}/.config";
  XDG_DATA_HOME = "${homeDirectory}/.local/share";
  XDG_STATE_HOME = "${homeDirectory}/.local/state";
  XDG_CACHE_HOME = "${homeDirectory}/.cache";
  repo = "${XDG_CONFIG_HOME}/nix";

  runUser = "${pkgs.util-linux}/bin/runuser -u ${username} --";

  mkSymlink = target: link: ''
    ${runUser} ${pkgs.coreutils}/bin/ln -sfnT "${target}" "${link}"
  '';

  mkDirMode = mode: dir: ''
    install -d -m ${mode} -o ${username} -g users "${dir}"
  '';

  mkDir = mkDirMode "0755";

  mkPrivateDir = mkDirMode "0700";

  readTheme = ''
    theme="$(cat "${XDG_STATE_HOME}/theme" 2>/dev/null)" || theme="midnight"
    [ -z "$theme" ] && theme="midnight"
  '';

  agentPackages = with pkgs; [
    codex
    devin-cli
  ];

  codexRuntimePackages = lib.optionals (builtins.elem "codex" (map lib.getName agentPackages)) [
    pkgs.google-cloud-sdk
    pkgs.google-workspace-cli
    pkgs.google-workspace-guard
    pkgs.mgrep
  ];

  pytest-language-server = pkgs.callPackage ../../../pkgs/pytest-language-server.nix { };
  whisper = whisperPkgs.whisper-cpp.override { cudaSupport = ui.gpu != "generic"; };
  gpgCacheTtlSeconds = 2147483647;

  jjConf = pkgs.writeText "jj-config" ''
    [user]
    name = "${identity.fullName}"
    email = "${identity.email}"

    [signing]
    behavior = "own"
    backend = "gpg"
    key = "${identity.gpgKey}"

    [ui]
    editor = "nvim"
    pager = "less -FRX"
    default-command = "log"
    diff-editor = ":builtin"
    merge-editor = "vimdiff"

    [git]
    sign-on-push = true

    [merge-tools.vimdiff]
    program = "nvim"
  '';

  gitConf = pkgs.writeText "git-wrapper" ''
    [user]
    	name = ${identity.fullName}
    	email = ${identity.email}
    	signingKey = ${identity.gpgKey}
    [safe]
    	directory = ${XDG_CACHE_HOME}/nix/tarball-cache-v2
    [include]
    	path = ${repo}/config/git/config
  '';

  mimeappsList = pkgs.writeText "mimeapps-workstation.list" ''
    [Default Applications]
    x-scheme-handler/http=chromium-browser.desktop
    x-scheme-handler/https=chromium-browser.desktop
    text/html=chromium-browser.desktop
    text/plain=nvim.desktop
    application/pdf=org.pwmt.zathura.desktop
  '';

  awsConf = pkgs.writeText "aws-config" ''
    [default]
    [profile barrett]
    region = us-east-2
    output = json
  '';

  zathuraThemes = pkgs.runCommand "zathura-theme-files" { } ''
    mkdir -p $out

    cat > $out/midnight << 'ZATHURAMIDNIGHT'
    ${themeGenerators.mkZathuraTheme palettes.midnight}
    ZATHURAMIDNIGHT

    cat > $out/daylight << 'ZATHURADAYLIGHT'
    ${themeGenerators.mkZathuraTheme palettes.daylight}
    ZATHURADAYLIGHT
  '';
in
{
  options.barrett.workstation.enable = lib.mkEnableOption "Barrett workstation extras";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = palettes != null && themeGenerators != null;
        message = "barrett.workstation.enable requires palettes and themeGenerators module arguments";
      }
    ];

    barrett.ui.enable = lib.mkDefault true;
    barrett.ui.idle.suspend = lib.mkDefault true;
    barrett.ui.useHomeRepo = lib.mkDefault true;

    systemd.tmpfiles.rules = [
      "d ${homeDirectory}/dev 0755 ${username} users -"
    ];

    users.users.${username}.packages =
      (with pkgs; [
        awscli2
        tree
        typos
        jq
        curl
        wget
        unzip
        gnumake
        just
        gcc
        file
        ffmpeg
        poppler-utils
        librsvg
        imagemagick
        luarocks
        delta-cli
        rustup
        uv
        python3
        bash-language-server
        basedpyright
        clang-tools
        emmet-language-server
        lua-language-server
        mdx-language-server
        pandoc
        pytest-language-server
        ruff
        tinymist
        vtsls
        vscode-langservers-extracted
        nixd
        black
        buf
        cbfmt
        cmake-format
        isort
        prettierd
        shfmt
        stylua
        checkmake
        cpplint
        eslint_d
        hadolint
        mypy
        ty
        selene
        shellcheck
        deadnix
        statix
        nodejs
        bun
        lua
        tree-sitter
        ts_query_ls
        nixfmt-tree
        tea
        git-lfs
        gemini-cli
        typst
        typstyle
        glab
        psmisc
        brightnessctl
        glib.bin
        direnv
        nix-direnv
        gh
        jujutsu
        gnupg
        whisper
        (mpv.override { youtubeSupport = false; })
        # signal-desktop
        # telegram-desktop
        # element-desktop
        zathura
        biber
        (texlive.combine {
          inherit (texlive)
            scheme-small
            latexindent
            latexmk
            lastpage
            pgf
            collection-fontsrecommended
            ;
        })
      ])
      ++ agentPackages
      ++ codexRuntimePackages;

    environment.sessionVariables = {
      WGETRC = "${XDG_CONFIG_HOME}/wgetrc";
      LUAROCKS_CONFIG = "${XDG_CONFIG_HOME}/luarocks/config.lua";
      GRADLE_USER_HOME = "${XDG_CONFIG_HOME}/gradle";
      LIBVIRT_DEFAULT_URI = "qemu:///system";
      MBSYNCRC = "${XDG_CONFIG_HOME}/mbsync/config";
      PARALLEL_HOME = "${XDG_CONFIG_HOME}/parallel";
      PASSWORD_STORE_DIR = "${XDG_DATA_HOME}/pass";
      PRETTIERD_CONFIG_HOME = "${XDG_STATE_HOME}/prettierd";
      RIPGREP_CONFIG_PATH = "${XDG_CONFIG_HOME}/rg/config";
      CARGO_HOME = "${XDG_DATA_HOME}/cargo";
      RUSTUP_HOME = "${XDG_DATA_HOME}/rustup";
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
      CODEX_HOME = "${XDG_CONFIG_HOME}/codex";
      DEVIN_PERMISSION_MODE = "dangerous";
      AWS_SHARED_CREDENTIALS_FILE = "${XDG_CONFIG_HOME}/aws/credentials";
      AWS_CONFIG_FILE = "${XDG_CONFIG_HOME}/aws/config";
      BOTO_CONFIG = "${XDG_CONFIG_HOME}/boto/config";
      PSQL_HISTORY = "${XDG_STATE_HOME}/psql_history";
      SQLITE_HISTORY = "${XDG_STATE_HOME}/sqlite_history";
      TEXMFHOME = "${XDG_DATA_HOME}/texmf";
      TEXMFVAR = "${XDG_CACHE_HOME}/texlive/texmf-var";
      TEXMFCONFIG = "${XDG_CONFIG_HOME}/texlive/texmf-config";
      INPUTRC = "${XDG_CONFIG_HOME}/readline/inputrc";
    };

    environment.extraInit = ''
      export PATH="${XDG_DATA_HOME}/cargo/bin:${XDG_DATA_HOME}/go/bin:${XDG_DATA_HOME}/pnpm:$PATH"
      if [ -z "''${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "${XDG_CONFIG_HOME}/gcloud/application_default_credentials.json" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="${XDG_CONFIG_HOME}/gcloud/application_default_credentials.json"
      fi
    '';

    programs.gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
      settings = {
        default-cache-ttl = gpgCacheTtlSeconds;
        default-cache-ttl-ssh = gpgCacheTtlSeconds;
        max-cache-ttl = gpgCacheTtlSeconds;
        max-cache-ttl-ssh = gpgCacheTtlSeconds;
      };
    };

    systemd.user.services.nix-flake-update = {
      description = "Update nix flake inputs";
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = "%h/.config/nix";
        ExecStart = "${pkgs.nix}/bin/nix flake update";
      };
    };

    systemd.user.timers.nix-flake-update = {
      description = "Auto-update nix flake inputs";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.user.services.direnv-cache-prune = {
      description = "Prune stale direnv and nix-direnv caches";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "direnv-cache-prune" ''
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

    systemd.user.services.whisper-dictation = {
      description = "Whisper dictation server";
      unitConfig.ConditionPathExists = "${XDG_DATA_HOME}/whisper-models/ggml-large-v3-turbo-q5_0.bin";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${whisper}/bin/whisper-server --model ${XDG_DATA_HOME}/whisper-models/ggml-large-v3-turbo-q5_0.bin --host 127.0.0.1 --port 8178";
      };
    };

    system.activationScripts.barrettWorkstationConfig = {
      deps = [ "barrettUiConfig" ];
      text = ''
        ${mkDir "${XDG_CONFIG_HOME}"}
        ${mkDir "${XDG_DATA_HOME}"}
        ${mkDir "${XDG_STATE_HOME}"}
        ${mkDir "${XDG_CACHE_HOME}"}
        ${mkDir "${XDG_CONFIG_HOME}/git"}
        ${mkDir "${XDG_CONFIG_HOME}/gh"}
        ${mkDir "${XDG_CONFIG_HOME}/jj"}
        ${mkDir "${XDG_CONFIG_HOME}/rg"}
        ${mkDir "${XDG_CONFIG_HOME}/fd"}
        ${mkDir "${XDG_CONFIG_HOME}/npm"}
        ${mkDir "${XDG_CONFIG_HOME}/python"}
        ${mkDir "${XDG_CONFIG_HOME}/luarocks"}
        ${mkDir "${XDG_CONFIG_HOME}/github"}
        ${mkDir "${XDG_CONFIG_HOME}/direnv"}
        ${mkDir "${XDG_CONFIG_HOME}/devin"}
        ${mkDir "${XDG_CONFIG_HOME}/codex"}
        ${mkDir "${XDG_CONFIG_HOME}/clangd"}
        ${mkDir "${XDG_CONFIG_HOME}/zathura"}
        ${mkDir "${XDG_CONFIG_HOME}/zathura/themes"}
        ${mkPrivateDir "${homeDirectory}/.ssh"}
        ${mkPrivateDir "${homeDirectory}/.gnupg"}
        if [ -L "${homeDirectory}/.codex" ]; then
          ${runUser} ${pkgs.coreutils}/bin/rm -f "${homeDirectory}/.codex"
        fi

        ${mkSymlink "${mimeappsList}" "${XDG_CONFIG_HOME}/mimeapps.list"}
        ${mkSymlink "${repo}/config/electron-flags.conf" "${XDG_CONFIG_HOME}/electron-flags.conf"}
        ${mkSymlink "${gitConf}" "${XDG_CONFIG_HOME}/git/config"}
        ${mkSymlink "${repo}/config/git/ignore" "${XDG_CONFIG_HOME}/git/ignore"}
        ${mkSymlink "${repo}/config/git/hooks" "${XDG_CONFIG_HOME}/git/hooks"}
        ${mkSymlink "${repo}/config/ssh/config" "${homeDirectory}/.ssh/config"}
        ${mkSymlink "${repo}/config/gh/config.yaml" "${XDG_CONFIG_HOME}/gh/config.yml"}
        ${mkSymlink "${jjConf}" "${XDG_CONFIG_HOME}/jj/config.toml"}
        ${mkSymlink "${repo}/config/rg/config" "${XDG_CONFIG_HOME}/rg/config"}
        ${mkSymlink "${repo}/config/fd/ignore" "${XDG_CONFIG_HOME}/fd/ignore"}
        ${mkSymlink "${repo}/config/python/pythonrc" "${XDG_CONFIG_HOME}/python/pythonrc"}
        ${mkSymlink "${repo}/config/wgetrc" "${XDG_CONFIG_HOME}/wgetrc"}
        ${mkSymlink "${repo}/config/luarocks/config.lua" "${XDG_CONFIG_HOME}/luarocks/config.lua"}
        ${mkSymlink "${repo}/config/github/ruleset.json" "${XDG_CONFIG_HOME}/github/ruleset.json"}
        ${mkSymlink "${repo}/config/direnv/direnvrc" "${XDG_CONFIG_HOME}/direnv/direnvrc"}
        ${mkSymlink "${repo}/config/direnv/config.toml" "${XDG_CONFIG_HOME}/direnv/config.toml"}
        ${mkSymlink "${repo}/config/devin/config.json" "${XDG_CONFIG_HOME}/devin/config.json"}
        ${mkSymlink "${repo}/config/devin/AGENTS.md" "${XDG_CONFIG_HOME}/devin/AGENTS.md"}
        ${mkSymlink "${repo}/config/codex/config.toml" "${XDG_CONFIG_HOME}/codex/config.toml"}
        ${mkSymlink "${repo}/config/codex/AGENTS.md" "${XDG_CONFIG_HOME}/codex/AGENTS.md"}
        ${mkSymlink "${repo}/config/clangd/config.yaml" "${XDG_CONFIG_HOME}/clangd/config.yaml"}
        ${mkSymlink "${zathuraThemes}/midnight" "${XDG_CONFIG_HOME}/zathura/themes/midnight"}
        ${mkSymlink "${zathuraThemes}/daylight" "${XDG_CONFIG_HOME}/zathura/themes/daylight"}
        ${mkSymlink "${repo}/config/zathura/zathurarc" "${XDG_CONFIG_HOME}/zathura/zathurarc"}

        ${readTheme}
        ${mkSymlink "${XDG_CONFIG_HOME}/zathura/themes/$theme" "${XDG_CONFIG_HOME}/zathura/theme"}

        ${mkDir "${XDG_CONFIG_HOME}/latexmk"}
        ${mkSymlink "${repo}/config/latexmk/latexmkrc" "${XDG_CONFIG_HOME}/latexmk/latexmkrc"}

        ${mkDir "${XDG_CONFIG_HOME}/codex/skills"}
        if [ -L "${XDG_CONFIG_HOME}/devin/skills" ]; then
          rm -f "${XDG_CONFIG_HOME}/devin/skills"
        fi
        ${mkDir "${XDG_CONFIG_HOME}/devin/skills"}
        for skill in ${repo}/config/skills/*/ ${repo}/.devin/skills/*/; do
          [ -f "$skill/SKILL.md" ] || continue
          name="$(basename "$skill")"
          for agentdir in "${XDG_CONFIG_HOME}/codex/skills" "${XDG_CONFIG_HOME}/devin/skills"; do
            ${runUser} ${pkgs.coreutils}/bin/ln -sfnT "$skill" "$agentdir/$name"
          done
        done

        ${mkDir "${XDG_CONFIG_HOME}/aws"}
        ${mkSymlink "${awsConf}" "${XDG_CONFIG_HOME}/aws/config"}
        ${mkDir "${XDG_DATA_HOME}/whisper-models"}

        for link in ${homeDirectory}/.nix-profile ${homeDirectory}/.nix-defexpr; do
          [ -L "$link" ] && [ ! -e "$link" ] && ${runUser} ${pkgs.coreutils}/bin/rm "$link"
        done

        if [ "$(readlink "${XDG_DATA_HOME}/fonts" 2>/dev/null || true)" = "${repo}/fonts" ]; then
          ${runUser} ${pkgs.coreutils}/bin/rm "${XDG_DATA_HOME}/fonts"
        fi
      '';
    };
  };
}
