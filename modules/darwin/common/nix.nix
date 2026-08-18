{
  determinateNix.enable = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
