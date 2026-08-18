{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "pytest-language-server";
  version = "0.24.0";

  src = fetchFromGitHub {
    owner = "bellini666";
    repo = "pytest-language-server";
    rev = "v${version}";
    hash = "sha256-wYrnO4kx1HBbyfX3vajYsJ71eSZRLUJycq4qwClCMDY=";
  };

  doCheck = false;

  cargoHash = "sha256-MljBI2wDuywgwuLjPoRjaTq46zGHbL5/2LhAMbzKx3c=";

  meta = {
    description = "Language Server Protocol implementation for pytest";
    homepage = "https://github.com/bellini666/pytest-language-server";
    license = lib.licenses.mit;
    mainProgram = "pytest-language-server";
  };
}
