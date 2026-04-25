#!/bin/sh
set -eu

nix develop .#ci --command just format
nix develop .#ci --command just lint
