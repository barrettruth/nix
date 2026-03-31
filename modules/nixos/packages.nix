{
  pkgs,
  hostConfig,
  zen-browser,
  hyprland,
  whisperPkgs ? pkgs,
  ...
}:
let
  sioyek-wrapped = pkgs.symlinkJoin {
    name = "sioyek";
    paths = [ pkgs.sioyek ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/sioyek \
        --set QT_QPA_PLATFORM wayland \
        --add-flags "--execute-command toggle_statusbar" \
        --add-flags "--execute-command toggle_synctex"
    '';
  };

  pytest-language-server = pkgs.callPackage ../../pkgs/pytest-language-server.nix { };

  whisper = whisperPkgs.whisper-cpp.override { cudaSupport = hostConfig.gpu == "nvidia"; };
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
    claude-code
    codex

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
    mpv
    libreoffice-fresh

    zen-browser.packages.${hostConfig.platform}.default

    sioyek-wrapped

    vesktop
    signal-desktop
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
    (python3.withPackages (ps: [ ps.pillow ]))

    hyprland.packages.${hostConfig.platform}.hyprland
    hyprland.packages.${hostConfig.platform}.xdg-desktop-portal-hyprland

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
