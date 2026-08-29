{
  pkgs,
  pierreForgejo,
  berkeleyMono,
  ...
}:
let
  frontendSrc = builtins.path {
    path = ./frontend;
    name = "forgejo-custom-frontend-src";
  };
  assetsSrc = builtins.path {
    path = ./assets;
    name = "forgejo-custom-assets-src";
  };
  templatesSrc = builtins.path {
    path = ./templates;
    name = "forgejo-custom-templates-src";
  };
  frontend = pkgs.buildNpmPackage {
    pname = "barrett-forgejo-custom-frontend";
    version = "0.0.0";
    src = frontendSrc;
    npmDepsHash = "sha256-w3TmCL18MC+Hs4T5HSxt1y0D58NS1Muuo98GHdHiABE=";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/js
      cp -R dist/. $out/js/
      runHook postInstall
    '';
  };
  assets =
    pkgs.runCommand "barrett-forgejo-custom-assets"
      {
        nativeBuildInputs = [
          pkgs.woff2
        ];
      }
      ''
        full_to_woff2() {
          local input="$1"
          local output="$2"
          local stem="$TMPDIR/$(basename "$output" .woff2)"
          local tmp="$stem.''${input##*.}"
          cp "$input" "$tmp"
          chmod u+w "$tmp"
          woff2_compress "$tmp" >/dev/null
          mv "$stem.woff2" "$output"
        }

        mkdir -p $out
        cp -R --no-preserve=mode,ownership ${assetsSrc}/. $out/
        cat \
          ${assetsSrc}/css/barrett-forgejo/00-vars.css \
          ${assetsSrc}/css/barrett-forgejo/10-base.css \
          > $out/css/barrett-forgejo.css
        mkdir -p $out/fonts/berkeley-mono
        full_to_woff2 ${berkeleyMono}/share/fonts/opentype/BerkeleyMono-Regular.otf \
          $out/fonts/berkeley-mono/BerkeleyMono-Regular-v1.woff2
        full_to_woff2 ${berkeleyMono}/share/fonts/opentype/BerkeleyMono-Oblique.otf \
          $out/fonts/berkeley-mono/BerkeleyMono-Italic-v1.woff2
        full_to_woff2 ${berkeleyMono}/share/fonts/opentype/BerkeleyMono-Bold.otf \
          $out/fonts/berkeley-mono/BerkeleyMono-Bold-v1.woff2
        full_to_woff2 ${berkeleyMono}/share/fonts/opentype/BerkeleyMono-Bold-Oblique.otf \
          $out/fonts/berkeley-mono/BerkeleyMono-BoldItalic-v1.woff2
      '';
  templates = pkgs.runCommand "barrett-forgejo-custom-templates" { } ''
    cp -R --no-preserve=mode,ownership ${templatesSrc}/. $out/

    version_for() {
      sha256sum "$1" | cut -c1-16
    }

    substituteInPlace $out/custom/header.tmpl \
      --replace-fail __BARRETT_FORGEJO_CSS_VERSION__ "$(version_for ${assets}/css/barrett-forgejo.css)" \
      --replace-fail __PIERRE_FORGEJO_CSS_VERSION__ "$(version_for ${pierreForgejo.assets}/css/pierre-forgejo.css)" \
      --replace-fail __BARRETT_FORGEJO_CM6_VERSION__ "$(version_for ${assets}/js/midnight-cm6.js)" \
      --replace-fail __BARRETT_FORGEJO_JS_VERSION__ "$(version_for ${frontend}/js/barrett-forgejo.js)" \
      --replace-fail __PIERRE_FORGEJO_JS_VERSION__ "$(version_for ${pierreForgejo.frontend}/js/pierre-forgejo.js)"
  '';
in
{
  inherit frontend assets templates;
}
