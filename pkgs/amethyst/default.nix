{
  lib,
  stdenvNoCC,
  fetchzip,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "amethyst";
  version = "0.24.3";

  # Amethyst is an Xcode/Swift app and cannot be built in the nix sandbox, so
  # the notarized release bundle is unpacked as-is. This is why it is absent
  # from nixpkgs.
  src = fetchzip {
    url = "https://github.com/ianyh/Amethyst/releases/download/v${finalAttrs.version}/Amethyst.zip";
    hash = "sha256-9ByhPzTL1KhR5t9bl15P6PoOpVHlpCiFhdea52CRpTc=";
    stripRoot = false;
  };

  # The bundle ships signed and stapled under Ian Ynda-Hummel's Developer ID
  # (82P2XLB4UH). The darwin fixup hook would re-sign it ad-hoc, which breaks
  # notarization and, because TCC keys ad-hoc bundles on their cdhash, would
  # drop the Accessibility grant on every version bump.
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
