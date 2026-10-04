#!/usr/bin/env python3
"""Build an isolated, signed LocalDebug bootstrap resource directory (macOS)."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
ENGINE_ID = 'internal-wine11-dxmt080-1'
KEY_ID = 'bootstrap-local-debug'
HEX = re.compile(r'[0-9a-f]{64}')


def safe_path(value):
    if not isinstance(value, str) or not value or len(value.encode()) > 1024:
        raise ValueError('invalid relative path')
    if '\\' in value or ':' in value or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('unsafe relative path')
    if any(p in ('', '.', '..') for p in value.split('/')):
        raise ValueError('unsafe path component')
    return value


def regular_file(path):
    path = Path(path).absolute()
    if any(p.is_symlink() for p in (path, *path.parents)) or not path.is_file():
        raise ValueError(f'expected regular file without symlinks: {path}')
    return path


def digest(path):
    with regular_file(path).open('rb') as source:
        h = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            h.update(chunk)
        return h.hexdigest()


def verify_digest(path, expected):
    if not isinstance(expected, str) or not HEX.fullmatch(expected) or digest(path) != expected:
        raise ValueError(f'SHA-256 mismatch: {path}')


def release_gate(engine, release):
    if not release:
        return
    if engine.get('distribution') != 'redistributable':
        raise ValueError('Release blocked: internalOnly runtime; audited source closure and redistribution rights required')
    raise ValueError('Release blocked: this LocalDebug signer cannot attest production trust, source closure, Developer ID signing, or notarization; use the audited release pipeline')


def installers_from(path):
    value = json.loads(regular_file(path).read_text())
    entries = value.get('installers') if isinstance(value, dict) else value
    if not isinstance(entries, list) or len(entries) != 4:
        raise ValueError('installer manifest must contain all four installers')
    ids, files = set(), set()
    for item in entries:
        if set(item) != {'id', 'fileName', 'url', 'sha256', 'maximumBytes'}:
            raise ValueError('unexpected installer fields')
        name = safe_path(item['fileName'])
        url = urlsplit(item['url'])
        if '/' in name or not name.lower().endswith('.exe') or name.casefold() in files:
            raise ValueError('unsafe or duplicate installer filename')
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment:
            raise ValueError('installer URL must be HTTPS without credentials or fragment')
        if not HEX.fullmatch(item['sha256']) or type(item['maximumBytes']) is not int or not 0 < item['maximumBytes'] <= 2 * 1024**3:
            raise ValueError('invalid installer hash or size bound')
        ids.add(item['id']); files.add(name.casefold())
    if ids != {'steam', 'vc-x64', 'vc-x86', 'directx'}:
        raise ValueError('missing or duplicate installer ID')
    return entries


def terms_from(directory, installers):
    directory = Path(directory)
    provenance_file = regular_file(directory / 'provenance.json')
    provenance = json.loads(provenance_file.read_text())
    pinned = {item['id']: item['sha256'] for item in installers}
    terms = provenance.get('terms', [])
    required_files = {'microsoft-vc14-en.txt', 'microsoft-directx-june2010-en.txt'}
    if {item.get('textFile') for item in terms} != required_files or len(terms) != 2:
        raise ValueError('both full Microsoft license texts are required')
    covered = set()
    for item in terms:
        name = safe_path(item['textFile'])
        verify_digest(directory / name, item['textSHA256'])
        if len((directory / name).read_text().strip()) < 1000:
            raise ValueError('license text is incomplete')
        covered.update(item['installerIDs'])
    if covered != {'vc-x64', 'vc-x86', 'directx'}:
        raise ValueError('license coverage is incomplete')
    provenance_pins = {item['id']: item['sha256'] for item in provenance['installers']}
    if set(provenance_pins) != covered or any(pinned[item] != provenance_pins[item] for item in covered):
        raise ValueError('license provenance does not match pinned installers')
    return [provenance_file, *(directory / name for name in sorted(required_files))]


def validate_archive(path, engine):
    verify_digest(path, engine['archiveSHA256'])
    if path.stat().st_size != engine['archiveBytes']:
        raise ValueError('archive size mismatch')
    expected = dict(engine.get('dxmtFileSHA256s', {}))
    required = {safe_path(engine['winePath']), safe_path(engine['wineserverPath'])}
    for name in expected:
        safe_path(name)
    seen, files, kinds, executable, expanded = set(), set(), {}, set(), 0
    with tarfile.open(path, 'r:') as archive:
        for entry in archive:
            name = safe_path(entry.name)
            if name.casefold() in seen or len(seen) >= 100000:
                raise ValueError('duplicate archive path or entry limit')
            seen.add(name.casefold())
            kinds[name.casefold()] = entry.isdir()
            if not (entry.isfile() or entry.isdir()):
                raise ValueError('archive links and special entries are forbidden')
            if name.split('/')[0] != 'Libraries':
                raise ValueError('runtime archive must contain only Libraries, never user prefixes')
            if entry.isfile():
                files.add(name)
                if entry.mode & 0o111:
                    executable.add(name)
                expanded += entry.size
                if expanded > engine['unpackedBytes'] or expanded > 64 * 1024**3:
                    raise ValueError('archive expansion limit')
                if name in expected:
                    h = hashlib.sha256(archive.extractfile(entry).read()).hexdigest()
                    if h != expected[name]:
                        raise ValueError(f'DXMT file digest mismatch: {name}')
    for name in seen:
        parts = name.split('/')
        for index in range(1, len(parts)):
            if kinds.get('/'.join(parts[:index])) is False:
                raise ValueError('archive file used as directory')
    if expanded != engine['unpackedBytes'] or not required.union(expected).issubset(files) or not required.issubset(executable):
        raise ValueError('missing runtime executable/DXMT file or unpacked size mismatch')


SWIFT = r'''
import Foundation
import CryptoKit
let args = CommandLine.arguments
let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: String]
let trusted = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: String]
guard let encodedKey = trusted[envelope["keyID"]!], let rawKey = Data(base64Encoded: encodedKey),
      let oldPayload = Data(base64Encoded: envelope["payload"]!), let signature = Data(base64Encoded: envelope["signature"]!) else { fatalError("invalid source catalog envelope") }
let oldKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
guard oldKey.isValidSignature(signature, for: oldPayload) else { fatalError("source catalog signature mismatch") }
let payload = try Data(contentsOf: URL(fileURLWithPath: args[3]))
let key = Curve25519.Signing.PrivateKey()
let signed = ["keyID": "bootstrap-local-debug", "payload": payload.base64EncodedString(), "signature": try key.signature(for: payload).base64EncodedString()]
let directory = URL(fileURLWithPath: args[4])
try JSONSerialization.data(withJSONObject: signed, options: [.sortedKeys]).write(to: directory.appendingPathComponent("runtime-catalog.json"))
try JSONSerialization.data(withJSONObject: ["bootstrap-local-debug": key.publicKey.rawRepresentation.base64EncodedString()], options: [.sortedKeys]).write(to: directory.appendingPathComponent("runtime-keys.json"))
'''


def build_payload(args):
    catalog_file = regular_file(args.catalog)
    envelope = json.loads(catalog_file.read_text())
    original = json.loads(base64.b64decode(envelope['payload'], validate=True))
    matches = [e for e in original['engines'] if e['id'] == ENGINE_ID]
    if len(matches) != 1:
        raise ValueError('expected exactly one original DXMT runtime manifest')
    engine = matches[0]
    release_gate(engine, args.release)
    if engine['distribution'] != 'internalOnly':
        raise ValueError('LocalDebug requires an explicitly internalOnly manifest')
    archive = regular_file(args.archive)
    validate_archive(archive, engine)
    pointer = regular_file(args.pointer)
    pointer_hash = digest(pointer)
    if args.pointer_sha256:
        verify_digest(pointer, args.pointer_sha256)
    installers = installers_from(args.installers_manifest)
    terms = terms_from(ROOT / 'scripts/compatibility/terms', installers)
    output = Path(args.output).absolute()
    if output.exists() or output.is_symlink():
        raise ValueError('output exists; choose a new directory or explicitly remove the old generated payload')
    output.parent.mkdir(parents=True, exist_ok=True)
    if any(p.is_symlink() for p in (output.parent, *output.parents)):
        raise ValueError('output path contains a symlink')
    with tempfile.TemporaryDirectory(prefix='.bootstrap-', dir=output.parent) as temporary:
        work = Path(temporary)
        payload = work / 'payload'; payload.mkdir()
        shutil.copyfile(archive, payload / 'runtime.tar')
        verify_digest(payload / 'runtime.tar', engine['archiveSHA256'])
        shutil.copyfile(pointer, payload / 'version.dll')
        verify_digest(payload / 'version.dll', pointer_hash)
        bridge = payload / 'deskrawl-alpha.dylib'
        if args.bridge:
            if not args.bridge_sha256:
                raise ValueError('--bridge requires --bridge-sha256 from its verified build')
            verify_digest(args.bridge, args.bridge_sha256)
            shutil.copyfile(args.bridge, bridge)
            verify_digest(bridge, args.bridge_sha256)
            subprocess.run(['codesign', '--verify', str(bridge)], check=True)
        else:
            subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-dynamiclib', '-fobjc-arc', '-fblocks', '-framework', 'Cocoa', '-framework', 'QuartzCore', '-framework', 'Metal', str(ROOT / 'scripts/compatibility/deskrawl-alpha.m'), '-o', str(bridge)], check=True)
            subprocess.run(['codesign', '--force', '--sign', '-', str(bridge)], check=True)
        now = int(time.time())
        catalog = {'schemaVersion': 1, 'revision': max(now, original['revision'] + 1), 'issuedAt': now - 60, 'expiresAt': now + 30 * 86400, 'revokedEngineIDs': original.get('revokedEngineIDs', []), 'engines': [engine]}
        if ENGINE_ID in catalog['revokedEngineIDs']:
            raise ValueError('selected runtime is revoked')
        unsigned = work / 'catalog-payload.json'; unsigned.write_text(json.dumps(catalog, sort_keys=True, separators=(',', ':')))
        signer = work / 'sign.swift'; signer.write_text(SWIFT)
        subprocess.run(['xcrun', 'swift', str(signer), str(catalog_file), str(regular_file(args.trust_keys)), str(unsigned), str(payload)], check=True)
        manifest = {'schema': 1, 'engineID': ENGINE_ID, 'catalogFile': 'runtime-catalog.json', 'trustKeysFile': 'runtime-keys.json', 'archiveFile': 'runtime.tar', 'bridgeFile': bridge.name, 'bridgeSHA256': digest(bridge), 'pointerFile': 'version.dll', 'pointerSHA256': pointer_hash, 'installers': installers}
        (payload / 'bootstrap.json').write_text(json.dumps(manifest, indent=2) + '\n')
        terms_dir = payload / 'Terms'; terms_dir.mkdir()
        for source in terms:
            shutil.copyfile(source, terms_dir / source.name)
            verify_digest(terms_dir / source.name, digest(source))
        source_dir = payload / 'CompatibilitySources'; source_dir.mkdir()
        source_hashes = {}
        for name in ('deskrawl-alpha.m', 'deskrawl-pointer.c', 'deskrawl-version.c', 'deskrawl-version.def', 'build-pointer.sh', 'POINTER-LICENSE.md', 'MINGW-AUTHORS.txt', 'MINGW-COPYING.txt'):
            source = regular_file(ROOT / 'scripts/compatibility' / name)
            source_hashes[name] = digest(source)
            shutil.copyfile(source, source_dir / name)
            verify_digest(source_dir / name, source_hashes[name])
        (source_dir / 'sha256.json').write_text(json.dumps(source_hashes, indent=2) + '\n')
        os.rename(payload, output)
    print(f'LocalDebug bootstrap payload: {output}\nRuntime remains internalOnly; catalog expires in 30 days.')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=ROOT / 'build/research/internal-wine.tar')
    parser.add_argument('--catalog', type=Path, default=ROOT / 'build/research/dxmt-catalog.json')
    parser.add_argument('--trust-keys', type=Path, default=ROOT / 'build/research/dxmt-public-keys.json')
    parser.add_argument('--pointer', type=Path, default=ROOT / 'build/compatibility/version.dll')
    parser.add_argument('--pointer-sha256', help='Optional independently pinned pointer digest')
    parser.add_argument('--bridge', type=Path, help='Optional prebuilt and signed native bridge')
    parser.add_argument('--bridge-sha256', help='Required verified build digest when --bridge is supplied')
    parser.add_argument('--installers-manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/bootstrap-payload')
    parser.add_argument('--release', action='store_true', help='Enforce release gate (local research runtime is refused)')
    args = parser.parse_args()
    try:
        build_payload(args)
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Bootstrap packaging failed: {error}\n')


if __name__ == '__main__':
    main()
