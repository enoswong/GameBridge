#!/bin/sh
# Xcode resource phase. LocalDebug payloads must never enter a Release product.
set -eu
: "${SRCROOT:?Xcode SRCROOT is required}"
: "${TARGET_BUILD_DIR:?Xcode TARGET_BUILD_DIR is required}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?Xcode resource path is required}"
: "${CONFIGURATION:?Xcode CONFIGURATION is required}"
payload="$SRCROOT/build/bootstrap-payload"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Bootstrap"
if [ ! -d "$payload" ]; then
    if [ "$CONFIGURATION" = Debug ]; then
        echo 'note: LocalDebug Bootstrap payload absent; run scripts/package-bootstrap.py to enable one-click setup.'
        # An incremental build must not retain a payload removed from its inputs.
        if [ -L "$destination" ]; then
            echo 'error: Bootstrap destination must not be a symlink.' >&2
            exit 1
        fi
        rm -rf "$destination"
        exit 0
    fi
    echo 'error: Release bootstrap payload is missing; an audited release pipeline is required.' >&2
    exit 1
fi
python3 - "$SRCROOT" "$payload" "$CONFIGURATION" <<'PY'
import base64
import importlib.util
import json
from pathlib import Path
import sys
root, payload, configuration = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
spec = importlib.util.spec_from_file_location('bootstrap_packaging', root / 'scripts/package-bootstrap.py')
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)
manifest = json.loads(packaging.regular_file(payload / 'bootstrap.json').read_text())
for field in ('catalogFile', 'trustKeysFile', 'archiveFile', 'bridgeFile', 'pointerFile'):
    packaging.safe_path(manifest[field])
    packaging.regular_file(payload / manifest[field])
catalog = json.loads(base64.b64decode(json.loads((payload / manifest['catalogFile']).read_text())['payload'], validate=True))
engine = next(item for item in catalog['engines'] if item['id'] == manifest['engineID'])
packaging.release_gate(engine, configuration != 'Debug')
packaging.verify_digest(payload / manifest['archiveFile'], engine['archiveSHA256'])
packaging.verify_digest(payload / manifest['bridgeFile'], manifest['bridgeSHA256'])
packaging.verify_digest(payload / manifest['pointerFile'], manifest['pointerSHA256'])
packaging.terms_from(payload / 'Terms', manifest['installers'])
if payload.is_symlink() or any(path.is_symlink() for path in payload.rglob('*')):
    raise ValueError('Bootstrap resources must not contain symlinks')
PY
if [ -L "$destination" ]; then
    echo 'error: Bootstrap destination must not be a symlink.' >&2
    exit 1
fi
mkdir -p "$(dirname "$destination")"
rm -rf "$destination"
/usr/bin/ditto "$payload" "$destination"
echo 'note: Embedded verified LocalDebug Bootstrap resources.'
