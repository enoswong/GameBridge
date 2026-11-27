#!/usr/bin/env bash
# Experimental FEX correction; never run automatically on a stable device build.
set -euo pipefail
[[ $# == 2 && ( "$1" == --check || "$1" == --rebuild ) ]] || {
    echo "Usage: $0 --check|--rebuild MADEIRA_WORKSPACE" >&2; exit 2;
}
root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(cd "$2" && pwd -P)"
fex="$workspace/FEX"
relative=FEXCore/include/FEXCore/Utils/AllocatorHooks.h
header="$fex/$relative"
patch="$root/mobile/fex-experiments/0001-win32-virtual-protect-contract.patch"
[[ "$(git -C "$workspace" rev-parse HEAD)" == fbad430410b4075192166172447c859714726de9 ]]
[[ "$(git -C "$fex" rev-parse HEAD)" == 1dc6ed4932bd231df1c53dd7b8043ffdee0ac34a ]]
[[ -f "$header" && ! -L "$header" ]]
git -C "$fex" diff --cached --quiet HEAD -- "$relative"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/$(dirname "$relative")"
git -C "$fex" show "HEAD:$relative" > "$temp/original"
cp "$temp/original" "$temp/$relative"
(cd "$temp" && git apply --check "$patch" && git apply "$patch")
if ! cmp -s "$header" "$temp/original" && ! cmp -s "$header" "$temp/$relative"; then
    echo "Other local changes to the FEX protection header; refusing overwrite." >&2
    exit 1
fi
python3 "$root/scripts/test-fex-virtual-protect.py" "$temp/$relative"
[[ "$1" == --rebuild ]] || { echo "Pinned FEX protection experiment preflight passed."; exit 0; }
[[ "$(uname -s)" == Darwin ]]
arm64ec="$workspace/app/Madeira/arm64ec-windows/xtajit64.dll"
wow64="$workspace/app/Madeira/aarch64-windows/xtajit.dll"
for dll in "$arm64ec" "$wow64"; do [[ -s "$dll" && ! -L "$dll" ]]; done
backup="$(mktemp -d "$HOME/GameBridge-fex-protect-backup.XXXXXXXX")"
cp -p "$header" "$backup/AllocatorHooks.h"
cp -p "$arm64ec" "$backup/xtajit64.dll"
cp -p "$wow64" "$backup/xtajit.dll"
restore=1
cleanup() {
    if [[ "$restore" == 1 ]]; then
        cp -p "$backup/AllocatorHooks.h" "$header"
        # Force a future incremental build to observe the restored source timestamp.
        touch "$header"
        cp -p "$backup/xtajit64.dll" "$arm64ec"
        cp -p "$backup/xtajit.dll" "$wow64"
        echo "Previous FEX modules and header restored." >&2
    fi
    rm -rf "$temp"
}
trap cleanup EXIT
if cmp -s "$header" "$temp/original"; then git -C "$fex" apply "$patch"; fi
cmp "$header" "$temp/$relative"
bash "$workspace/build/fex-arm64ec/build.sh" 2>&1 | tee "$backup/arm64ec.log"
bash "$workspace/build/fex-wow64/build.sh" 2>&1 | tee "$backup/wow64.log"
python3 - "$arm64ec" "$wow64" <<'PY'
import pathlib, struct, sys
for filename, allowed in zip(sys.argv[1:], ({0xa641, 0x8664}, {0xaa64})):
    data = pathlib.Path(filename).read_bytes()
    assert data[:2] == b'MZ', filename
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[offset:offset+4] == b'PE\0\0', filename
    assert struct.unpack_from('<H', data, offset+4)[0] in allowed, filename
PY
restore=0
echo "Experimental modules rebuilt; backup: $backup"
echo "This is not device validation. Rebuild the existing signed app in Xcode and test separately."
