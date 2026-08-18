{
  lib,
  stdenvNoCC,
  fetchzip,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "amethyst";
  version = "0.24.3";

  src = fetchzip {
    url = "https://github.com/ianyh/Amethyst/releases/download/v${finalAttrs.version}/Amethyst.zip";
    hash = "sha256-9ByhPzTL1KhR5t9bl15P6PoOpVHlpCiFhdea52CRpTc=";
    stripRoot = false;
  };

  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R Amethyst.app "$out/Applications/"
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Tiling window manager for macOS along the lines of xmonad";
    homepage = "https://ianyh.com/amethyst/";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
