default:
    @just --list

rebuild-desktop:
    nixos-rebuild switch --no-reexec --flake .#desktop --target-host desktop --build-host desktop

rebuild-laptop:
    @if [ "$(id -u)" -eq 0 ]; then printf '%s\n' 'rebuild-laptop must run unprivileged; sudo is only for activation.' >&2; exit 1; fi
    nixos-rebuild switch --no-reexec --flake .#laptop --build-host desktop-builder --elevate sudo --ask-elevate-password

rebuild-mac: (_rebuild-darwin "mac")

rebuild-imc: (_rebuild-darwin "imc")

_rebuild-darwin host:
    @if [ "$(id -u)" -eq 0 ]; then printf '%s\n' 'rebuild must run unprivileged; sudo is only for activation.' >&2; exit 1; fi
    @export NIX_CONFIG="extra-experimental-features = nix-command flakes"; \
      expected=$(nix eval --raw '.#darwinConfigurations.{{ host }}.config.barrett.user.name') && \
      if [ "$expected" != "$(id -un)" ]; then \
        printf '%s\n' "{{ host }} is configured for user $expected, but this machine is $(id -un)." >&2; \
        exit 1; \
      fi && \
      system=$(nix build --no-link --print-out-paths '.#darwinConfigurations.{{ host }}.system') && \
      sudo -H nix-env --profile /nix/var/nix/profiles/system --set "$system" && \
      sudo -H /nix/var/nix/profiles/system/activate

rebuild-vps:
    @export NIX_SSHOPTS="-o ControlMaster=auto -o ControlPath=/tmp/nixos-rebuild-vps-%C -o ControlPersist=180 -o ConnectTimeout=20 -o ServerAliveInterval=15"; \
    if command -v nixos-rebuild >/dev/null 2>&1; then \
      nixos-rebuild switch --no-reexec --flake .#vps --target-host vps --build-host vps; \
    else \
      nix run nixpkgs#nixos-rebuild -- switch --no-reexec --flake .#vps --target-host vps --build-host vps; \
    fi

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
    stylua --check config/nvim

lint:
    git ls-files '*.nix' | xargs deadnix --fail --no-lambda-pattern-names
    lua-language-server --check config/nvim --configpath "$(pwd)/config/nvim/.luarc.json" --checklevel=Warning
    just _shell-scripts | xargs -r shellcheck
    just _python-scripts | xargs -r ty check
    just _python-scripts | xargs -r basedpyright --pythonversion 3.11

ci: format lint
    @:
