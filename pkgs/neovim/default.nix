{
  lib,
  neovimPackage,
  vimPlugins,
  wrapNeovimUnstable,
}:
let
  grammars = lib.filter lib.isDerivation (builtins.attrValues vimPlugins.nvim-treesitter-parsers);
  queries = lib.filter (query: query != null) (
    map (grammar: grammar.associatedQuery or null) grammars
  );
  wrapped = wrapNeovimUnstable neovimPackage {
    wrapRc = false;
    wrapperArgs = [
      "--add-flags"
      ''--cmd "lua dofile('${vimPlugins.nvim-treesitter}/plugin/filetypes.lua')"''
    ];
    plugins = grammars ++ queries;
  };
in
wrapped.overrideAttrs (
  old:
  let
    pname = neovimPackage.pname or (old.pname or "neovim");
    version = neovimPackage.version or (old.version or lib.getVersion neovimPackage);
  in
  {
    inherit pname version;
    name = "${pname}-${version}";
  }
)
