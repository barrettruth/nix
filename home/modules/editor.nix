{ pkgs, config, ... }:

{
  home.sessionVariables = {
    EDITOR = "nvim";
    MANPAGER = "nvim +Man!";
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraPackages = with pkgs; [
      # lsp
      bash-language-server
      basedpyright
      clang-tools
      emmet-language-server
      lua-language-server
      ruff
      tinymist
      vscode-langservers-extracted

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

      # runtime/tools
      nodejs
      websocat
    ];
  };

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/nvim";
}
