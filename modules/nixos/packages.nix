{
  pkgs,
  hostConfig,
  whisperPkgs ? pkgs,
  ...
}:
let
  pytest-language-server = pkgs.callPackage ../../pkgs/pytest-language-server.nix { };

  whisper = whisperPkgs.whisper-cpp.override { cudaSupport = hostConfig.gpu == "nvidia"; };

  devin = pkgs.callPackage ../../pkgs/devin.nix {
    agentConfig = "${hostConfig.XDG_CONFIG_HOME}/devin/agent.yaml";
  };
in
{
  users.users.${hostConfig.username}.packages = with pkgs; [
    awscli2
    pure-prompt
    tree
    typos
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
    luarocks
    xclip

    rustup
    uv
    python3
    claude-code
    codex
    devin

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
    selene
    shellcheck
    deadnix
    statix

    nodejs
    bun
    lua
    tree-sitter
    nixfmt-tree
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

    tea
    git-lfs

    slack
    gemini-cli
    typst
    typstyle
    glab
    zathura
    mpv
    (chromium.override {
      commandLineArgs = "--silent-debugger-extension-api";
    })

    vesktop
    signal-desktop
    telegram-desktop
    element-desktop

    xdg-desktop-portal-gtk
    hyprlock
    nerd-fonts.jetbrains-mono
    papirus-icon-theme
    psmisc
    fuzzel
    wl-clipboard
    grim
    slurp
    wf-recorder
    libnotify
    brightnessctl
    socat
    glib.bin
    gsettings-desktop-schemas

    pkgs.hyprland
    pkgs.xdg-desktop-portal-hyprland

    fzf
    eza
    zoxide
    ripgrep
    fd
    direnv
    nix-direnv
    tmux
    neovim
    gh
    jujutsu
    gnupg

    ghostty

    apple-cursor

    whisper

    tmuxPlugins.resurrect
    tmuxPlugins.continuum

    zsh-syntax-highlighting
    zsh-autosuggestions

    waybar

    dunst

    hyprpaper
    hypridle

    cliphist
  ];
}
