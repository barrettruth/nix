{ ... }:
let
  identity = rec {
    fullName = "Barrett Ruth";
    email = "br@barrettruth.com";
    domain = "barrettruth.com";
    tailnetHosts = {
      "100.64.0.1" = [
        "desktop"
        "forge.barrettruth.com"
        "git.barrettruth.com"
        "www.barrettruth.com"
        "barrettruth.com"
        "www.barrettruth.sh"
        "barrettruth.sh"
        "www.philipmruth.com"
        "philipmruth.com"
        "www.vimdoc-language-server.com"
        "vimdoc-language-server.com"
        "vimdoc-language-server.barrettruth.com"
        "ts.barrettruth.com"
        "delta.barrettruth.com"
        "vault.barrettruth.com"
        "finance.barrettruth.com"
      ];
    };
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${email}"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAVzzY8UkHm+o6u8JIFJQNLnA8uCo7STUpvPXL70SQr ${email}"
    ];
  };
in
{
  _module.args = { inherit identity; };
}
