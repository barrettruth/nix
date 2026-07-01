{ lib, inputs, ... }:
let
  neovimChannel = "local";

  overlays = [
    (_final: prev: {
      "neovim-main-unwrapped" = prev.neovim-unwrapped;
    })
    inputs.neovim-nightly.overlays.default
    inputs.codex.overlays.default
    inputs.devin.overlays.default
    (
      final: prev:
      let
        system = final.stdenv.hostPlatform.system;
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
              home="''${HOME:-/home/barrett}"
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
        neovimPackages = {
          local = localNeovim final."neovim-main-unwrapped";
          main = final."neovim-main-unwrapped";
          nightly = prev.neovim;
        };
      in
      {
        barrett-fonts = inputs.fonts.packages.${system}.desktop;
        barrett-webfonts = inputs.fonts.packages.${system}.web;
        delta-software-sync = final.callPackage ../pkgs/delta-software-sync { };
        delta-cli = inputs.delta.packages.${system}.cli;
        direnv-instant = inputs.direnv-instant.packages.${system}.direnv-instant.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ../pkgs/direnv-instant-mux-nvim.patch ];
        });
        google-workspace-cli = inputs.googleworkspace-cli.packages.${system}.default;
        google-workspace-guard = final.callPackage ../pkgs/google-workspace-guard {
          gws = final.google-workspace-cli;
        };
        neovim = final.callPackage ../pkgs/neovim {
          neovimPackage = neovimPackages.${neovimChannel};
        };
      }
    )
  ];

  sharedUnfree = [
    "slack"
    "apple_cursor"
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
        inherit (pkgs)
          barrett-fonts
          barrett-webfonts
          delta-software-sync
          neovim
          ;
      };
    };
}
