#!/usr/bin/env python3
"""Normalize the pinned internal probe archive. Never executes or extracts its code.

This is a developer research tool, not a production updater or a source rebuild.
Only contained file symlinks are materialized. All other special entries fail closed.
"""
import gzip
import tempfile
import argparse
import hashlib
import json
import posixpath
import tarfile
from pathlib import Path

PINNED_SHA256 = '01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3'
MAX_BYTES = 2 * 1024**3


def safe_path(name):
    if not name or name.startswith('/') or '\\' in name or ':' in name:
        raise ValueError('unsafe archive path')
    if any(part in ('', '.', '..') for part in name.split('/')):
        raise ValueError('unsafe archive component')
    if any(ord(c) < 32 for c in name):
        raise ValueError('control character in path')
    return name


def normalize(source, destination):
    with source.open('rb') as handle:
        digest = hashlib.file_digest(handle, 'sha256').hexdigest()
    if digest != PINNED_SHA256:
        raise ValueError('source archive does not match pinned release digest')
    with tempfile.TemporaryFile() as raw:
        with gzip.open(source, 'rb') as compressed:
            total = 0
            while chunk := compressed.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_BYTES:
                    raise ValueError('decompressed archive limit')
                raw.write(chunk)
        raw.seek(0)
        return normalize_tar(raw, destination, digest)


def normalize_tar(raw, destination, digest):
    with tarfile.open(fileobj=raw, mode='r:') as archive:
        entries = {}
        folded = set()
        size = 0
        for entry in archive:
            name = safe_path(entry.name.rstrip('/') if entry.isdir() else entry.name)
            if name.casefold() in folded or len(entries) >= 10000:
                raise ValueError('duplicate path or entry limit')
            if not (entry.isfile() or entry.isdir() or entry.issym()):
                raise ValueError('unsupported entry type')
            size += entry.size
            if size > MAX_BYTES:
                raise ValueError('input expansion limit')
            folded.add(name.casefold())
            entries[name] = entry

        def resolve(name, visited=None):
            visited = set() if visited is None else visited
            if name in visited or name not in entries:
                raise ValueError('link cycle or missing target')
            visited.add(name)
            entry = entries[name]
            if entry.issym():
                if entry.linkname.startswith('/') or '\\' in entry.linkname:
                    raise ValueError('absolute or invalid link')
                target = safe_path(posixpath.normpath(posixpath.join(posixpath.dirname(name), entry.linkname)))
                return resolve(target, visited)
            if not entry.isfile():
                raise ValueError('only file links can be materialized')
            return entry

        expanded = 0
        # Exclusive destination creation prevents accidental replacement of evidence.
        with destination.open('xb') as output, tarfile.open(fileobj=output, mode='w', format=tarfile.USTAR_FORMAT) as normalized:
            for name, entry in sorted(entries.items()):
                info = tarfile.TarInfo(name)
                info.uid = info.gid = info.mtime = 0
                if entry.isdir():
                    info.type = tarfile.DIRTYPE
                    info.mode = 0o700
                    normalized.addfile(info)
                else:
                    regular = resolve(name)
                    expanded += regular.size
                    if expanded > MAX_BYTES:
                        raise ValueError('materialized expansion limit')
                    info.size = regular.size
                    info.mode = 0o500 if regular.mode & 0o111 else 0o400
                    with archive.extractfile(regular) as content:
                        normalized.addfile(info, content)
    with destination.open('rb') as handle:
        result = hashlib.file_digest(handle, 'sha256').hexdigest()
    return {'archiveSHA256': result, 'archiveBytes': destination.stat().st_size,
            'unpackedBytes': expanded, 'sourceSHA256': digest, 'entries': len(entries)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    print(json.dumps(normalize(args.source, args.destination), sort_keys=True))
