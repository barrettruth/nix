{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs,
}:
buildNpmPackage {
  pname = "vercel-cli";
  version = "59.17.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-YaAgQaTCD9rfqN6RmSHLE0YFYMvVOf3llWHdjjQSkwk=";

  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp -R node_modules "$out/lib/node_modules"

    makeWrapper ${lib.getExe nodejs} "$out/bin/vercel" \
      --add-flags "$out/lib/node_modules/vercel/dist/vc.js" \
      --set-default VERCEL_TELEMETRY_DISABLED 1 \
      --set-default NO_UPDATE_NOTIFIER 1
    ln -s vercel "$out/bin/vc"

    runHook postInstall
  '';

  meta = {
    description = "Vercel CLI, for managing deployments, domains and DNS records";
    homepage = "https://vercel.com/docs/cli";
    license = lib.licenses.asl20;
    mainProgram = "vercel";
  };
}
