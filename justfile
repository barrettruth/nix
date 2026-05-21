default:
    @just --list

format:
    nix fmt -- --ci
    git ls-files 'scripts/**' ':!:scripts/mux.py' ':!:scripts/spark' | xargs -r shfmt -i 2 -d
    black --check scripts/spark scripts/*.py

lint:
    git ls-files '*.nix' | xargs deadnix --fail --no-lambda-pattern-names
    lua-language-server --check config/nvim --configpath "$(pwd)/config/nvim/.luarc.json" --checklevel=Warning
    git ls-files 'scripts/**' ':!:scripts/mux.py' ':!:scripts/spark' | xargs -r shellcheck
    ty check scripts/spark scripts/*.py

ci: format lint
    @:
