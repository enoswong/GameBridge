#!/usr/bin/env bash
# Build the local diagnostic from reviewed source using the pinned upstream toolchain.
set -euo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 MADEIRA_WORKSPACE" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(cd "$1" && pwd -P)"
[[ "$(git -C "$workspace" rev-parse HEAD)" == fbad430410b4075192166172447c859714726de9 ]]
compiler="$workspace/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin/x86_64-w64-mingw32-clang"
if [[ ! -x "$compiler" ]]; then
    [[ "$(uname -s)" == Darwin ]] || { echo "Pinned macOS toolchain required." >&2; exit 1; }
    ROOT="$workspace" bash "$workspace/tools/build/setup-llvm-mingw.sh"
fi
[[ -x "$compiler" ]]
destination="$workspace/app/Madeira/gamebridge-probes"
[[ ! -L "$destination" ]]
bash "$root/scripts/build-mobile-native-probe.sh" "$destination" "$compiler"
test -s "$destination/GameBridge-native-smoke-x64.exe"
