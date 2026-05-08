{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      biomeSource = lib.cleanSourceWith {
        src = ../.;
        filter =
          path: type:
          let
            name = baseNameOf path;
            pathString = toString path;
            biomeSuffixes = [
              ".css"
              ".cjs"
              ".gql"
              ".graphql"
              ".html"
              ".js"
              ".json"
              ".jsonc"
              ".mjs"
              ".ts"
              ".tsx"
            ];
          in
          type == "directory"
          || (
            type == "regular"
            && (
              builtins.elem name [
                ".gitignore"
                "biome.json"
              ]
              || (
                lib.any (suffix: lib.hasSuffix suffix pathString) biomeSuffixes
                && !lib.hasSuffix ".min.js" pathString
              )
            )
          );
      };
      commonPackages = [
        pkgs.just
        pkgs.deadnix
        pkgs.statix
        pkgs.nixfmt
        pkgs.shfmt
        pkgs.stylua
        pkgs.selene
        pkgs.biome
      ];
    in
    {
      formatter = pkgs.nixfmt-tree;
      checks.biome = pkgs.runCommandLocal "biome-check" { nativeBuildInputs = [ pkgs.biome ]; } ''
        cd ${biomeSource}
        biome ci .
        touch $out
      '';

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
