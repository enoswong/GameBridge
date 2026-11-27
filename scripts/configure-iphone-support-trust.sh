#!/usr/bin/env bash
# Embed an already verified public support identity into the local research project.
# Never read the private key, edit the entitlement file or change Apple signing.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 3 && ( "$1" == --check || "$1" == --apply ) ]] || {
    echo "Usage: $0 --check|--apply EXISTING_MADEIRA_WORKSPACE PUBLIC_RELEASE_DIRECTORY" >&2
    exit 2
}
mode="$1"
workspace="$(cd "$2" && pwd -P)"
release="$(cd "$3" && pwd -P)"
plist="$workspace/app/Madeira/Info.plist"
[[ "$(git -C "$workspace" rev-parse HEAD)" == fbad430410b4075192166172447c859714726de9 ]]
[[ "$(git -C "$workspace" remote get-url origin)" == https://github.com/willfaust/Madeira.git ]]
[[ -f "$plist" && ! -L "$plist" ]]
for name in trust.json steam-seed.json; do
    [[ -f "$release/$name" && ! -L "$release/$name" ]]
done
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
cp "$release/trust.json" "$release/steam-seed.json" "$temp/"
python3 - "$temp/trust.json" "$temp/steam-seed.json" <<'PY'
import base64, hashlib, json, pathlib, sys
trust_path, envelope_path = map(pathlib.Path, sys.argv[1:])
if trust_path.stat().st_size > 4096 or envelope_path.stat().st_size > 65536:
    raise ValueError("Support metadata exceeds size limit")
trust = json.loads(trust_path.read_bytes())
if set(trust) != {"keyID", "publicKey"}:
    raise ValueError("Unexpected trust fields")
key = base64.b64decode(trust["publicKey"], validate=True)
if len(key) != 32 or hashlib.sha256(key).hexdigest()[:16] != trust["keyID"]:
    raise ValueError("Public key identity mismatch")
PY
keyid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["keyID"])' "$temp/trust.json")"
pub="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["publicKey"])' "$temp/trust.json")"
swiftc -parse-as-library "$root/WhiskyKit/Sources/GameBridgeCore/MobileSupportCatalog.swift" \
    "$root/scripts/mobile-support-signer.swift" -o "$temp/signer"
"$temp/signer" verify "$keyid" "$pub" "$temp/steam-seed.json"
# Refuse if the required support overlay is absent or another key is embedded.
python3 - "$plist" "$keyid" "$pub" "$mode" <<'PY'
import os, pathlib, plistlib, re, stat, sys, tempfile
path = pathlib.Path(sys.argv[1])
keyid, pub, mode = sys.argv[2:]
source = path.read_bytes()
parsed = plistlib.loads(source)
if parsed.get("CFBundleDisplayName") != "GameBridge Research":
    raise ValueError("Not a GameBridge research project")
entries = {
    "GameBridgeSupportKeyID": ("$(GAMEBRIDGE_SUPPORT_KEY_ID)", keyid),
    "GameBridgeSupportPublicKey": ("$(GAMEBRIDGE_SUPPORT_PUBLIC_KEY)", pub),
}
updated = source
for name, (placeholder, value) in entries.items():
    old = parsed.get(name)
    if old == value:
        continue
    if old != placeholder:
        raise ValueError("Support overlay missing or different key already configured: " + name)
    pattern = rb"(<key>" + name.encode() + rb"</key>\s*<string>)" + re.escape(placeholder.encode()) + rb"(</string>)"
    updated, count = re.subn(pattern, lambda m: m[1] + value.encode() + m[2], updated)
    if count != 1:
        raise ValueError("Unexpected plist representation: " + name)
expected = dict(parsed)
for name, (_, value) in entries.items():
    expected[name] = value
if plistlib.loads(updated) != expected:
    raise ValueError("Unexpected plist changes")
if updated == source:
    print("The same verified public key is already embedded.")
    sys.exit(0)
if mode == "--check":
    print("Trust embedding preflight passed. Close Xcode before applying.")
    sys.exit(0)
# Atomic file replacement; retain original plist in an exclusive local backup.
backup_dir = pathlib.Path(tempfile.mkdtemp(prefix="GameBridge-trust-backup.", dir=pathlib.Path.home()))
(backup_dir / "Info.plist").write_bytes(source)
fd, temp = tempfile.mkstemp(prefix=".gamebridge-trust-", dir=path.parent)
try:
    with os.fdopen(fd, "wb") as out:
        os.fchmod(out.fileno(), stat.S_IMODE(path.stat().st_mode))
        out.write(updated)
        out.flush()
        os.fsync(out.fileno())
    if path.is_symlink() or path.read_bytes() != source:
        raise ValueError("Plist changed during operation")
    os.replace(temp, path)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
print("Verified public trust embedded. Backup:", backup_dir)
PY
echo "No private key, Apple signing setting or engine artifact was changed."
echo "A native app rebuild/re-sign is required once; catalog publication is separate."
