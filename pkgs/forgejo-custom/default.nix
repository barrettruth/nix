{
  pkgs,
  ...
}:
let
  noniconsFont = pkgs.fetchFromGitHub {
    owner = "ya2s";
    repo = "nonicons";
    rev = "a7d49eef27d1143b03a4eeb33859f411b9e93490";
    hash = "sha256-2eTjf7tl85YJkJY99Pb3a5PBhfPRUHIXXvAwfTPgnwc=";
  };
  frontend = pkgs.buildNpmPackage {
    pname = "barrett-forgejo-custom-frontend";
    version = "0.0.0";
    src = ./frontend;
    npmDepsHash = "sha256-g5GB86S7laJ92nE61HlbiQ5wJm0XgikcPMw+VY9vOXI=";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/js
      cp -R dist/. $out/js/
      runHook postInstall
    '';
  };
in
{
  inherit frontend;
  assets = pkgs.runCommand "barrett-forgejo-custom-assets" { } ''
    mkdir -p $out
    cp -R ${./assets}/. $out/
    mkdir -p $out/fonts
    cp ${noniconsFont}/dist/nonicons.woff $out/fonts/nonicons.woff
  '';
  templates = ./templates;
}
