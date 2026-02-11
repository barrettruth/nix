{
  lib,
  config,
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
    "img/wp"
  ];
in
{
  home.activation.createDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for dir in ${lib.concatStringsSep " " directories}; do
      $DRY_RUN_CMD mkdir -p "$HOME/$dir"
    done
  '';

  home.activation.cleanDanglingLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for link in "$HOME/.nix-profile" "$HOME/.nix-defexpr"; do
      [ -L "$link" ] && [ ! -e "$link" ] && run rm "$link"
    done
  '';

  home.activation.linkWallpapers = lib.hm.dag.entryAfter [ "createDirectories" ] ''
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
