{ ... }:
let
  identity = {
    fullName = "Barrett Ruth";
    email = "br@barrettruth.com";
    domain = "barrettruth.com";
  };
in
{
  _module.args = { inherit identity; };
}
