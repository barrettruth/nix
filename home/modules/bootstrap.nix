{
  lib,
  config,
  hostConfig,
  ...
}:

let
  homeDir = config.home.homeDirectory;
  repoDir = "${homeDir}/.config/nix";

  directories =
    [
      "dev"
      "Downloads"
      "Pictures"
    ]
    ++ lib.optionals hostConfig.isLinux [
      "Pictures/Screensavers"
      "Pictures/Screenshots"
      "Pictures/wp"
    ];
in
{
  home.activation.createDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for dir in ${lib.concatStringsSep " " directories}; do
      run mkdir -p "$HOME/$dir"
    done
  '';

  home.activation.cleanDanglingLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for link in "$HOME/.nix-profile" "$HOME/.nix-defexpr"; do
      [ -L "$link" ] && [ ! -e "$link" ] && run rm "$link"
    done
  '';

  home.activation.linkWallpapers = lib.mkIf hostConfig.isLinux (
    lib.hm.dag.entryAfter [ "createDirectories" ] ''
      src="${repoDir}/config/screen"
      dest="$HOME/Pictures/Screensavers"
      if [ -d "$src" ]; then
        for f in "$src"/*; do
          [ -f "$f" ] || continue
          name=$(basename "$f")
          [ -L "$dest/$name" ] || run ln -sf "$f" "$dest/$name"
        done
      fi
    ''
  );
}
