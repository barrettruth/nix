{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

let
  version = "152.0.7977.82";
  revision = "1.1";
  hashes = {
    aarch64-darwin = "sha256-umc4dlM+ebPAntrz69Da3MKenQESubhD2MAyz7e/tFc=";
    x86_64-darwin = "sha256-AMzHPmP5ef2rvBjKZ5mbKrzUCaxmL70s1vhrDzKQRYg=";
  };
  arch =
    {
      aarch64-darwin = "arm64";
      x86_64-darwin = "x86_64";
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "ungoogled-chromium-bin";
  version = "${version}-${revision}";

  src = fetchurl {
    url = "https://github.com/ungoogled-software/ungoogled-chromium-macos/releases/download/${version}-${revision}/ungoogled-chromium_${version}-${revision}_${arch}-macos.dmg";
    hash = hashes.${stdenvNoCC.hostPlatform.system};
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = "Chromium.app";

  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications/Ungoogled Chromium.app"
    cp -R . "$out/Applications/Ungoogled Chromium.app"
    runHook postInstall
  '';

  meta = {
    description = "Chromium with dependencies on Google web services removed, notarized for macOS";
    homepage = "https://github.com/ungoogled-software/ungoogled-chromium-macos";
    license = lib.licenses.bsd3;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames hashes;
  };
}
