{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "3.15.15";
  releases = {
    aarch64-darwin = {
      suffix = "-arm64";
      hash = "sha256-ghKyFlPGZfrvQfIjTtU1vz4pxnjZzudoyPJr0MH3tDg=";
    };
    x86_64-darwin = {
      suffix = "";
      hash = "sha256-ZpL6xhlqjHuAGpoFqdYyTlJwG/XFKi2O2gJK2CuVUb8=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "ivpn-bin";
  inherit version;

  src = fetchurl {
    url = "https://repo.ivpn.net/macos/bin/IVPN-${version}${release.suffix}.dmg";
    inherit (release) hash;
  };

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    ln -s "$src" "$out/IVPN.dmg"
    runHook postInstall
  '';

  meta = {
    description = "Official signed IVPN macOS disk image";
    homepage = "https://www.ivpn.net/en/apps-macos/";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames releases;
  };
}
