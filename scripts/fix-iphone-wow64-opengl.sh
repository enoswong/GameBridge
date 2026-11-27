#!/usr/bin/env bash
# Apply the upstream TEB32 address-conversion correction only. No guest data changes.
set -euo pipefail
[[ $# == 2 && ( "$1" == --check || "$1" == --apply || "$1" == --rebuild ) ]] || {
    echo "Usage: $0 --check|--apply|--rebuild MADEIRA_WORKSPACE" >&2; exit 2;
}
mode="$1"
workspace="$(cd "$2" && pwd -P)"
wine="$workspace/wine"
relative=dlls/opengl32/unix_private.h
header="$wine/$relative"
[[ "$(git -C "$workspace" rev-parse HEAD)" == fbad430410b4075192166172447c859714726de9 ]]
[[ "$(git -C "$wine" rev-parse HEAD)" == ddf92babc5ba71f4586cc4713f5a8eb39f63d39b ]]
[[ -f "$header" && ! -L "$header" ]]
grep -Fq 'static inline void *ios_wow_host_ptr( ULONG addr )' "$wine/include/wine/unixlib.h"
python3 - "$mode" "$wine" "$relative" <<'PY'
import pathlib, subprocess, sys
mode, root, relative = sys.argv[1:]
path = pathlib.Path(root, relative)
baseline = subprocess.check_output(["git", "-C", root, "show", "HEAD:" + relative])
old = b"    TEB32 *teb32_ptr = ULongToPtr( teb32 );"
new = b"    TEB32 *teb32_ptr = ios_wow_host_ptr( teb32 );"
include = b'#include "wine/opengl_driver.h"'
assert baseline.count(old) == baseline.count(include) == 1, "Unexpected baseline"
expected = baseline.replace(old, new).replace(include, include + b'\n#include "wine/unixlib.h"')
current = path.read_bytes()
if current not in (baseline, expected):
    sys.exit("OpenGL header has other edits; refusing to overwrite them.")
if current == expected:
    print("WoW64 TEB address translation already patched.")
elif mode == "--check":
    print("Unpatched pinned OpenGL header; targeted fix is applicable.")
else:
    path.write_bytes(expected)
    print("Applied upstream TEB32 guest-to-host address correction.")
PY
[[ "$mode" == --rebuild ]] || exit 0
[[ "$(uname -s)" == Darwin ]]
command -v xcrun >/dev/null
lib="$workspace/app/Madeira/libntdll_unix.a"
[[ -f "$lib" && ! -L "$lib" && -f "$wine/build-macos/include/config.h" ]]
backup="$(mktemp -d "$HOME/GameBridge-native-backup.XXXXXXXX")"
cp -p "$lib" "$backup/libntdll_unix.a"
restore=1
trap 'if [[ "$restore" == 1 ]]; then cp -p "$backup/libntdll_unix.a" "$lib"; echo "Original library restored." >&2; fi' EXIT
# Upstream build can continue after a failed compile; require its explicit zero-failure summary.
bash "$workspace/build/ntdll-unix/build.sh" 2>&1 | tee "$backup/rebuild.log"
grep -Eq '^Results: [1-9][0-9]* succeeded, 0 failed$' "$backup/rebuild.log"
xcrun nm "$workspace/build/ntdll-unix/obj/opengl32_wgl.o" > "$backup/opengl-symbols.txt"
grep -q '_ios_wow_base' "$backup/opengl-symbols.txt"
restore=0
echo "Native library rebuilt. Backup and logs: $backup"
echo "Rebuild and install the existing Xcode app without the LLDB debugger attached."
