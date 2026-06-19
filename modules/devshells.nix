{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      commonPackages = [
        pkgs.just
        pkgs.basedpyright
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
            pkgs.age
            pkgs.authelia
            pkgs.xxd
            pkgs.pre-commit
            pkgs.sops
            pkgs.ssh-to-age
          ];
        };
        ci = pkgs.mkShell {
          packages = commonPackages;
        };
        neovim = pkgs.mkShell {
          packages = [
            pkgs.prettier
            pkgs.stylua
            pkgs.ts_query_ls
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
