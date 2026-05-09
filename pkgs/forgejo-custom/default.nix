{
  pkgs,
  ...
}:
let
  sfProLatinRange = "U+0000-00FF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2212,U+FB00-FB06";
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
  assets =
    pkgs.runCommand "barrett-forgejo-custom-assets"
      {
        nativeBuildInputs = [
          pkgs.python3Packages.fonttools
          pkgs.woff2
        ];
      }
      ''
        full_to_woff2() {
          local input="$1"
          local output="$2"
          local tmp="$TMPDIR/$(basename "$output" .woff2).ttf"
          cp "$input" "$tmp"
          chmod u+w "$tmp"
          woff2_compress "$tmp" >/dev/null
          mv "''${tmp%.ttf}.woff2" "$output"
        }

        subset_to_woff2() {
          local input="$1"
          local output="$2"
          local unicodes="$3"
          local tmp="$TMPDIR/$(basename "$output" .woff2).ttf"
          pyftsubset "$input" \
            --output-file="$tmp" \
            --layout-features='*' \
            --unicodes="$unicodes" \
            --ignore-missing-glyphs
          woff2_compress "$tmp" >/dev/null
          mv "''${tmp%.ttf}.woff2" "$output"
        }

        mkdir -p $out
        cp -R ${./assets}/. $out/
        chmod -R u+w $out
        cat \
          ${./assets/css/barrett-forgejo/00-vars.css} \
          ${./assets/css/barrett-forgejo/10-base.css} \
          ${./assets/css/barrett-forgejo/20-pierre.css} \
          ${./assets/css/barrett-forgejo/30-pr-native-diff.css} \
          > $out/css/barrett-forgejo.css
        mkdir -p $out/fonts
        cp ${noniconsFont}/dist/nonicons.woff $out/fonts/nonicons.woff
        full_to_woff2 ${noniconsFont}/dist/nonicons.ttf $out/fonts/nonicons-v1.woff2

        mkdir -p $out/fonts/san-francisco-pro
        subset_to_woff2 ${../../fonts/san-francisco-pro}/SF-Pro.ttf \
          $out/fonts/san-francisco-pro/SF-Pro-latin-v1.woff2 \
          "${sfProLatinRange}"
        subset_to_woff2 ${../../fonts/san-francisco-pro}/SF-Pro-Italic.ttf \
          $out/fonts/san-francisco-pro/SF-Pro-Italic-latin-v1.woff2 \
          "${sfProLatinRange}"
        full_to_woff2 ${../../fonts/san-francisco-pro}/SF-Pro.ttf \
          $out/fonts/san-francisco-pro/SF-Pro-v1.woff2
        full_to_woff2 ${../../fonts/san-francisco-pro}/SF-Pro-Italic.ttf \
          $out/fonts/san-francisco-pro/SF-Pro-Italic-v1.woff2

        mkdir -p $out/fonts/berkeley-mono
        full_to_woff2 ${../../fonts/berkeley-mono}/BerkeleyMono-Regular.ttf \
          $out/fonts/berkeley-mono/BerkeleyMono-Regular-v1.woff2
        full_to_woff2 ${../../fonts/berkeley-mono}/BerkeleyMono-Italic.ttf \
          $out/fonts/berkeley-mono/BerkeleyMono-Italic-v1.woff2
        full_to_woff2 ${../../fonts/berkeley-mono}/BerkeleyMono-Bold.ttf \
          $out/fonts/berkeley-mono/BerkeleyMono-Bold-v1.woff2
        full_to_woff2 ${../../fonts/berkeley-mono}/BerkeleyMono-BoldItalic.ttf \
          $out/fonts/berkeley-mono/BerkeleyMono-BoldItalic-v1.woff2

        mkdir -p $out/fonts/stix-two
        full_to_woff2 '${pkgs.stix-two}/share/fonts/truetype/STIXTwoText[wght].ttf' \
          $out/fonts/stix-two/STIXTwoText-v1.woff2
      '';
  templates = pkgs.runCommand "barrett-forgejo-custom-templates" { } ''
    cp -R ${./templates}/. $out/
    chmod -R u+w $out

    version_for() {
      sha256sum "$1" | cut -c1-16
    }

    substituteInPlace $out/custom/header.tmpl \
      --replace-fail __BARRETT_FORGEJO_CSS_VERSION__ "$(version_for ${assets}/css/barrett-forgejo.css)" \
      --replace-fail __BARRETT_FORGEJO_CM6_VERSION__ "$(version_for ${assets}/js/midnight-cm6.js)" \
      --replace-fail __BARRETT_FORGEJO_JS_VERSION__ "$(version_for ${frontend}/js/barrett-forgejo.js)" \
      --replace-fail __BARRETT_FORGEJO_PIERRE_PRELOAD_VERSION__ "$(version_for ${frontend}/js/pierre-preload.js)"
  '';
in
{
  inherit frontend assets templates;
}
