default:
    @just --list

format:
    nix fmt -- --ci
    stylua --check config/nvim
    shfmt -i 2 -d scripts/
    git ls-files -- '*.json' '*.jsonc' '*.js' '*.mjs' '*.cjs' '*.ts' '*.tsx' '*.css' '*.html' '*.graphql' '*.gql' | sed '/\.min\.js$/d' | xargs --no-run-if-empty biome ci

lint:
    git ls-files '*.nix' | xargs deadnix --fail --no-lambda-pattern-names
    statix check .
    git ls-files '*.lua' | xargs selene --display-style quiet --config config/nvim/selene.toml
