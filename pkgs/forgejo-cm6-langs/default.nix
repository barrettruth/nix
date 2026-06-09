{
  lib,
  pkgs,
  forgejo,
  buildGoModule,
  buildNpmPackage,
  bash,
  git,
  gzip,
  openssh,
  makeWrapper,
  writableTmpDirAsHomeHook,
  nodejs,
  cacert,
  python3,
  frontendPatches ? [ ],
}:
let
  inherit (forgejo) version vendorHash;
  legacyModesVersion = "6.5.0";

  # FOD: add @codemirror/legacy-modes + extra lang registrations to forgejo's
  # web source; outputHash needs lib.fakeHash iteration on first build.
  patchedSrc =
    pkgs.runCommand "forgejo-${version}-with-cm6-langs-source"
      {
        nativeBuildInputs = [
          nodejs
          python3
          cacert
        ];
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-Bvp0NjYkL5q0hr5bBobZ5kJ0htDzV+ZorY2y6R7LN1A=";
      }
      ''
        set -euo pipefail
        cp -r --no-preserve=mode,ownership ${forgejo.src} src
        cd src
        export HOME=$(mktemp -d)
        export NPM_CONFIG_CACHE="$HOME/.npm-cache"
        export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

        node -e "
          const fs = require('fs');
          const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
          pkg.dependencies['@codemirror/legacy-modes'] = '${legacyModesVersion}';
          fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
        "

        npm install --package-lock-only --no-audit --no-fund

        python3 -c "
        import re, pathlib
        path = pathlib.Path('web_src/js/features/codemirror-lang.ts')
        text = path.read_text()
        addition = pathlib.Path('${./codemirror-langs.append.txt}').read_text()
        text = re.sub(r'(\n  \];\n\}\n?)$', '\n' + addition + r'\1', text, count=1)
        path.write_text(text)
        "

        rm -rf "$HOME"
        cp -r --no-preserve=mode . $out
      '';

  frontend = buildNpmPackage {
    pname = "forgejo-frontend-with-cm6-langs";
    inherit version;
    src = patchedSrc;
    npmDepsHash = "sha256-s1D9FgKg3myXIAdF+rFTGlxXd72fAvTAClN9fcO5tU8=";
    patches = frontendPatches;

    buildPhase = ''
      runHook preBuild
      ./node_modules/.bin/webpack
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir $out
      cp -R ./public $out/
      runHook postInstall
    '';
  };
in
buildGoModule {
  pname = "forgejo-with-cm6-langs";
  inherit version vendorHash;
  src = patchedSrc;

  subPackages = [
    "."
    "contrib/environment-to-ini"
  ];

  outputs = [
    "out"
    "data"
  ];

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    git
    openssh
    writableTmpDirAsHomeHook
  ];

  doCheck = false;

  patches = [
    "${pkgs.path}/pkgs/by-name/fo/forgejo/static-root-path.patch"
    ./oauth-avatar-on-registration.patch
    ./profile-root-landing.patch
  ];
  postPatch = ''
    substituteInPlace modules/setting/server.go --subst-var data
  '';

  tags = [
    "sqlite"
    "sqlite_unlock_notify"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
    "-X 'main.Tags=sqlite sqlite_unlock_notify'"
  ];

  preConfigure = ''
    export ldflags+=" -X main.ForgejoVersion=$(GITEA_VERSION=${version} make show-version-api)"
  '';

  preInstall = ''
    mv "$GOPATH/bin/forgejo.org" "$GOPATH/bin/forgejo"
  '';

  postInstall = ''
    mkdir $data
    cp -R ./{templates,options} ${frontend}/public $data
    mkdir -p $out
    cp -R ./options/locale $out/locale
    wrapProgram $out/bin/forgejo \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          git
          gzip
          openssh
        ]
      }
  '';

  overrideModAttrs = _: {
    postPatch = null;
  };

  meta = forgejo.meta // {
    description =
      forgejo.meta.description
      + " (with @codemirror/legacy-modes registered for INI/TOML/Shell/Lua/Ruby/Dockerfile/Perl/Nginx/Vim script/Diff)";
  };
}
