#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Use the same immutable official Microsoft package as the pinned Madeira device installer.
set -euo pipefail
url='https://download.visualstudio.microsoft.com/download/pr/990c720a-46ce-4dc7-87b9-c2eb615d34b9/CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B/VC_redist.x64.exe'
sha='cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
bytes=25635768
verify() {
    python3 - "$1" "$sha" "$bytes" <<'PY'
import hashlib, pathlib, sys
p = pathlib.Path(sys.argv[1])
if p.is_symlink() or not p.is_file() or p.stat().st_size != int(sys.argv[3]):
    raise SystemExit("Microsoft runtime input is not a regular file of the pinned size")
with p.open("rb") as f:
    if f.read(2) != b"MZ":
        raise SystemExit("Microsoft runtime input lacks an MZ header")
    f.seek(0)
    digest = hashlib.sha256()
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != sys.argv[2]:
    raise SystemExit("Microsoft runtime input SHA-256 mismatch")
print("Microsoft x64 runtime 14.44.35211.0 size and SHA-256 verified")
PY
}
case "${1:-}" in
    --verify)
        [[ $# == 2 ]] || exit 2
        verify "$2"
        ;;
    --fetch)
        [[ $# == 2 ]] || exit 2
        destination="$2"
        if [[ -e "$destination" || -L "$destination" ]]; then
            verify "$destination"
            exit 0
        fi
        mkdir -p "$(dirname "$destination")"
        temp="$(mktemp "$(dirname "$destination")/.vc-redist.XXXXXXXX")"
        trap 'rm -f "$temp"' EXIT
        # No shortlink, redirects, unverified mirrors, or arbitrary replacement versions.
        code="$(curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
            --retry 3 --retry-all-errors --connect-timeout 20 --max-time 120 \
            --max-filesize "$bytes" --output "$temp" --write-out '%{http_code}' "$url")"
        [[ "$code" == 200 ]] || { echo "Microsoft CDN returned unexpected HTTP status" >&2; exit 1; }
        verify "$temp"
        # Hard-link publication is atomic and refuses to overwrite a concurrently created file.
        if ! ln "$temp" "$destination"; then verify "$destination"; fi
        verify "$destination"
        ;;
    *)
        echo "Usage: $0 --fetch FILE | --verify FILE" >&2
        exit 2
        ;;
esac
