{ lib, ... }:
{
  environment.sessionVariables = {
    EDITOR = "nvim";
    MANPAGER = "nvim +Man!";
    TERMINAL = "ghostty";
    TERM = "xterm-ghostty";
    TERMINFO = "/home/barrett/.local/share/terminfo";
    BROWSER = "zen-beta";
    FZF_DEFAULT_OPTS_FILE = "/home/barrett/.config/fzf/themes/theme";
    FZF_DEFAULT_COMMAND = "rg --files --hidden";
    FZF_CTRL_T_COMMAND = "rg --files --hidden";
    FZF_ALT_C_COMMAND = "fd --type d --hidden";
    LESSHISTFILE = "-";
    WGETRC = "/home/barrett/.config/wgetrc";
    LUAROCKS_CONFIG = "/home/barrett/.config/luarocks/config.lua";
    GRADLE_USER_HOME = "/home/barrett/.config/gradle";
    LIBVIRT_DEFAULT_URI = "qemu:///system";
    MBSYNCRC = "/home/barrett/.config/mbsync/config";
    PARALLEL_HOME = "/home/barrett/.config/parallel";
    PASSWORD_STORE_DIR = "/home/barrett/.local/share/pass";
    PRETTIERD_CONFIG_HOME = "/home/barrett/.local/state/prettierd";
    RIPGREP_CONFIG_PATH = "/home/barrett/.config/rg/config";
    CARGO_HOME = "/home/barrett/.local/share/cargo";
    RUSTUP_HOME = "/home/barrett/.local/share/rustup";
    GOPATH = "/home/barrett/.local/share/go";
    GOMODCACHE = "/home/barrett/.cache/go/mod";
    NPM_CONFIG_USERCONFIG = "/home/barrett/.config/npm/npmrc";
    NODE_REPL_HISTORY = "/home/barrett/.local/state/node_repl_history";
    PNPM_HOME = "/home/barrett/.local/share/pnpm";
    PNPM_NO_UPDATE_NOTIFIER = "true";
    PYTHONSTARTUP = "/home/barrett/.config/python/pythonrc";
    PYTHON_HISTORY = "/home/barrett/.local/state/python_history";
    PYTHONPYCACHEPREFIX = "/home/barrett/.cache/python";
    PYTHONUSERBASE = "/home/barrett/.local/share/python";
    MYPY_CACHE_DIR = "/home/barrett/.cache/mypy";
    JUPYTER_CONFIG_DIR = "/home/barrett/.config/jupyter";
    JUPYTER_PLATFORM_DIRS = "1";
    OPAMROOT = "/home/barrett/.local/share/opam";
    DOCKER_CONFIG = "/home/barrett/.config/docker";
    AWS_SHARED_CREDENTIALS_FILE = "/home/barrett/.config/aws/credentials";
    AWS_CONFIG_FILE = "/home/barrett/.config/aws/config";
    BOTO_CONFIG = "/home/barrett/.config/boto/config";
    PSQL_HISTORY = "/home/barrett/.local/state/psql_history";
    SQLITE_HISTORY = "/home/barrett/.local/state/sqlite_history";
    TEXMFHOME = "/home/barrett/.local/share/texmf";
    TEXMFVAR = "/home/barrett/.cache/texlive/texmf-var";
    TEXMFCONFIG = "/home/barrett/.config/texlive/texmf-config";
    CLAUDE_CONFIG_DIR = "/home/barrett/.config/claude";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    XCURSOR_SIZE = "24";
    XCURSOR_THEME = "macOS";
  };

  environment.extraInit = ''
    export PATH="/home/barrett/.config/nix/scripts:/home/barrett/.local/bin:/home/barrett/.local/share/cargo/bin:/home/barrett/.local/share/go/bin:/home/barrett/.local/share/pnpm:$PATH"
  '';
}
