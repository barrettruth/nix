{
  lib,
  curl,
  gnutar,
  neovimPackage,
  stdenv,
  tree-sitter,
  wrapNeovimUnstable,
}:
let
  wrapped = wrapNeovimUnstable neovimPackage {
    wrapRc = false;
    wrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [
        tree-sitter
        stdenv.cc
        curl
        gnutar
      ])
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
  }
)
