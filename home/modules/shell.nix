{
  pkgs,
  lib,
  config,
  hostConfig,
  ...
}:

let
  repoDir = "${config.home.homeDirectory}/.config/nix";

  ripgrep = config.programs.ripgrep.enable;

  claude = true;
  rust = true;
  go = true;
  node = true;
  python = true;
  ocaml = true;
  docker = true;
  aws = true;
  psql = true;
  tex = true;
  sqlite = true;
in
{
  home.packages =
    with pkgs;
    [
      awscli2
      pure-prompt
      tree
      jq
      curl
      wget
      unzip
      tesseract
      gnumake
      gcc
      file
      ffmpeg
      poppler-utils
      librsvg
      imagemagick
      graphite-cli
    ]
    ++ lib.optionals hostConfig.isLinux [ xclip ]
    ++ lib.optionals rust [ rustup ]
    ++ lib.optionals claude [ claude-code ];

  home.sessionVariables = lib.mkMerge [
    {
      FZF_DEFAULT_OPTS_FILE = "${config.xdg.configHome}/fzf/themes/theme";
      LESSHISTFILE = "-";
      WGETRC = "${config.xdg.configHome}/wgetrc";
      LUAROCKS_CONFIG = "${config.xdg.configHome}/luarocks/config.lua";
      GRADLE_USER_HOME = "${config.xdg.configHome}/gradle";
      LIBVIRT_DEFAULT_URI = "qemu:///system";
      MBSYNCRC = "${config.xdg.configHome}/mbsync/config";
      PARALLEL_HOME = "${config.xdg.configHome}/parallel";
      PASSWORD_STORE_DIR = "${config.xdg.dataHome}/pass";
      PRETTIERD_CONFIG_HOME = "${config.xdg.stateHome}/prettierd";
    }
    (lib.mkIf ripgrep {
      RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/rg/config";
    })
    (lib.mkIf rust {
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    })
    (lib.mkIf go {
      GOPATH = "${config.xdg.dataHome}/go";
      GOMODCACHE = "${config.xdg.cacheHome}/go/mod";
    })
    (lib.mkIf node {
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";
      NODE_REPL_HISTORY = "${config.xdg.stateHome}/node_repl_history";
      PNPM_HOME = "${config.xdg.dataHome}/pnpm";
      PNPM_NO_UPDATE_NOTIFIER = "true";
    })
    (lib.mkIf python {
      PYTHONSTARTUP = "${config.xdg.configHome}/python/pythonrc";
      PYTHON_HISTORY = "${config.xdg.stateHome}/python_history";
      PYTHONPYCACHEPREFIX = "${config.xdg.cacheHome}/python";
      PYTHONUSERBASE = "${config.xdg.dataHome}/python";
      MYPY_CACHE_DIR = "${config.xdg.cacheHome}/mypy";
      JUPYTER_CONFIG_DIR = "${config.xdg.configHome}/jupyter";
      JUPYTER_PLATFORM_DIRS = "1";
    })
    (lib.mkIf ocaml {
      OPAMROOT = "${config.xdg.dataHome}/opam";
    })
    (lib.mkIf docker {
      DOCKER_CONFIG = "${config.xdg.configHome}/docker";
    })
    (lib.mkIf aws {
      AWS_SHARED_CREDENTIALS_FILE = "${config.xdg.configHome}/aws/credentials";
      AWS_CONFIG_FILE = "${config.xdg.configHome}/aws/config";
      BOTO_CONFIG = "${config.xdg.configHome}/boto/config";
    })
    (lib.mkIf psql {
      PSQL_HISTORY = "${config.xdg.stateHome}/psql_history";
    })
    (lib.mkIf sqlite {
      SQLITE_HISTORY = "${config.xdg.stateHome}/sqlite_history";
    })
    (lib.mkIf tex {
      TEXMFHOME = "${config.xdg.dataHome}/texmf";
      TEXMFVAR = "${config.xdg.cacheHome}/texlive/texmf-var";
      TEXMFCONFIG = "${config.xdg.configHome}/texlive/texmf-config";
    })
    (lib.mkIf claude {
      CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
    })
  ];

  home.sessionPath = lib.mkMerge [
    [ "${config.home.homeDirectory}/.local/bin" ]
    (lib.mkIf rust [ "${config.xdg.dataHome}/cargo/bin" ])
    (lib.mkIf go [ "${config.xdg.dataHome}/go/bin" ])
    (lib.mkIf node [ "${config.xdg.dataHome}/pnpm" ])
  ];

  xdg.configFile."aws/config" = lib.mkIf aws {
    text = ''
      [default]
      [profile barrett]
      region = us-east-2
      output = json
    '';
  };

  xdg.configFile."npm/npmrc" = lib.mkIf node {
    text = ''
      prefix=''${XDG_DATA_HOME}/npm
      cache=''${XDG_CACHE_HOME}/npm
      init-module=''${XDG_CONFIG_HOME}/npm/config/npm-init.js
    '';
  };

  xdg.configFile."python/pythonrc" = lib.mkIf python {
    text = ''
      import atexit
      import os
      import readline

      history = os.path.join(os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')), 'python_history')

      try:
          readline.read_history_file(history)
      except OSError:
          pass

      def write_history():
          try:
              readline.write_history_file(history)
          except OSError:
              pass

      atexit.register(write_history)
    '';
  };

  xdg.configFile."rg/config" = lib.mkIf ripgrep {
    text = ''
      --column
      --no-heading
      --smart-case
      --no-follow
      --glob=!pnpm-lock.yaml
      --glob=!*.json
      --glob=!venv/
      --glob=!pyenv/
      --ignore-file=${config.xdg.configHome}/git/ignore
      --no-messages
      --color=auto
      --colors=line:style:nobold
      --colors=line:fg:242
      --colors=match:fg:green
      --colors=match:style:bold
      --colors=path:fg:blue
    '';
  };

  xdg.configFile."wgetrc".text = ''
    hsts_file = ${config.xdg.stateHome}/wget-hsts
  '';

  xdg.configFile."luarocks/config.lua".text = ''
    rocks_trees = {
      { name = "user", root = (os_getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/luarocks" };
      { name = "system", root = "/usr" };
    }
  '';

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    completionInit = "";

    profileExtra = lib.mkIf hostConfig.isLinux ''
      [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ] && start-hyprland
    '';

    history = {
      path = "${config.xdg.stateHome}/zsh_history";
      size = 2000;
      save = 2000;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;
      append = true;
    };

    shellAliases = {
      ls = "eza";
      l = "ls --color=auto --group-directories-first";
      ll = "l -alF";
      la = "ll -R";
      g = "git";
      nv = "nvim";
    };

    syntaxHighlighting.enable = true;

    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
    };

    initContent = ''
      fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")
      source "$XDG_CONFIG_HOME/nix/config/zsh/zshrc"
    '';
  };

  home.activation.removeZshenvBridge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    [ -L "$HOME/.zshenv" ] && rm "$HOME/.zshenv" || true
  '';

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "rg --files --hidden";
    defaultOptions = [
      "--bind=ctrl-a:select-all"
      "--bind=ctrl-f:half-page-down"
      "--bind=ctrl-b:half-page-up"
      "--no-scrollbar"
      "--no-info"
    ];
    changeDirWidgetCommand = "fd --type d --hidden";
    fileWidgetCommand = "rg --files --hidden";
    historyWidgetOptions = [ "--reverse" ];
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = false;
    git = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config.global = {
      hide_env_diff = true;
    };
    stdlib = ''
      layout_uv() {
        if [[ ! -d .venv ]]; then
          uv venv
        fi
        . .venv/bin/activate
      }
    '';
  };

  programs.ripgrep.enable = true;

  programs.fd = {
    enable = true;
    hidden = true;
    ignores = [
      ".git/"
      "node_modules/"
      "target/"
      "venv/"
    ];
  };

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    sensibleOnTop = false;

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-dir '${config.xdg.stateHome}/tmux/resurrect'
          set -g @resurrect-capture-pane-contents on
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
    ];

    extraConfig = ''
      source "$XDG_CONFIG_HOME/nix/config/tmux/tmux.conf"
    '';
  };

  xdg.configFile."claude/settings.json" = lib.mkIf claude {
    text = builtins.toJSON {
      permissions.defaultMode = "acceptEdits";
      network_access = true;
      allowed_domains = [
        "github.com"
        "raw.githubusercontent.com"
        "api.github.com"
      ];
      tools.web_fetch = true;
    };
  };

  xdg.configFile."claude/CLAUDE.md" = lib.mkIf claude {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/claude/CLAUDE.md";
  };

  xdg.configFile."claude/rules" = lib.mkIf claude {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/claude/rules";
  };

  xdg.configFile."claude/skills" = lib.mkIf claude {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/claude/skills";
  };

  xdg.configFile."tmux/themes/midnight.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/tmux/themes/midnight.conf";
  xdg.configFile."tmux/themes/daylight.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/tmux/themes/daylight.conf";
}
