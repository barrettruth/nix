{
  # The macs run upstream nix. Determinate's module writes its settings to
  # /etc/nix/nix.custom.conf, which only its own daemon reads, and forces
  # nix.enable off so nothing writes /etc/nix/nix.conf either. Off, nix-darwin
  # manages the file this nix actually reads.
  determinateNix.enable = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
