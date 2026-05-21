default:
    @just --list

_python-scripts:
    @git ls-files 'scripts/**' | while IFS= read -r file; do \
        [ -f "$file" ] || continue; \
        shebang=$(sed -n '1p' "$file"); \
        case "$shebang" in \
            "#!"*python*) printf '%s\n' "$file" ;; \
        esac; \
    done

_shell-scripts:
    @git ls-files 'scripts/**' | while IFS= read -r file; do \
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
