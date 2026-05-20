default:
    @just --list

format:
    nix fmt -- --ci
    shfmt -i 2 -d scripts/*

lint:
    git ls-files '*.nix' | xargs deadnix --fail --no-lambda-pattern-names
    lua-language-server --check config/nvim --configpath "$(pwd)/config/nvim/.luarc.json" --checklevel=Warning
    shellcheck scripts/*

ci: format lint
    @:
