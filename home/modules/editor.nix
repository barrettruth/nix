{ pkgs, config, ... }:

{
  home.sessionVariables = {
    EDITOR = "nvim";
    MANPAGER = "nvim +Man!";
  };

  home.packages = with pkgs; [
    nodejs
    isort
    black
    mypy
    stylua
    selene
    prettierd
    eslint_d
    shfmt
    buf
    hadolint
    cbfmt
    cmake-format
    checkmake
    cpplint
    texlivePackages.latexindent
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix/config/nvim";
}
