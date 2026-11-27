#!/usr/bin/env bash
# Prepare a new signed revision from the last published, authenticated envelope.
# No automatic publication, no private key sent to GitHub.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 2 ]] || { echo "Usage: $0 PREVIOUS_PUBLISHED_ENVELOPE NEW_OUTPUT_DIRECTORY" >&2; exit 2; }
previous="$1"
out="$2"
keydir="$HOME/.gamebridge-support"
key="$keydir/ed25519.key"
[[ -f "$previous" && ! -L "$previous" && ! -e "$out" && ! -L "$out" ]]
[[ -d "$keydir" && ! -L "$keydir" && -f "$key" && ! -L "$key" ]]
[[ "$(stat -f '%Lp' "$keydir")" == 700 && "$(stat -f '%Lp' "$key")" == 600 ]]
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
swiftc -parse-as-library "$root/WhiskyKit/Sources/GameBridgeCore/MobileSupportCatalog.swift" \
    "$root/scripts/mobile-support-signer.swift" -o "$temp/signer"
"$temp/signer" renew-payload "$key" "$previous" "$temp/renewal.json"
bash "$root/scripts/prepare-mobile-support-release.sh" "$temp/renewal.json" "$out"
echo "Review previous published revision before opening a support-catalog PR."
