{ ... }:
let
  identity = {
    fullName = "Barrett Ruth";
    email = "br@barrettruth.com";
    gpgKey = "A6C96C9349D2FC81";
    domain = "barrettruth.com";
  };
in
{
  _module.args = { inherit identity; };
}
