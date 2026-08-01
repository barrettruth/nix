{ ... }:
let
  identity = rec {
    fullName = "Barrett Ruth";
    email = "br@barrettruth.com";
    domain = "barrettruth.com";
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${email}"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAVzzY8UkHm+o6u8JIFJQNLnA8uCo7STUpvPXL70SQr ${email}"
    ];
  };
in
{
  _module.args = { inherit identity; };
}
