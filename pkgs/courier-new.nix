{
  lib,
  stdenvNoCC,
  fetchurl,
  cabextract,
}:

let
  eula = fetchurl {
    url = "https://corefonts.sourceforge.net/eula.htm";
    hash = "sha256-LOgNEsM+dANEreP2LsFi+pAnBNDMFB9Pg+KJAahlC6s=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "courier-new";
  version = "1";

  src = fetchurl {
    url = "mirror://sourceforge/corefonts/the%20fonts/final/courie32.exe";
    hash = "sha256-u1EdhhZV3eh5rlUuuGsTTW+uZ8tYUC5v9z7F2RUfM4Q=";
  };

  nativeBuildInputs = [ cabextract ];

  unpackPhase = ''
    cabextract --lowercase "$src"
  '';

  installPhase = ''
    install -Dm444 cour.ttf "$out/share/fonts/truetype/Courier_New.ttf"
    install -Dm444 courbd.ttf "$out/share/fonts/truetype/Courier_New_Bold.ttf"
    install -Dm444 couri.ttf "$out/share/fonts/truetype/Courier_New_Italic.ttf"
    install -Dm444 courbi.ttf "$out/share/fonts/truetype/Courier_New_Bold_Italic.ttf"
    install -Dm444 "${eula}" "$out/share/fonts/truetype/eula.html"
  '';

  meta = {
    homepage = "https://corefonts.sourceforge.net/";
    description = "Courier New from Microsoft's TrueType core fonts for the Web";
    platforms = lib.platforms.all;
    license = lib.licenses.unfreeRedistributable;
  };
}
