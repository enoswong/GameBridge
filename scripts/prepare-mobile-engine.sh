#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare an isolated research checkout; never package the internal Mac runtime.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream="https://github.com/willfaust/Madeira.git"
revision="fbad430410b4075192166172447c859714726de9"
workspace="$root/build/mobile-research/madeira-$revision"
mode="${1:---prepare}"
if [[ "$mode" != "--prepare" && "$mode" != "--build" ]]; then
    echo "Usage: bash scripts/prepare-mobile-engine.sh [--prepare|--build]" >&2
    exit 2
fi
if [[ "$mode" == "--build" ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || { echo "Xcode on macOS is required." >&2; exit 1; }
    command -v xcodebuild >/dev/null
    command -v brew >/dev/null
fi
# A build is never executed by default; it may install upstream build dependencies.
if [[ ! -e "$workspace" ]]; then
    mkdir -p "$(dirname "$workspace")"
    git init "$workspace"
    git -C "$workspace" remote add origin "$upstream"
    git -C "$workspace" fetch --depth=1 origin "$revision"
    git -C "$workspace" checkout --detach FETCH_HEAD
fi
[[ ! -L "$workspace" && -d "$workspace/.git" ]]
[[ "$(git -C "$workspace" remote get-url origin)" == "$upstream" ]]
[[ "$(git -C "$workspace" rev-parse HEAD)" == "$revision" ]]
git -C "$workspace" diff --quiet HEAD --
git -C "$workspace" diff --cached --quiet HEAD --
# This route is Valve's desktop executable, not Madeira Dock's headless launcher.
source_file="$workspace/app/Madeira/ContentView.swift"
grep -Fq 'Button("Steam Testing")' "$source_file"
grep -Fq 'private func prepareSteamLaunch() -> Bool' "$source_file"
grep -Fq 'steam.exe' "$source_file"
for component in FEX wine dxmt madeira-dock; do
    entry="$(git -C "$workspace" ls-tree HEAD "$component")"
    [[ "$entry" == 160000* ]] || { echo "Missing gitlink: $component" >&2; exit 1; }
    printf '%s\n' "$entry"
done
git -C "$workspace" submodule update --init --recursive
# Refuse uninitialized or mismatched dependencies. Source availability can fail here.
status="$(git -C "$workspace" submodule status --recursive)"
printf '%s\n' "$status"
if grep -Eq '^[-+U]' <<< "$status"; then
    echo "Submodule source is missing or mismatched." >&2
    exit 1
fi
printf 'Pinned research checkout: %s\n' "$workspace"
if [[ "$mode" == "--build" ]]; then
    printf 'Building upstream research IPA (not a GameBridge release).\n'
    (cd "$workspace" && bash tools/build-ipa.sh)
fi
