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
in
wrapNeovimUnstable neovimPackage {
  wrapRc = false;
  wrapperArgs = [
    "--add-flags"
    ''--cmd "lua dofile('${vimPlugins.nvim-treesitter}/plugin/filetypes.lua')"''
  ];
  plugins = grammars ++ queries;
}
