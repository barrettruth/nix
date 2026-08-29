{ lib, inputs, ... }:
let
  hasFonts = inputs ? fonts;

  overlays = [
    inputs.devin.overlays.default
    (
      final: prev:
      let
        system = final.stdenv.hostPlatform.system;
        barrettFonts =
          let
            fontRoot = inputs.fonts.outPath;
            src = builtins.path {
              path = fontRoot;
              name = "barrett-desktop-fonts-source";
              filter =
                path: type:
                let
                  relative = lib.removePrefix "${fontRoot}/" (toString path);
                in
                type == "directory"
                || lib.hasPrefix "berkeley-mono/" relative
                || lib.hasPrefix "nonicons/" relative
                || (
                  final.stdenv.hostPlatform.isLinux && lib.hasPrefix "san-francisco-pro/SF-Pro-Display-" relative
                );
            };
          in
          final.stdenvNoCC.mkDerivation {
            pname = "barrett-fonts";
            version = "0";
            inherit src;

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall

              mkdir -p $out/share/fonts/barrett
              find . -type f \
                \( -name '*.ttf' -o -name '*.otf' -o -name '*.bdf' -o -name '*.woff' -o -name '*.woff2' \) \
                -print0 \
                | while IFS= read -r -d "" file; do
                    rel="''${file#./}"
                    install -Dm644 "$file" "$out/share/fonts/barrett/$rel"
                  done

              runHook postInstall
            '';

            meta = {
              description = "Private fonts used by Barrett's workstations";
              license = lib.licenses.unfree;
              platforms = lib.platforms.all;
            };
          };
        localNeovim =
          base:
          final.runCommand "neovim-local-first-${lib.getVersion base}"
            {
              pname = "neovim-local-first";
              version = lib.getVersion base;
              nativeBuildInputs = [ final.lndir ];
              passthru = (base.passthru or { }) // {
                inherit (base) lua;
                unwrapped = base;
              };
              meta = base.meta // {
                mainProgram = "nvim";
              };
            }
            ''
              mkdir -p $out
              lndir -silent ${base} $out
              rm -f $out/bin/nvim
              cat > $out/bin/nvim <<'EOF'
              #!${final.runtimeShell}
              set -eu

              base="${base}/bin/nvim"
              home="''${HOME:-}"
              src="$home/dev/neovim"
              asan="$src/build_asan/bin/nvim"
              normal="$src/build/bin/nvim"
              state="''${XDG_STATE_HOME:-$home/.local/state}"
              mode="''${NVIM_LOCAL_BUILD:-auto}"

              if [ -n "''${NIX_BUILD_TOP:-}" ]; then
                exec "$base" "$@"
              fi

              run_asan() {
                mkdir -p "$state/nvim/asan"
                export VIMRUNTIME="$src/runtime"
                export ASAN_SYMBOLIZER_PATH="${final.llvmPackages.llvm}/bin/llvm-symbolizer"
                export ASAN_OPTIONS="''${ASAN_OPTIONS:-detect_leaks=0:log_path=$state/nvim/asan/asan}"
                exec "$asan" "$@"
              }

              run_normal() {
                export VIMRUNTIME="$src/runtime"
                exec "$normal" "$@"
              }

              case "$mode" in
                asan)
                  [ -x "$asan" ] && run_asan "$@"
                  ;;
                normal|build)
                  [ -x "$normal" ] && run_normal "$@"
                  ;;
                auto|"")
                  [ -x "$asan" ] && run_asan "$@"
                  [ -x "$normal" ] && run_normal "$@"
                  ;;
                *)
                  printf 'nvim: unknown NVIM_LOCAL_BUILD mode: %s\n' "$mode" >&2
                  exit 2
                  ;;
              esac

              exec "$base" "$@"
              EOF
              chmod +x $out/bin/nvim
            '';
      in
      {
        neovim = final.callPackage ../pkgs/neovim {
          neovimPackage = localNeovim prev.neovim-unwrapped;
        };
      }
      // lib.optionalAttrs hasFonts {
        barrett-fonts = barrettFonts;
        barrett-webfonts = inputs.fonts.packages.${system}.web;
      }
    )
  ];

  sharedUnfree = [
    "apple_cursor"
    "barrett-fonts"
    "devin"
  ];
in
{
  _module.args = {
    inherit overlays sharedUnfree;
  };

  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) sharedUnfree;
      };
    in
    {
      _module.args.pkgs = pkgs;
      packages = {
        inherit (pkgs) neovim;
      }
      // lib.optionalAttrs hasFonts {
        inherit (pkgs) barrett-fonts barrett-webfonts;
      };
    };
}
