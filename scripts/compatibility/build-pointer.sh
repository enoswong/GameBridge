#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
compatibility_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$compatibility_dir/../.." && pwd)
output_dir=${1:-"$project_dir/build/compatibility"}
compiler=${MINGW_CC:-x86_64-w64-mingw32-gcc}
mkdir -p "$output_dir"
"$compiler" -O2 -Wall -Wextra -Werror -Wno-cast-function-type \
  -shared -nostdlib -fno-builtin -Wl,--entry,DllMain,--no-insert-timestamp \
  "$compatibility_dir/deskrawl-pointer.c" "$compatibility_dir/deskrawl-version.c" \
  "$compatibility_dir/deskrawl-version.def" -o "$output_dir/version.dll" \
  -luser32 -lkernel32
shasum -a 256 "$output_dir/version.dll"
