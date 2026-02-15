{
  lib,
  config,
  hostConfig,
  ...
}:

let
  homeDir = config.home.homeDirectory;
  repoDir = "${homeDir}/.config/nix";

  directories = [ "dev" ];

  pictureSubdirs = [
    "Screensavers"
    "Screenshots"
    "wp"
  ];
in
{
  home.activation.createDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    ''
      for dir in ${lib.concatStringsSep " " directories}; do
        run mkdir -p "$HOME/$dir"
      done
    ''
    + lib.optionalString hostConfig.isLinux ''
      for dir in ${lib.concatStringsSep " " pictureSubdirs}; do
        run mkdir -p "${config.xdg.userDirs.pictures}/$dir"
      done
    ''
  );

  home.activation.cleanDanglingLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for link in "$HOME/.nix-profile" "$HOME/.nix-defexpr"; do
      [ -L "$link" ] && [ ! -e "$link" ] && run rm "$link"
    done
  '';

  home.activation.linkWallpapers = lib.mkIf hostConfig.isLinux (
    lib.hm.dag.entryAfter [ "createDirectories" ] ''
      src="${repoDir}/config/screen"
      dest="${config.xdg.userDirs.pictures}/Screensavers"
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
