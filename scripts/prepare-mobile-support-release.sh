#!/usr/bin/env bash
# Prepare public catalog metadata locally; never push or upload a private key.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# != 2 ]]; then
    echo "Usage: $0 REVIEWED_PAYLOAD.json NEW_OUTPUT_DIRECTORY" >&2
    exit 2
fi
payload="$1"
out="$2"
keydir="$HOME/.gamebridge-support"
key="$keydir/ed25519.key"
[[ -f "$payload" && ! -L "$payload" && ! -e "$out" && ! -L "$out" ]]
[[ -d "$keydir" && ! -L "$keydir" && -f "$key" && ! -L "$key" ]] || {
    echo "Create the maintainer key once using the documented offline signer init-key command." >&2
    exit 1
}
[[ "$(stat -f '%Lp' "$keydir")" == 700 && "$(stat -f '%Lp' "$key")" == 600 ]] || {
    echo "Require private key directory 0700 and key 0600." >&2
    exit 1
}
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
swiftc -parse-as-library "$root/WhiskyKit/Sources/GameBridgeCore/MobileSupportCatalog.swift" \
    "$root/scripts/mobile-support-signer.swift" -o "$temp/signer"
# Freeze exact input bytes before the archive check and signature.
cp "$payload" "$temp/payload.json"
python3 "$root/scripts/diagnose-mobile-steam.py" --catalog-payload "$temp/payload.json"
"$temp/signer" sign "$key" "$temp/payload.json" "$temp/steam-seed.json"
"$temp/signer" public-key "$key" > "$temp/trust.json"
keyid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["keyID"])' "$temp/trust.json")"
pub="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["publicKey"])' "$temp/trust.json")"
"$temp/signer" verify "$keyid" "$pub" "$temp/steam-seed.json"
mkdir "$out"
cp "$temp/steam-seed.json" "$temp/trust.json" "$out/"
printf 'Prepared public files only in %s\n' "$out"
printf 'GAMEBRIDGE_SUPPORT_KEY_ID=%s\nGAMEBRIDGE_SUPPORT_PUBLIC_KEY=%s\n' "$keyid" "$pub"
echo "Review against the current published revision before committing to support-catalog."
