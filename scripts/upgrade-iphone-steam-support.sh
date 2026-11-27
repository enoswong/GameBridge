#!/usr/bin/env bash
# Update the device workspace from the signed support-v1 Swift overlay.
# Native libraries, signing and the device's data are never reset here.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 1 || $# == 2 ]] || { echo "Usage: $0 MADEIRA_WORKSPACE [support-v1|language-v1|native-v1]" >&2; exit 2; }
baseline="${2:-support-v1}"
[[ "$baseline" == support-v1 || "$baseline" == language-v1 || "$baseline" == native-v1 ]]
workspace="$(cd "$1" && pwd -P)"
bash "$root/scripts/update-existing-iphone-project.sh" --check "$workspace" "$baseline"
bash "$root/scripts/fix-iphone-wow64-opengl.sh" --check "$workspace"
grep -Fq 'TEB32 *teb32_ptr = ios_wow_host_ptr( teb32 );' "$workspace/wine/dlls/opengl32/unix_private.h" || {
    echo "Previous native OpenGL correction is not applied; stop and rebuild it first." >&2; exit 1;
}
bash "$root/scripts/prepare-mobile-cjk-fonts.sh" "$workspace"
bash "$root/scripts/stage-mobile-native-probe.sh" "$workspace"
bash "$root/scripts/update-existing-iphone-project.sh" --apply "$workspace" "$baseline"
echo "Language resources and source update ready. Existing native OpenGL library retained."
echo "Open $workspace/app/Madeira.xcodeproj and build for the existing iPhone identity without LLDB."
