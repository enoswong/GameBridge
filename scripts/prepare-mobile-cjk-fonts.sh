#!/usr/bin/env bash
# Fetch OFL fonts from a pinned upstream commit; verify Git blob IDs before use.
set -euo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 MADEIRA_WORKSPACE" >&2; exit 2; }
workspace="$(cd "$1" && pwd -P)"
[[ "$(git -C "$workspace" rev-parse HEAD)" == fbad430410b4075192166172447c859714726de9 ]]
dest="$workspace/app/Madeira/fonts-ja"
[[ -d "$dest" && ! -L "$dest" ]]
revision=523d033d6cb47f4a80c58a35753646f5c3608a78
origin="https://raw.githubusercontent.com/notofonts/noto-cjk/$revision"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
fetch() {
    local source="$1" name="$2" expected="$3"
    if [[ -e "$dest/$name" || -L "$dest/$name" ]]; then
        [[ -f "$dest/$name" && ! -L "$dest/$name" && "$(git hash-object "$dest/$name")" == "$expected" ]] || {
            echo "Unexpected existing $name; refusing overwrite." >&2; return 1;
        }
        return
    fi
    curl --proto '=https' --fail --silent --show-error --location --proto-redir '=https' \
        --retry 3 --connect-timeout 20 --max-time 180 --max-filesize 20000000 \
        "$origin/$source" -o "$temp/$name"
    [[ "$(git hash-object "$temp/$name")" == "$expected" ]] || {
        echo "Blob verification failed: $name" >&2; return 1;
    }
}
fetch Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf NotoSansCJKsc-Regular.otf dc15562470b4f842321894787a0d066879ccff8b
fetch Sans/OTF/TraditionalChineseHK/NotoSansCJKhk-Regular.otf NotoSansCJKhk-Regular.otf e28d5f1e78db9039ee432a78d31b566dc3a00d27
fetch LICENSE LICENSE-NotoSansCJK-OFL.txt d952d62c065f3f35fb83a173496e90b21525aef3
for file in "$temp"/*; do
    [[ -f "$file" ]] || continue
    cp -n "$file" "$dest/"
done
echo "Verified Chinese font resources staged in $dest; existing fonts retained."
