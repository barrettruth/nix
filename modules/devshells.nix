{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt-tree;

      devShells = {
        default = pkgs.mkShell {
          packages = [
            pkgs.xxd
            pkgs.deadnix
            pkgs.statix
            pkgs.nixfmt
            pkgs.pre-commit
            pkgs.prettier
            pkgs.shfmt
            pkgs.stylua
            pkgs.selene
          ];
        };
        neovim = pkgs.mkShell {
          packages = [
            pkgs.prettier
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
            pkgs.vimdoc-language-server
            (pkgs.luajit.withPackages (ps: [
              ps.busted
              ps.nlua
            ]))
          ];
        };
      };
    };
}
