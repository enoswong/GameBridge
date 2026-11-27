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

# CP850 and CP10000 are requested by the device log even in the English desktop.
# Stage the exact Wine revision's tables into the primary NLS directory, not only extra/.
dest="$workspace/app/Madeira/nls"
[[ -d "$dest" && ! -L "$dest" ]]
origin="https://raw.githubusercontent.com/willfaust/wine/ddf92babc5ba71f4586cc4713f5a8eb39f63d39b"
for file in "$temp"/*; do [[ ! -f "$file" ]] || rm -- "$file"; done
fetch nls/c_850.nls c_850.nls 7b8fcaee181db36c3dc85eb89490b8cb8c1a22b1
fetch nls/c_10000.nls c_10000.nls 80f8055857aa3e8b1ac96f686f92f745482918fd
for file in "$temp"/*; do
    [[ -f "$file" ]] || continue
    cp -n "$file" "$dest/"
done
echo "Verified missing CP850 and CP10000 tables staged in $dest."
