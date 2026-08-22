{
  lib,
  pkgs,
  forgejo,
  buildGoModule,
  buildNpmPackage,
  fetchurl,
  bash,
  git,
  gzip,
  openssh,
  makeWrapper,
  writableTmpDirAsHomeHook,
  nodejs,
  python3,
  frontendPatches ? [ ],
}:
let
  inherit (forgejo) version vendorHash;
  legacyModesVersion = "6.5.0";

  legacyModes = fetchurl {
    url = "https://registry.npmjs.org/@codemirror/legacy-modes/-/legacy-modes-${legacyModesVersion}.tgz";
    hash = "sha256-NarHMgm6lGRLB21eke8AOQn7ezOyo9A2uMXP/bG3JtM=";
  };

  frontend = buildNpmPackage {
    pname = "forgejo-frontend-with-cm6-langs";
    inherit version nodejs;
    src = forgejo.src;
    inherit (forgejo) npmDeps;
    patches = frontendPatches;

    nativeBuildInputs = [ python3 ];

    postPatch = ''
      python3 -c "
      import re, pathlib
      path = pathlib.Path('web_src/js/features/codemirror-lang.ts')
      text = path.read_text()
      addition = pathlib.Path('${./codemirror-langs.append.txt}').read_text()
      text = re.sub(r'(\n  \];\n\}\n?)$', '\n' + addition + r'\1', text, count=1)
      path.write_text(text)
      "
    '';

    preBuild = ''
      mkdir -p node_modules/@codemirror/legacy-modes
      tar xzf ${legacyModes} -C node_modules/@codemirror/legacy-modes --strip-components=1
    '';

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
  src = forgejo.src;

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
      + " (with @codemirror/legacy-modes registered for INI/TOML/Shell/Lua/Ruby/Dockerfile/Perl/Nginx/Diff)";
  };
}
