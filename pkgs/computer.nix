{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "agentcomputer";
  version = "0.1.35";

  src = fetchurl {
    url = "https://www.agentcomputer.ai/install/cli/latest/computer-linux-x64";
    hash = "sha256-efVTIAVYBhk2ipP9VzodFFeJ0mjp6hlOsuMR9rLu/gk=";
  };

  dontUnpack = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/computer
    ln -s computer $out/bin/agentcomputer
    ln -s computer $out/bin/aicomputer
    runHook postInstall
  '';

  meta = {
    description = "Agent Computer CLI — cloud computers for AI agents";
    homepage = "https://agentcomputer.ai";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "computer";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
