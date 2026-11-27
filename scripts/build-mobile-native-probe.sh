#!/usr/bin/env bash
# Build the repository's standalone probe; no Steam, network or CRT required.
set -euo pipefail
[[ $# == 1 || $# == 2 ]] || { echo "Usage: $0 OUTPUT_DIRECTORY [MINGW_COMPILER]" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$1"
out="$(cd "$1" && pwd -P)"
source="$root/tests/mobile/native-smoke-x64.c"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
name=GameBridge-native-smoke-x64.exe
if [[ $# == 2 ]]; then
    "$2" -O2 -ffreestanding -fno-stack-protector -nostdlib -Wl,-e,mainCRTStartup -mwindows \
        "$source" -lkernel32 -luser32 -o "$temp/$name"
else
    printf 'LIBRARY KERNEL32.dll\nEXPORTS\nExitProcess\nLoadLibraryW\nGetProcAddress\n' > "$temp/kernel32.def"
    printf 'LIBRARY USER32.dll\nEXPORTS\nMessageBoxW\n' > "$temp/user32.def"
    lld-link /lib /machine:x64 "/def:$temp/kernel32.def" "/out:$temp/kernel32.lib"
    lld-link /lib /machine:x64 "/def:$temp/user32.def" "/out:$temp/user32.lib"
    clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-stack-protector -c "$source" -o "$temp/probe.obj"
    lld-link /machine:x64 /subsystem:windows /entry:mainCRTStartup /nodefaultlib /timestamp:0 \
        "/out:$temp/$name" "$temp/probe.obj" "$temp/kernel32.lib" "$temp/user32.lib"
fi
[[ ! -L "$out/$name" ]] || { echo 'Refusing linked output' >&2; exit 1; }
cp "$temp/$name" "$out/$name"
echo "Built standalone native probe: $out/$name"
