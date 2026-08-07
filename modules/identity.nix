{ ... }:
let
  identity = rec {
    fullName = "Barrett Ruth";
    email = "br@barrettruth.com";
    domain = "barrettruth.com";
    tailnetDomain = "tn.${domain}";
    tailnetHosts = {
      "100.64.0.1" = [
        "desktop"
        "delta.barrettruth.com"
        "vault.barrettruth.com"
        "finance.barrettruth.com"
      ];
    };
    hostKeys = {
      desktop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFGvo/W4vhLlW9ZVtxbFE2qzkG/SfR2zC2ZIsnfw6AEI";
      laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILt1sOYoWNtfIjLoZ7XT/VmC5s0d/Hw8Q9GQyUUaKeIC";
      forge-tailnet = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJlaElaGlwSxKvtujoAnGWSrZWlxZRdviq3Y9TgZCLZ/";
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
