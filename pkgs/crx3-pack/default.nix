{
  openssl,
  python3,
  writeShellApplication,
}:

writeShellApplication {
  name = "crx3-pack";

  runtimeInputs = [ openssl ];

  text = ''
    exec ${python3}/bin/python3 ${./crx3-pack.py} "$@"
  '';
}
