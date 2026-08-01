default:
    @just --list

rebuild-desktop:
    nixos-rebuild switch --no-reexec --flake .#desktop --target-host desktop --build-host desktop

rebuild-laptop:
    @if [ "$(id -u)" -eq 0 ]; then printf '%s\n' 'rebuild-laptop must run unprivileged; sudo is only for activation.' >&2; exit 1; fi
    nixos-rebuild switch --no-reexec --flake .#laptop --build-host desktop-builder --elevate sudo --ask-elevate-password

rebuild-mac:
    @if [ "$(id -u)" -eq 0 ]; then printf '%s\n' 'rebuild-mac must run unprivileged; sudo is only for activation.' >&2; exit 1; fi
    @system=$(nix build --no-link --print-out-paths '.#darwinConfigurations.mac.system') && \
      sudo nix-env --profile /nix/var/nix/profiles/system --set "$system" && \
      sudo /nix/var/nix/profiles/system/activate

_python-scripts:
   @git ls-files 'scripts/**' 'modules/**' | while IFS= read -r file; do \
        [ -f "$file" ] || continue; \
        shebang=$(sed -n '1p' "$file"); \
        case "$shebang" in \
            "#!"*python*) printf '%s\n' "$file" ;; \
        esac; \
    done

_shell-scripts:
    @git ls-files 'scripts/**' 'modules/**' | while IFS= read -r file; do \
        [ -f "$file" ] || continue; \
        shebang=$(sed -n '1p' "$file"); \
        case "$shebang" in \
            "#!"*python*) ;; \
            "#!"*) printf '%s\n' "$file" ;; \
        esac; \
    done

format:
    nix fmt -- --ci
    just _shell-scripts | xargs -r shfmt -i 2 -d
    just _python-scripts | xargs -r black --check

lint:
    git ls-files '*.nix' | xargs deadnix --fail --no-lambda-pattern-names
    lua-language-server --check config/nvim --configpath "$(pwd)/config/nvim/.luarc.json" --checklevel=Warning
    just _shell-scripts | xargs -r shellcheck
    just _python-scripts | xargs -r ty check
    just _python-scripts | xargs -r basedpyright --pythonversion 3.11

ci: format lint
    @:
