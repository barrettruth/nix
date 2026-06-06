{
  lib,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "delta-software-sync";
  version = "0.1.0";

  src = ./.;

  nativeCheckInputs = [ python3 ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/delta-software-sync
    cp delta_software_sync.py $out/share/delta-software-sync/
    cat > $out/bin/delta-software-sync <<EOF
    #!${python3}/bin/python3
    import runpy
    runpy.run_path("$out/share/delta-software-sync/delta_software_sync.py", run_name="__main__")
    EOF
    chmod +x $out/bin/delta-software-sync

    runHook postInstall
  '';

  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python3 -m unittest discover -s tests
    runHook postCheck
  '';

  meta = {
    description = "Provider-neutral forge issue/PR sync plugin for Delta";
    license = lib.licenses.gpl3Only;
    mainProgram = "delta-software-sync";
  };
}
