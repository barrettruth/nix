{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  installShellFiles,
  makeWrapper,
  agentConfig ? null,
}:
let
  sourcesData = lib.importJSON ./devin-sources.json;
  inherit (sourcesData) version;
  source =
    sourcesData.platforms.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "devin";
  inherit version;

  src = fetchurl {
    inherit (source) url hash;
  };
  sourceRoot = ".";

  nativeBuildInputs = [
    installShellFiles
  ]
  ++ lib.optionals (agentConfig != null) [ makeWrapper ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/devin $out/bin/devin
    if [ -d share/man/man1 ]; then
      installManPage share/man/man1/*.1
    fi
    ${lib.optionalString (agentConfig != null) ''
      wrapProgram $out/bin/devin \
        --add-flags "--agent-config ${agentConfig}"
    ''}
    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Devin for Terminal";
    homepage = "https://cli.devin.ai";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "devin";
    platforms = builtins.attrNames sourcesData.platforms;
  };
}
