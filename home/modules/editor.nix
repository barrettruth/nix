{
  pkgs,
  lib,
  config,
  ...
}:

let
  neovim = config.programs.neovim.enable;
in
{
  home.packages = with pkgs; [
    # lsp
    bash-language-server
    basedpyright
    clang-tools
    emmet-language-server
    lua-language-server
    ruff
    tinymist
    vscode-langservers-extracted
    nixd

    # formatters
    black
    buf
    cbfmt
    cmake-format
    isort
    prettierd
    shfmt
    stylua

    # linters
    checkmake
    cpplint
    eslint_d
    hadolint
    mypy
    selene
    shellcheck

    # runtime/tools
    nodejs
    luarocks
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
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  home.sessionVariables = lib.mkIf neovim {
    MANPAGER = "nvim +Man!";
  };

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/nvim";

  xdg.configFile."latexmk/latexmkrc".text = ''
    $out_dir = "build";
    $pdf_mode = 1;
  '';
}
