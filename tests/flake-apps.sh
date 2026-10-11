#!/usr/bin/env bash
set -euo pipefail
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
nix build --no-update-lock-file --no-link "$source_root#default"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
unset LD_LIBRARY_PATH
for app in default domainHunt; do
  nix run --no-update-lock-file "$source_root#$app" -- --help >"$app.txt"
  grep -q webSocketAddr "$app.txt"
done
echo 'installed default and domainHunt flake entrypoints PASS'
