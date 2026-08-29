{ ... }:
{
  imports = [
    ../common/activation.nix
    ../../barrett/workstation.nix
    ./ui.nix
    ./whisper.nix
  ];
}
