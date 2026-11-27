#!/usr/bin/env bash
# Prepare or push a review branch containing ONLY signed public support metadata.
# Uses the maintainer's existing Git authentication; never reads the signing key.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 2 && ( "$1" == --check || "$1" == --push-review ) ]] || {
    echo "Usage: $0 --check|--push-review PUBLIC_RELEASE_DIRECTORY" >&2
    exit 2
}
mode="$1"
release="$(cd "$2" && pwd -P)"
for file in trust.json steam-seed.json; do
    [[ -f "$release/$file" && ! -L "$release/$file" ]]
done
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir "$temp/public"
cp "$release/trust.json" "$release/steam-seed.json" "$temp/public/"
git clone --quiet --depth=1 --single-branch --branch support-catalog \
    https://github.com/enoswong/GameBridge.git "$temp/catalog"
python3 - "$temp/public" "$temp/catalog/mobile" "$temp/payload.json" <<'PY'
import base64, hashlib, json, pathlib, sys
public, old, target = map(pathlib.Path, sys.argv[1:])
def read(path, maximum):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise ValueError("Invalid metadata file")
    return json.loads(path.read_bytes())
trust = read(public / "trust.json", 4096)
if set(trust) != {"keyID", "publicKey"}:
    raise ValueError("Unexpected public trust fields")
key = base64.b64decode(trust["publicKey"], validate=True)
if len(key) != 32 or hashlib.sha256(key).hexdigest()[:16] != trust["keyID"]:
    raise ValueError("Public key identity mismatch")
envelope = read(public / "steam-seed.json", 65536)
if set(envelope) != {"keyID", "payload", "signature"}:
    raise ValueError("Unexpected envelope fields")
payload = base64.b64decode(envelope["payload"], validate=True)
revision = json.loads(payload)["revision"]
if type(revision) is not int or not 0 < revision <= 2**63 - 1:
    raise ValueError("Invalid revision")
exists = [(old / name).exists() or (old / name).is_symlink()
          for name in ("trust.json", "steam-seed.json")]
if any(exists):
    if not all(exists):
        raise ValueError("Incomplete published metadata")
    if read(old / "trust.json", 4096) != trust:
        raise ValueError("Refusing a trust key change")
    previous = base64.b64decode(read(old / "steam-seed.json", 65536)["payload"], validate=True)
    old_revision = json.loads(previous)["revision"]
    if revision <= old_revision:
        raise ValueError("Review release must increase the published revision")
target.write_bytes(payload)
print("Proposed public catalog revision:", revision)
PY
keyid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["keyID"])' "$temp/public/trust.json")"
pub="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["publicKey"])' "$temp/public/trust.json")"
revision="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision"])' "$temp/payload.json")"
swiftc -parse-as-library "$root/WhiskyKit/Sources/GameBridgeCore/MobileSupportCatalog.swift" \
    "$root/scripts/mobile-support-signer.swift" -o "$temp/signer"
"$temp/signer" verify "$keyid" "$pub" "$temp/public/steam-seed.json"
python3 "$root/scripts/diagnose-mobile-steam.py" --catalog-payload "$temp/payload.json"
if [[ "$mode" == --check ]]; then
    echo "Publication preflight passed. No remote changes."
    exit 0
fi
branch="support-publish/revision-$revision"
cd "$temp/catalog"
git switch -c "$branch"
mkdir -p mobile
cp "$temp/public/trust.json" "$temp/public/steam-seed.json" mobile/
git add -- mobile/trust.json mobile/steam-seed.json
git diff --cached --stat
git commit -m "Publish signed mobile support catalog revision $revision"
# Never force-push or write directly to the live support-catalog branch.
git push origin "HEAD:refs/heads/$branch"
echo "Review PR: https://github.com/enoswong/GameBridge/compare/support-catalog...$branch?expand=1"
echo "The live catalog has not been changed. Merge only after publication validation passes."
