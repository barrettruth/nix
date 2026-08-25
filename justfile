default:
    @just --list

rebuild-desktop: (_rebuild-nixos "desktop" "--target-host" "desktop" "--build-host" "desktop")

rebuild-laptop: (_rebuild-nixos "laptop" "--build-host" "desktop-builder" "--elevate" "sudo" "--ask-elevate-password")

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

rebuild-vps: (_rebuild-nixos "vps" "--target-host" "vps" "--build-host" "vps")

_rebuild-nixos host +args:
    @if [ "$(id -u)" -eq 0 ]; then printf '%s\n' 'rebuild must run unprivileged; sudo is only for activation.' >&2; exit 1; fi
    @export NIX_CONFIG="extra-experimental-features = nix-command flakes"; \
      export NIX_SSHOPTS="-o ControlMaster=auto -o ControlPath=/tmp/nixos-rebuild-{{ host }}-%C -o ControlPersist=180 -o ConnectTimeout=20 -o ServerAliveInterval=15"; \
      if command -v nixos-rebuild >/dev/null 2>&1; then \
        nixos-rebuild switch --no-reexec --flake '.#{{ host }}' {{ args }}; \
      else \
        nix run nixpkgs#nixos-rebuild -- switch --no-reexec --flake '.#{{ host }}' {{ args }}; \
      fi

paths := "'scripts/**' 'modules/**' 'config/**' 'pkgs/**'"

lua_dirs := "config/nvim config/skills/_lib"

_python-scripts:
   @git ls-files {{ paths }} | while IFS= read -r file; do \
        [ -f "$file" ] || continue; \
        case "$file" in *.py) printf '%s\n' "$file"; continue ;; esac; \
        shebang=$(sed -n '1p' "$file"); \
        case "$shebang" in \
            "#!"*python*) printf '%s\n' "$file" ;; \
        esac; \
    done

_shell-scripts:
    @git ls-files {{ paths }} | while IFS= read -r file; do \
        [ -f "$file" ] || continue; \
        case "$file" in *.py) continue ;; esac; \
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
    stylua --check --config-path config/nvim/stylua.toml {{ lua_dirs }}
    git ls-files '*.md' | xargs -r prettier --check

lint:
    git ls-files '*.nix' | xargs deadnix --fail --no-lambda-pattern-names
    export VIMRUNTIME="$(nvim --clean --headless -c 'lua io.write(vim.env.VIMRUNTIME)' -c 'qa!')" && test -d "$VIMRUNTIME" && for dir in {{ lua_dirs }}; do lua-language-server --check "$dir" --configpath "$(pwd)/$dir/.luarc.json" --checklevel=Warning || exit 1; done
    just _shell-scripts | xargs -r shellcheck
    just _python-scripts | xargs -r ty check
    just _python-scripts | xargs -r basedpyright

ci: format lint
    @:
