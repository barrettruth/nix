{
  lib,
  config,
  pkgs,
  ...
}:

let
  homeDir = config.home.homeDirectory;
  repoDir = "${homeDir}/.config/nix";

  directories = [
    "dev"
    "dl"
    "img"
    "img/screen"
    "wp"
  ];
in
{
  home.activation.createDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for dir in ${lib.concatStringsSep " " directories}; do
      $DRY_RUN_CMD mkdir -p "$HOME/$dir"
    done
  '';

  home.activation.cloneNixConfig = lib.hm.dag.entryAfter [ "createDirectories" ] ''
    if [ ! -d "${repoDir}" ]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "${repoDir}")"
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/barrettruth/nix-config.git "${repoDir}"
    fi
  '';

  home.activation.linkWallpapers = lib.hm.dag.entryAfter [ "cloneNixConfig" ] ''
    src="${repoDir}/config/screen"
    dest="$HOME/img/screen"
    if [ -d "$src" ]; then
      for f in "$src"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        [ -L "$dest/$name" ] || $DRY_RUN_CMD ln -sf "$f" "$dest/$name"
      done
    fi
  '';
}
