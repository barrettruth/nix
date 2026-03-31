{ hostConfig, ... }:
let
  inherit (hostConfig)
    homeDirectory
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_STATE_HOME
    XDG_CACHE_HOME
    ;
  repo = "${XDG_CONFIG_HOME}/nix";
in
{
  environment.sessionVariables = {
    XDG_CONFIG_HOME = "${XDG_CONFIG_HOME}";
    XDG_DATA_HOME = "${XDG_DATA_HOME}";
    XDG_STATE_HOME = "${XDG_STATE_HOME}";
    XDG_CACHE_HOME = "${XDG_CACHE_HOME}";
    EDITOR = "nvim";
    MANPAGER = "nvim +Man!";
    TERMINAL = "ghostty";
    TERM = "xterm-ghostty";
    TERMINFO = "${XDG_DATA_HOME}/terminfo";
    BROWSER = "zen-beta";
    FZF_DEFAULT_OPTS_FILE = "${XDG_CONFIG_HOME}/fzf/themes/theme";
    FZF_DEFAULT_COMMAND = "rg --files --hidden";
    FZF_CTRL_T_COMMAND = "rg --files --hidden";
    FZF_ALT_C_COMMAND = "fd --type d --hidden";
    LESSHISTFILE = "-";
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
    AWS_SHARED_CREDENTIALS_FILE = "${XDG_CONFIG_HOME}/aws/credentials";
    AWS_CONFIG_FILE = "${XDG_CONFIG_HOME}/aws/config";
    BOTO_CONFIG = "${XDG_CONFIG_HOME}/boto/config";
    PSQL_HISTORY = "${XDG_STATE_HOME}/psql_history";
    SQLITE_HISTORY = "${XDG_STATE_HOME}/sqlite_history";
    TEXMFHOME = "${XDG_DATA_HOME}/texmf";
    TEXMFVAR = "${XDG_CACHE_HOME}/texlive/texmf-var";
    TEXMFCONFIG = "${XDG_CONFIG_HOME}/texlive/texmf-config";
    CLAUDE_CONFIG_DIR = "${XDG_CONFIG_HOME}/claude";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    XCURSOR_SIZE = "24";
    XCURSOR_THEME = "macOS";
  };

  environment.extraInit = ''
    export PATH="${repo}/scripts:${homeDirectory}/.local/bin:${XDG_DATA_HOME}/cargo/bin:${XDG_DATA_HOME}/go/bin:${XDG_DATA_HOME}/pnpm:$PATH"
  '';
}
