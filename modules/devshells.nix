{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      commonPackages = [
        pkgs.just
        pkgs.deadnix
        pkgs.lua-language-server
        pkgs.black
        pkgs.shellcheck
        pkgs.shfmt
        pkgs.ty
      ];
    in
    {
      formatter = pkgs.nixfmt-tree;

      devShells = {
        default = pkgs.mkShell {
          packages = commonPackages ++ [
            pkgs.xxd
            pkgs.pre-commit
          ];
        };
        ci = pkgs.mkShell {
          packages = commonPackages;
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
