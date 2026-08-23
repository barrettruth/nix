{
  lib,
  buildEnv,
  neovimPackage,
  vimPlugins,
  wrapNeovimUnstable,
}:
let
  grammars = lib.filter lib.isDerivation (builtins.attrValues vimPlugins.nvim-treesitter-parsers);
  queries = lib.filter (query: query != null) (
    map (grammar: grammar.associatedQuery or null) grammars
  );
  treesitter = buildEnv {
    name = "nvim-treesitter-runtime";
    paths = grammars ++ queries;
  };
  wrapped = wrapNeovimUnstable neovimPackage {
    wrapRc = false;
    wrapperArgs = [
      "--add-flags"
      ''--cmd "lua dofile('${vimPlugins.nvim-treesitter}/plugin/filetypes.lua')"''
    ];
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
    passthru = (old.passthru or { }) // {
      inherit treesitter;
    };
  }
)
