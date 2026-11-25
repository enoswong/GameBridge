#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare an isolated research checkout; never package the internal Mac runtime.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream="https://github.com/willfaust/Madeira.git"
revision="fbad430410b4075192166172447c859714726de9"
mode="${1:---prepare}"
case "$mode" in
    --prepare|--build) research_ui=0 ;;
    --steam-first-prepare|--steam-first-build) research_ui=1 ;;
    *) echo "Usage: $0 [--prepare|--build|--steam-first-prepare|--steam-first-build]" >&2; exit 2 ;;
esac
patches=(
    "$root/mobile/patches/0001-steam-first-research.patch"
    "$root/mobile/patches/0002-bootstrap-and-identity.patch"
    "$root/mobile/patches/0003-runtime-preparation.patch"
)
workspace="$root/build/mobile-research/madeira-$revision"
if [[ "$research_ui" == 1 ]]; then
    overlay="$(cat "${patches[@]}" | git hash-object --stdin)"
    workspace="$workspace-steam-first-$overlay"
fi
if [[ "$mode" == *build ]]; then
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
git -C "$workspace" diff --cached --quiet HEAD --
if [[ "$research_ui" == 1 ]]; then
    # Validate the complete intended working tree against a temporary index.
    # Never overwrite a developer's modifications or reuse a dirty checkout.
    index="$(mktemp)"
    rm -f "$index"
    trap 'rm -f "$index" "$index.lock"' EXIT
    GIT_INDEX_FILE="$index" git -C "$workspace" read-tree HEAD
    GIT_INDEX_FILE="$index" git -C "$workspace" apply --cached "${patches[@]}"
    if git -C "$workspace" diff --quiet HEAD --; then
        git -C "$workspace" apply --check "${patches[@]}"
        git -C "$workspace" apply "${patches[@]}"
    fi
    GIT_INDEX_FILE="$index" git -C "$workspace" diff --quiet --ignore-submodules=all --
    for name in RuntimeDependencyPolicy PortableWindowsImportReader PortableLegacyGameAudit SteamDirectoryAudit; do
        cmp "$root/WhiskyKit/Sources/GameBridgeCore/$name.swift" "$workspace/app/Madeira/$name.swift"
    done
else
    git -C "$workspace" diff --quiet HEAD --
fi
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
if [[ "$mode" == *build ]]; then
    printf 'Building mobile research IPA (not a GameBridge release).\n'
    # The upstream CI path assumes separate native/i386 cache jobs. Run the full
    # local-source path on our isolated runner instead, including i386.
    (cd "$workspace" && env -u GITHUB_ACTIONS -u MADEIRA_RUNTIME_REUSE -u MADEIRA_RUNTIME_SDK \
        JOBS="${JOBS:-3}" bash tools/build-ipa.sh)
    if [[ "$research_ui" == 1 ]]; then
        python3 "$root/scripts/verify-mobile-research-ipa.py" "$workspace/dist/Madeira.ipa"
    fi
fi
