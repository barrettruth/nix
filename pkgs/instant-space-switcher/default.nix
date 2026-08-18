{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "instant-space-switcher";
  version = "2.0";

  src = fetchurl {
    url = "https://github.com/jurplel/InstantSpaceSwitcher/releases/download/v${finalAttrs.version}/InstantSpaceSwitcher-${finalAttrs.version}.dmg";
    hash = "sha256-48DH2Hu/XhLPr8jP2ArmLJLFbJmIupkrlqlFOsNnL7g=";
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R InstantSpaceSwitcher.app "$out/Applications/"
    ln -s "$out/Applications/InstantSpaceSwitcher.app/Contents/MacOS/ISSCli" "$out/bin/isscli"
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Native instant workspace switching on macOS with no animation";
    homepage = "https://github.com/jurplel/InstantSpaceSwitcher";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "isscli";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
