#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Never use a live game prefix. All state lives below build/compatibility.
set -eu
compatibility_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$compatibility_dir/../.." && pwd)
output_dir="$project_dir/build/compatibility"
compiler=${MINGW_CC:-x86_64-w64-mingw32-gcc}
: "${WINE_BINARY:?Set WINE_BINARY to the absolute path of the supported Wine executable}"
"$compatibility_dir/build-pointer.sh" "$output_dir"
mkdir -p "$output_dir/test"
"$compiler" -Wall -Wextra -Werror "$compatibility_dir/deskrawl-pointer-test.c" \
  -o "$output_dir/test/Deskrawl.exe" -luser32 -lversion
cp "$output_dir/test/Deskrawl.exe" "$output_dir/test/Unrelated.exe"
cp "$output_dir/version.dll" "$output_dir/test/version.dll"
export WINEPREFIX="$output_dir/test-prefix"
export WINEDLLOVERRIDES='version=n,b' WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=0
"$WINE_BINARY" "$output_dir/test/Deskrawl.exe"
"$WINE_BINARY" "$output_dir/test/Deskrawl.exe" disabled
"$WINE_BINARY" "$output_dir/test/Unrelated.exe" inactive
# Rollback: removal of the game-local DLL restores the baseline Wine behavior.
mv "$output_dir/test/version.dll" "$output_dir/test/version.dll.disabled"
trap 'mv "$output_dir/test/version.dll.disabled" "$output_dir/test/version.dll"' EXIT HUP INT TERM
"$WINE_BINARY" "$output_dir/test/Deskrawl.exe" inactive
