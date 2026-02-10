{
  pkgs,
  lib,
  config,
  ...
}:

let
  c = config.colors;
  isNixOS = builtins.pathExists /etc/NIXOS;

  ripgrep = config.programs.ripgrep.enable;

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
  home.packages = with pkgs; [
    awscli2
    pure-prompt
    xclip
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
  ];

  home.sessionVariables = {
    LESSHISTFILE = "-";
    GRADLE_USER_HOME = "${config.xdg.configHome}/gradle";
    LIBVIRT_DEFAULT_URI = "qemu:///system";
    MBSYNCRC = "${config.xdg.configHome}/mbsync/config";
    PARALLEL_HOME = "${config.xdg.configHome}/parallel";
    PASSWORD_STORE_DIR = "${config.xdg.dataHome}/pass";
    PRETTIERD_CONFIG_HOME = "${config.xdg.stateHome}/prettierd";
  }
  // lib.optionalAttrs ripgrep {
    RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/rg/config";
  }
  // lib.optionalAttrs rust {
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
  }
  // lib.optionalAttrs go {
    GOPATH = "${config.xdg.dataHome}/go";
    GOMODCACHE = "${config.xdg.cacheHome}/go/mod";
  }
  // lib.optionalAttrs node {
    NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";
    NODE_REPL_HISTORY = "${config.xdg.stateHome}/node_repl_history";
    PNPM_HOME = "${config.xdg.dataHome}/pnpm";
    PNPM_NO_UPDATE_NOTIFIER = "true";
  }
  // lib.optionalAttrs python {
    PYTHONSTARTUP = "${config.xdg.configHome}/python/pythonrc";
    PYTHON_HISTORY = "${config.xdg.stateHome}/python_history";
    PYTHONPYCACHEPREFIX = "${config.xdg.cacheHome}/python";
    PYTHONUSERBASE = "${config.xdg.dataHome}/python";
    MYPY_CACHE_DIR = "${config.xdg.cacheHome}/mypy";
    JUPYTER_CONFIG_DIR = "${config.xdg.configHome}/jupyter";
    JUPYTER_PLATFORM_DIRS = "1";
  }
  // lib.optionalAttrs ocaml {
    OPAMROOT = "${config.xdg.dataHome}/opam";
  }
  // lib.optionalAttrs docker {
    DOCKER_CONFIG = "${config.xdg.configHome}/docker";
  }
  // lib.optionalAttrs aws {
    AWS_SHARED_CREDENTIALS_FILE = "${config.xdg.configHome}/aws/credentials";
    AWS_CONFIG_FILE = "${config.xdg.configHome}/aws/config";
    BOTO_CONFIG = "${config.xdg.configHome}/boto/config";
  }
  // lib.optionalAttrs psql {
    PSQL_HISTORY = "${config.xdg.stateHome}/psql_history";
  }
  // lib.optionalAttrs sqlite {
    SQLITE_HISTORY = "${config.xdg.stateHome}/sqlite_history";
  }
  // lib.optionalAttrs tex {
    TEXMFHOME = "${config.xdg.dataHome}/texmf";
    TEXMFVAR = "${config.xdg.cacheHome}/texlive/texmf-var";
    TEXMFCONFIG = "${config.xdg.configHome}/texlive/texmf-config";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.local/bin/scripts"
  ]
  ++ lib.optionals rust [ "${config.xdg.dataHome}/cargo/bin" ]
  ++ lib.optionals go [ "${config.xdg.dataHome}/go/bin" ]
  ++ lib.optionals node [ "${config.xdg.dataHome}/pnpm" ];

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

  home.file.".zshenv".text = ''
    export THEME="${config.theme}"
  '';

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

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
      pe = "printenv";
    };

    syntaxHighlighting.enable = true;

    autosuggestion = {
      enable = true;
      strategy = [ "history" "completion" ];
    };

    completionInit = ''
      autoload -U compinit && compinit -d "$XDG_STATE_HOME/zcompdump" -u
      zmodload zsh/complist
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-za-z}'
    '';

    initContent = ''
      export GPG_TTY=$(tty)
      export THEME="''${THEME:-${config.theme}}"

      setopt auto_cd
      unsetopt beep notify
      unset completealiases

      bindkey -v
      bindkey '^[[3~' delete-char
      bindkey '^P' up-line-or-history
      bindkey '^N' down-line-or-history
      bindkey '^J' backward-char
      bindkey '^K' forward-char

      export PURE_PROMPT_SYMBOL=">"
      export PURE_PROMPT_VICMD_SYMBOL="<"
      export PURE_GIT_UP_ARROW="^"
      export PURE_GIT_DOWN_ARROW="v"
      export PURE_GIT_STASH_SYMBOL="="
      export PURE_CMD_MAX_EXEC_TIME=5
      export PURE_GIT_PULL=0
      export PURE_GIT_UNTRACKED_DIRTY=1
      zstyle ':prompt:pure:git:stash' show yes

      fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")
      autoload -Uz promptinit && promptinit
      prompt pure

      autoload -Uz add-zle-hook-widget
      function _cursor_shape() {
        case $KEYMAP in
          vicmd) echo -ne '\e[2 q' ;;
          viins|main) echo -ne '\e[6 q' ;;
        esac
      }
      function _cursor_init() { echo -ne '\e[6 q'; }
      add-zle-hook-widget zle-keymap-select _cursor_shape
      add-zle-hook-widget zle-line-init _cursor_init

      export FZF_COMPLETION_TRIGGER=\;
      export FZF_TMUX=1

      fzf-config-widget() {
          file="$(fd --type file --hidden . ~/.config | sed "s|$HOME|~|g" | fzf)"
          [ -n "$file" ] || { zle reset-prompt; return; }
          file="''${file/#\~/$HOME}"
          BUFFER="nvim $file"
          zle accept-line
      }
      zle -N fzf-config-widget
      bindkey '^E' fzf-config-widget

    ''
    + lib.optionalString ocaml ''
      [[ ! -r "$OPAMROOT/opam-init/init.zsh" ]] || source "$OPAMROOT/opam-init/init.zsh" > /dev/null 2> /dev/null
    '';
  };

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
      "--color=fg:${c.fg},bg:${c.bg},hl:${c.accent}"
      "--color=fg+:${c.fg},bg+:${c.bgAlt},hl+:${c.accent}"
      "--color=info:${c.green},prompt:${c.accent},pointer:${c.fg},marker:${c.green},spinner:${c.fg}"
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
    stdlib = ''
      layout_uv() {
        if [[ ! -d .venv ]]; then
          uv venv
        fi
        source .venv/bin/activate
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
    shortcut = "x";
    keyMode = "vi";
    mouse = true;
    escapeTime = 0;
    historyLimit = 50000;
    baseIndex = 1;
    aggressiveResize = true;
    focusEvents = true;
    sensibleOnTop = false;

    plugins = with pkgs.tmuxPlugins; [
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
    ];

    extraConfig = ''
      set -g prefix M-x
      unbind C-b
      bind M-x send

      set -g default-terminal "$TERM"
      set -g default-shell "$SHELL"

      set -g renumber-windows on
      setw -g automatic-rename off
      set -g pane-base-index 1

      set -g status-position bottom
      set -g status-interval 5
      set -g @c ','
      set-hook -g session-created 'run "mux bar"'
      set-hook -g session-closed 'run "mux bar"'
      set-hook -g client-session-changed 'run "mux bar"'
      set-hook -g pane-mode-changed 'refresh-client -S'

      set -g status-bg '${c.bg}'
      set -g status-fg '${c.fg}'
      set -g window-status-style fg='${c.fg}'
      set -g window-status-current-style fg='${c.fg}'
      set -g window-status-bell-style fg='${c.bellFg}',bg='${c.bg}',bold
      set -g window-status-activity-style fg='${c.activityFg}',bg='${c.bg}',bold
      set -g pane-border-style fg='${c.border}'
      set -g pane-active-border-style fg='${c.fg}'

      set -as terminal-features ",$TERM:RGB"
      set -as terminal-overrides ",*:U8=1"
      set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
      set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

      unbind Left; bind h selectp -L
      unbind Down; bind j selectp -D
      unbind Up; bind k selectp -U
      unbind Right; bind l selectp -R

      unbind :; bind : display-popup -E 'mux cmd'
      unbind s; bind s display-popup -E 'mux pick-session'
      unbind w; bind w display-popup -E 'mux pick-window'
      unbind p; bind p display-popup -E 'mux pick-pane'

      bind -r Left resizep -L 5
      bind -r Right resizep -R 5
      bind -r Up resizep -U 5
      bind -r Down resizep -D 5

      unbind c; bind c neww -c '#{pane_current_path}'
      unbind \'; bind \' splitw -hc '#{pane_current_path}'
      unbind \-; bind \- splitw -vc '#{pane_current_path}'

      unbind y; bind y if -F '#{pane_in_mode}' 'send q' 'copy-mode'
      unbind /; bind / if -F '#{pane_in_mode}' 'send q' 'copy-mode \; send /'
      unbind ?; bind ? if -F '#{pane_in_mode}' 'send q' 'copy-mode \; send ?'

      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'test -n "$WAYLAND_DISPLAY" && wl-copy || xclip -in -sel c'

      unbind b; bind b set status\; refresh -S
      unbind m; bind m set -g mouse\; run 'mux bar'\; refresh -S

      unbind ^; bind ^ last-window

      unbind e; bind e neww -n 'tmux.conf' "sh -c 'nvim $XDG_CONFIG_HOME/tmux/tmux.conf; tmux source $XDG_CONFIG_HOME/tmux/tmux.conf'"

      unbind H; bind H run 'mux switch 0'\; refresh -S
      unbind J; bind J run 'mux switch 1'\; refresh -S
      unbind K; bind K run 'mux switch 2'\; refresh -S
      unbind L; bind L run 'mux switch 3'\; refresh -S
      unbind \$; bind \$ run 'mux switch 4'\; refresh -S

      unbind Tab; bind Tab switchc -l

      set-hook -g client-light-theme 'source ${config.xdg.configHome}/tmux/themes/daylight.conf'
      set-hook -g client-dark-theme  'source ${config.xdg.configHome}/tmux/themes/midnight.conf'

      unbind A; bind A run 'mux ai'
      unbind C; bind C run 'mux code'
      unbind R; bind R run 'mux run'
      unbind T; bind T run 'mux term'
      unbind G; bind G run 'mux git'
      unbind M; bind M run 'mux misc'

      set -g lock-after-time 300
      set -g lock-command "pipes -p 2"

      set -g @resurrect-capture-pane-contents on
    '';
  };

  xdg.configFile."tmux/themes/midnight.conf".text = ''
    set -g status-bg '#121212'
    set -g status-fg '#e0e0e0'
    set -g window-status-style fg='#e0e0e0'
    set -g window-status-current-style fg='#e0e0e0'
    set -g window-status-bell-style fg='#ff6b6b',bg='#121212',bold
    set -g window-status-activity-style fg='#7aa2f7',bg='#121212',bold
    set -g pane-border-style fg='#3d3d3d'
    set -g pane-active-border-style fg='#e0e0e0'
    set -g copy-mode-selection-style fg='#121212',bg='yellow'
    set -g copy-mode-current-match-style fg='#121212',bg='yellow'
    set -g copy-mode-match-style 'reverse'
  '';

  xdg.configFile."tmux/themes/daylight.conf".text = ''
    set -g status-bg '#f5f5f5'
    set -g status-fg '#1a1a1a'
    set -g window-status-style fg='#1a1a1a'
    set -g window-status-current-style fg='#1a1a1a'
    set -g window-status-bell-style fg='#c7254e',bg='#f5f5f5',bold
    set -g window-status-activity-style fg='#3b5bdb',bg='#f5f5f5',bold
    set -g pane-border-style fg='#e8e8e8'
    set -g pane-active-border-style fg='#1a1a1a'
    set -g copy-mode-selection-style fg='#f5f5f5',bg='yellow'
    set -g copy-mode-current-match-style fg='#f5f5f5',bg='yellow'
    set -g copy-mode-match-style 'reverse'
  '';

  programs.lf = {
    enable = true;
    settings = {
      drawbox = true;
      number = true;
      relativenumber = true;
      hidden = true;
      shell = "zsh";
      icons = false;
      incsearch = true;
      scrolloff = 4;
      tabstop = 2;
      smartcase = true;
      dircounts = true;
      info = "size";
      ratios = "1:2:3";
      timefmt = "2006-01-02 15:04:05 -0700";
      previewer = "~/.config/lf/previewer";
      cleaner = "~/.config/lf/cleaner";
    };

    commands = {
      open = ''
        $${{
                setsid -f xdg-open "$f" 2>/dev/null 2>&1 &
              }}'';
      sopen = ''
        $${{
                for f in $fx; do
                   setsid -f xdg-open "$f" >/dev/null 2>&1 &
                done
              }}'';
      rmd = ''
        $${{
                set -f
                while IFS= read -r dir; do
                    rmdir -v -- "$dir"
                done <<< "$fx"
              }}'';
      rmf = ''
        $${{
                set -f
                while IFS= read -r file; do
                    rm -v -- "$file"
                done <<< "$fx"
              }}'';
      resize = ''
        %{{
                w=$(tmux display-message -p '#{pane_width}' || tput cols)
                if [ $w -le 62 ]; then
                    lf -remote "send $id set ratios 1:4"
                    lf -remote "send $id set nopreview"
                elif [ $w -le 80 ]; then
                    lf -remote "send $id set ratios 1:2:2"
                elif [ $w -le 100 ]; then
                    lf -remote "send $id set ratios 1:2:3"
                else
                    lf -remote "send $id set ratios 2:4:5"
                fi
              }}'';
      on-init = ''
        %{{
                lf -remote "send $id resize"
              }}'';
    };

    keybindings = {
      "<c-o>" = ":sopen; quit";
      "." = "set hidden!";
      "ad" = "push $mkdir<space>";
      "af" = "push $touch<space>";
      "xd" = "rmd";
      "xf" = "rmf";
      "H" = "jump-prev";
      "L" = "jump-next";
      "<c-t>" = ''$lf -remote "send $id select $(fzf)"'';
      "zz" = "push :z<space>";
    };

    extraConfig = ''
      set shellopts '-eu'
      set ifs "\n"
    '';
  };

  xdg.configFile."lf/previewer" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/config/lf/previewer";
  };

  xdg.configFile."lf/cleaner" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/config/lf/cleaner";
  };

  xdg.configFile."lf/lf.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/config/lf/lf.lua";
  xdg.configFile."lf/sort.py".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/config/lf/sort.py";
}
