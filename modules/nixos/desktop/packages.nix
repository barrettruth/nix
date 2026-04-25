{
  pkgs,
  lib,
  hostConfig,
  whisperPkgs ? pkgs,
  ...
}:
let
  pytest-language-server = pkgs.callPackage ../../../pkgs/pytest-language-server.nix { };

  whisper = whisperPkgs.whisper-cpp.override { cudaSupport = hostConfig.gpu == "nvidia"; };

  devin = pkgs.symlinkJoin {
    name = "devin";
    paths = [ pkgs."devin-cli" ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/devin \
        --add-flags "--agent-config ${hostConfig.XDG_CONFIG_HOME}/devin/agent.yaml"
    '';
  };
in
{
  users.users.${hostConfig.username}.packages =
    with pkgs;
    [
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
      just
      gcc
      file
      ffmpeg
      poppler-utils
      librsvg
      imagemagick
      luarocks

      rustup
      uv
      python3
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
      ty
      selene
      shellcheck
      deadnix
      statix

      nodejs
      bun
      lua
      tree-sitter
      nixfmt-tree

      tea
      git-lfs

      gemini-cli
      typst
      typstyle
      glab

      psmisc
      brightnessctl
      socat
      glib.bin

      fzf
      eza
      zoxide
      ripgrep
      fd
      direnv
      nix-direnv
      tmux
      neovim
      vim
      gh
      jujutsu
      gnupg

      ghostty

      whisper

      tmuxPlugins.resurrect
      tmuxPlugins.continuum

      zsh-syntax-highlighting
      zsh-autosuggestions
    ]
    ++ lib.optionals hostConfig.enableTexlive [
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
    ]
    ++ lib.optionals hostConfig.enableDesktop [
      slack
      zathura
      mpv
      (chromium.override {
        commandLineArgs = "--silent-debugger-extension-api";
      })
      vesktop
      signal-desktop
      telegram-desktop
      cinny-desktop
      element-desktop
      xdg-desktop-portal-gtk
      nerd-fonts.jetbrains-mono
      papirus-icon-theme
      apple-cursor
      libnotify
      gsettings-desktop-schemas
    ]
    ++ lib.optionals hostConfig.enableWayland [
      hyprlock
      fuzzel
      wl-clipboard
      grim
      slurp
      wf-recorder
      pkgs.hyprland
      pkgs.xdg-desktop-portal-hyprland
      waybar
      dunst
      hyprpaper
      hypridle
      cliphist
    ];
}
