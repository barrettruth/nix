{
  gws,
  python3,
  writeShellApplication,
}:

writeShellApplication {
  name = "google";

  runtimeInputs = [
    gws
    python3
  ];

  text = ''
    export GWS_BIN="${gws}/bin/gws"
    exec ${python3}/bin/python3 ${./google-workspace-guard.py} "$@"
  '';
}
