{
  lib,
  stdenvNoCC,
  _7zz,
  fetchurl,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ungoogled-chromium-bin";
  version = "150.0.7871.46-1.1";

  src = fetchurl {
    url = "https://github.com/ungoogled-software/ungoogled-chromium-macos/releases/download/${finalAttrs.version}/ungoogled-chromium_${finalAttrs.version}_arm64-macos.dmg";
    hash = "sha256-/nVIrUNuN7unIx+GRVHYj3f2aX/OHHtpQvq4Ep6KB5o=";
  };

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    7zz -snld x $src
    runHook postUnpack
  '';

  nativeBuildInputs = [
    _7zz
    makeBinaryWrapper
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    mv Chromium/Chromium.app $out/Applications/
    makeBinaryWrapper \
      $out/Applications/Chromium.app/Contents/MacOS/Chromium \
      $out/bin/chromium

    runHook postInstall
  '';

  dontFixup = true;

  meta = {
    description = "Chromium with Google integration removed, official macOS build";
    homepage = "https://github.com/ungoogled-software/ungoogled-chromium-macos";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "chromium";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
