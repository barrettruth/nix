{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "pytest-language-server";
  version = "0.21.0";

  src = fetchFromGitHub {
    owner = "bellini666";
    repo = "pytest-language-server";
    rev = "v${version}";
    hash = "sha256-Vvr4TGt5QZL1Ypw1zBSzkv+5JT4fxHayHpIbVTFwO9I=";
  };

  doCheck = false;

  cargoHash = "sha256-E4KcGqMRUvmSK93ALzqzlE+MJoxMQUZnJofW3eWVicU=";

  meta = {
    description = "Language Server Protocol implementation for pytest";
    homepage = "https://github.com/bellini666/pytest-language-server";
    license = lib.licenses.mit;
    mainProgram = "pytest-language-server";
  };
}
