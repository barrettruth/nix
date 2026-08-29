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
        pkgs.prettier
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
            pkgs.authelia
            pkgs.xxd
            pkgs.pre-commit
            pkgs.sops
            pkgs.ssh-to-age
          ];
        };
        ci = pkgs.mkShell {
          packages = commonPackages ++ [ pkgs.neovim-unwrapped ];
        };
        neovim = pkgs.mkShellNoCC {
          packages = [
            pkgs.just
            pkgs.prettier
            pkgs.prettierd
            pkgs.selene
            pkgs.stylua
            pkgs.lua-language-server
          ];
        };
        neovim-src = pkgs.mkShell {
          packages = [
            pkgs.just
            pkgs.bash
            pkgs.gnumake
            pkgs.cmake
            pkgs.ninja
            pkgs.gettext
            pkgs.curl
            pkgs.git
            pkgs.pkg-config
            pkgs.unzip
            pkgs.stylua
            pkgs.shellcheck
            pkgs.ts_query_ls
            pkgs.fish
            pkgs.gdb
            pkgs.xdg-utils
            pkgs.nodejs
            pkgs.perlPackages.Appcpanminus
            (pkgs.python3.withPackages (ps: [
              ps.pynvim
            ]))
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.inotify-tools
            pkgs.attr
            pkgs.acl
          ];
        };
      };
    };
}
