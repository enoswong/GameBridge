#!/usr/bin/env bash
# One-time local trust provisioning; no Apple credentials or GitHub token requested.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keydir="$HOME/.gamebridge-support"
[[ "$(uname -s)" == Darwin ]] || { echo "Use the maintainer's Mac." >&2; exit 1; }
if [[ ! -e "$keydir" && ! -L "$keydir" ]]; then
    (umask 077; mkdir "$keydir")
fi
[[ -d "$keydir" && ! -L "$keydir" && "$(stat -f '%Lp' "$keydir")" == 700 ]]
key="$keydir/ed25519.key"
out="$keydir/release-1"
[[ ! -e "$out" && ! -L "$out" ]] || {
    echo "Initial public release already prepared: $out"
    echo "Do not regenerate the key or reuse revision 1 with different content."
    exit 1
}
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
if [[ ! -e "$key" && ! -L "$key" ]]; then
    swiftc -parse-as-library "$root/WhiskyKit/Sources/GameBridgeCore/MobileSupportCatalog.swift" \
        "$root/scripts/mobile-support-signer.swift" -o "$temp/signer"
    "$temp/signer" init-key "$key"
fi
python3 - "$root/mobile/support/steam-seed.template.json" "$temp/payload.json" <<'PY'
import json, pathlib, sys, time
payload = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
now = int(time.time())
payload.update(revision=1, issuedAt=now - 60, expiresAt=now + 30 * 86400)
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload, sort_keys=True))
PY
bash "$root/scripts/prepare-mobile-support-release.sh" "$temp/payload.json" "$out"
echo "Share ONLY $out/trust.json and $out/steam-seed.json for initial publication."
echo "Keep $key private. Never upload the key or the entire key directory."
