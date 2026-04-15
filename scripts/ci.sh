#!/bin/sh
set -eu

nix fmt
git diff --exit-code -- '*.nix'
nix develop --command deadnix --fail --no-lambda-pattern-names -- **/*.nix
nix develop --command statix check

nix develop --command stylua --check config/nvim
git ls-files '*.lua' | xargs nix develop --command selene --display-style quiet --config config/nvim/selene.toml

nix develop --command shfmt -i 2 -d scripts/

nix develop --command prettier --check .
