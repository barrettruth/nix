{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      commonPackages = [
        pkgs.just
        pkgs.basedpyright
        pkgs.deadnix
        pkgs.lua-language-server
        pkgs.black
        pkgs.prettier
        pkgs.selene
        pkgs.shellcheck
        pkgs.shfmt
        pkgs.stylua
        pkgs.ty
      ];
    in
    {
      formatter = pkgs.nixfmt-tree;

      devShells = {
        default = pkgs.mkShell {
          packages = commonPackages ++ [
            pkgs.age
            pkgs.nixd
            pkgs.xxd
            pkgs.pre-commit
            pkgs.sops
            pkgs.ssh-to-age
            pkgs.statix
          ];
        };
        ci = pkgs.mkShell {
          packages = commonPackages ++ [ pkgs.neovim ];
        };
        neovim-config = pkgs.mkShellNoCC {
          packages = [
            pkgs.just
            pkgs.neovim
            pkgs.prettier
            pkgs.selene
            pkgs.stylua
            pkgs.lua-language-server
            inputs.vimdoc-language-server.packages.${system}.default
          ];
        };
      };
    };
}
