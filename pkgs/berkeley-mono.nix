{
  lib,
  stdenvNoCC,
  src,
}:
stdenvNoCC.mkDerivation {
  pname = "barrett-berkeley-mono";
  version = "1";
  inherit src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm444 BerkeleyMono-Regular.otf $out/share/fonts/opentype/BerkeleyMono-Regular.otf
    install -Dm444 BerkeleyMono-Oblique.otf $out/share/fonts/opentype/BerkeleyMono-Oblique.otf
    install -Dm444 BerkeleyMono-Bold.otf $out/share/fonts/opentype/BerkeleyMono-Bold.otf
    install -Dm444 BerkeleyMono-Bold-Oblique.otf $out/share/fonts/opentype/BerkeleyMono-Bold-Oblique.otf

    runHook postInstall
  '';

  meta = {
    description = "Berkeley Mono";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}
