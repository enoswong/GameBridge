#!/usr/bin/env bash
# Update only the original built research workspace's reviewed app source overlay.
# No engine rebuild, no reset, no signing changes, no automatic installation.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base=6787eca8cad63d916ffd9e989a99432da93c6064
upstream=fbad430410b4075192166172447c859714726de9
[[ ( $# == 2 || $# == 3 ) && ( "$1" == --check || "$1" == --apply ) ]] || {
    echo "Usage: $0 --check|--apply EXISTING_MADEIRA_WORKSPACE [original|support-v1|language-v1]" >&2
    exit 2
}
mode="$1"
case "${3:-original}" in
    original) ;;
    support-v1) base=1bfd71316184ffddb23a763fdad9772e398dc988 ;;
    language-v1) base=ec9932bc14465eafa5039641d84fd3e6eeba5681 ;;
    *) echo "Unsupported installed overlay baseline" >&2; exit 2 ;;
esac
if ! git -C "$root" cat-file -e "$base^{commit}"; then
    echo "Missing source baseline $base; fetch the development branch history first." >&2
    exit 1
fi
workspace="$(cd "$2" && pwd -P)"
[[ "$(git -C "$workspace" rev-parse HEAD)" == "$upstream" ]]
[[ "$(git -C "$workspace" remote get-url origin)" == https://github.com/willfaust/Madeira.git ]]
git -C "$workspace" diff --cached --quiet HEAD --
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
patches=(0001-steam-first-research.patch 0002-bootstrap-and-identity.patch 0003-runtime-preparation.patch)
for patch in "${patches[@]}"; do
    git -C "$root" show "$base:mobile/patches/$patch" > "$temp/$patch"
done
tree() {
    local idx="$1"
    shift
    GIT_INDEX_FILE="$idx" git -C "$workspace" read-tree "$upstream"
    GIT_INDEX_FILE="$idx" git -C "$workspace" apply --cached "$@"
    GIT_INDEX_FILE="$idx" git -C "$workspace" write-tree
}
old="$(tree "$temp/old.index" "${patches[@]/#/$temp/}")"
new="$(tree "$temp/new.index" "${patches[@]/#/$root/mobile/patches/}")"
git -C "$workspace" diff --name-status "$old" "$new" > "$temp/changes"
# Keep the helper restricted to text-only changes. New engine or entitlement changes need a real build.
while IFS=$'\t' read -r status path; do
    [[ -z "$status" ]] && continue
    [[ "$status" == A || "$status" == M ]] || { echo "Unsupported delta: $status" >&2; exit 1; }
    case "$path" in
        app/Madeira/*.swift|app/Madeira/Info.plist|app/Madeira.xcodeproj/project.pbxproj) ;;
        *) echo "Unsupported source update: $path" >&2; exit 1 ;;
    esac
    if [[ -L "$workspace/$path" ]]; then echo "Linked source: $path" >&2; exit 1; fi
done < "$temp/changes"
git -C "$workspace" diff --binary --no-renames "$old" "$new" > "$temp/update.patch"
[[ -s "$temp/update.patch" ]] || { echo "No source delta."; exit 0; }
# Apply only if original context still matches. Preserve unrelated local signing edits.
if ! git -C "$workspace" apply --check "$temp/update.patch"; then
    echo "Local source conflicts or overlay already updated. No source files changed." >&2
    exit 1
fi
cat "$temp/changes"
if [[ "$mode" == --check ]]; then
    echo "Source update preflight passed. Close Xcode before --apply."
    exit 0
fi
backup="$(mktemp -d "$HOME/GameBridge-source-backup.XXXXXXXX")"
while IFS=$'\t' read -r status path; do
    [[ "$status" == M ]] || continue
    mkdir -p "$backup/$(dirname "$path")"
    cp -p "$workspace/$path" "$backup/$path"
done < "$temp/changes"
cp "$temp/changes" "$temp/update.patch" "$backup/"
git -C "$workspace" apply "$temp/update.patch"
echo "Source update applied. Backup: $backup"
echo "Reopen this same Xcode project and build for the physical iPhone."
echo "Native runtime artifacts and signing entitlements were not changed."
echo "Do not run the full prepare script against this manually migrated workspace."
