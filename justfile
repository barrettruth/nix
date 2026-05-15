default:
    @just --list

format:
    nix fmt -- --ci

lint:
    git ls-files '*.nix' | xargs deadnix --fail --no-lambda-pattern-names
    lua-language-server --check config/nvim --configpath "$(pwd)/.luarc.json" --checklevel=Warning

ci: format lint
    @:
