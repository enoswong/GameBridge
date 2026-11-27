#!/usr/bin/env python3
"""Prepare missing official Steam files for an exported, stopped iPhone client.

Never modify the source snapshot, overwrite existing files, or mix package versions.
The output is a missing-files-only directory for manual import, not an IPA.
"""
import argparse
import hashlib
import importlib.util
import pathlib
import stat
import subprocess
import tempfile
import zipfile

spec = importlib.util.spec_from_file_location(
    "inventory", pathlib.Path(__file__).with_name("diagnose-mobile-steam.py"))
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)
LIMIT = 64 * 1024 * 1024
CLIENT_HASH = "71b391fe9f3e2006cbc81a5c75eef3eb4186012deabfdb2c8b7e8d4850ecf640"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe_parts(name):
    parts = name.replace("\\", "/").split("/")
    if (len(name.encode()) >= 240 or any(not p or p in (".", "..") or ":" in p
            or p.endswith((".", " ")) or any(ord(c) < 32 for c in p) for p in parts)):
        raise ValueError("Unsafe package path")
    return parts


def member_path(root, name):
    current = root
    for part in safe_parts(name):
        if current.is_symlink():
            raise ValueError("Linked directory in snapshot")
        if current.exists():
            if not current.is_dir():
                raise ValueError("Unexpected parent file")
            matches = [p for p in current.iterdir() if p.name.casefold() == part.casefold()]
            if len(matches) > 1 or (matches and matches[0].name != part):
                raise ValueError("Case conflict: " + name)
        current = current / part
    if current.is_symlink():
        raise ValueError("Linked file in snapshot")
    return current


def extract_archives(archives, stage):
    names = set()
    total = 0
    for path in archives:
        with zipfile.ZipFile(path) as archive:
            if len(archive.infolist()) > 256:
                raise ValueError("Too many archive entries")
            for entry in archive.infolist():
                name = entry.filename.replace("\\", "/")
                if name.endswith("/"):
                    safe_parts(name[:-1])
                    if entry.file_size != 0:
                        raise ValueError("Invalid directory entry")
                    continue
                mode = (entry.external_attr >> 16) & 0xf000
                if mode not in (0, stat.S_IFREG) or entry.flag_bits & 1:
                    raise ValueError("Unsupported archive entry")
                target = member_path(stage, name)
                if name.casefold() in names or not 0 <= entry.file_size <= LIMIT:
                    raise ValueError("Duplicate or oversized entry")
                names.add(name.casefold())
                total += entry.file_size
                if total > 512 * 1024 * 1024:
                    raise ValueError("Cohort extraction limit exceeded")
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open("xb") as stream:
                    stream.write(archive.read(entry))
    return sorted(p for p in stage.rglob("*") if p.is_file())


def plan(snapshot, stage, files):
    if not snapshot.is_dir() or snapshot.is_symlink():
        raise ValueError("Provide a local copy of the stopped Steam Big Picture folder")
    missing = []
    for source in files:
        relative = source.relative_to(stage).as_posix()
        destination = member_path(snapshot, relative)
        if destination.exists():
            if not destination.is_file() or destination.stat().st_size != source.stat().st_size or sha(destination) != sha(source):
                raise ValueError("Existing client differs from pinned cohort: " + relative)
        else:
            missing.append(relative)
    return sorted(missing, key=lambda name: (name == "steam.exe", name))


def prepare(snapshot, output):
    snapshot = snapshot.absolute()
    output = output.absolute()
    if output.exists() or output.is_symlink() or output.resolve().is_relative_to(snapshot.resolve()):
        raise ValueError("Output must be a new directory outside the client snapshot")
    with tempfile.TemporaryDirectory(prefix="gamebridge-repair-") as tmp:
        tmp = pathlib.Path(tmp)
        archives = []
        for name, size, digest in inventory.PACKAGES:
            file = tmp / name
            subprocess.run(["curl", "--proto", "=https", "--fail", "--silent", "--show-error",
                            "--retry", "2", "--connect-timeout", "20", "--max-time", "120",
                            "--max-filesize", str(size), "-o", str(file), inventory.ORIGIN + name], check=True)
            if file.stat().st_size != size or sha(file) != digest:
                raise ValueError("Official archive verification failed")
            archives.append(file)
        stage = tmp / "stage"
        stage.mkdir()
        files = extract_archives(archives, stage)
        for relative, machine in (("steam.exe", "x86"), ("bin/vgui2_s.dll", "x86"),
                                  ("steamclient.dll", "x86"), ("steamclient64.dll", "x64")):
            if inventory.facts((stage / relative).read_bytes()) != machine:
                raise ValueError("Unexpected architecture: " + relative)
        if sha(stage / "steamclient64.dll") != CLIENT_HASH:
            raise ValueError("Client identity mismatch")
        missing = plan(snapshot, stage, files)
        if not missing:
            print("No missing cohort files. Investigate loader or indirect dependencies instead.")
            return
        # Export to a new folder; do not modify or print account/config files.
        output.mkdir()
        for relative in missing:
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as stream:
                stream.write((stage / relative).read_bytes())
            if sha(target) != sha(stage / relative):
                raise ValueError("Export verification failed; do not use partial output")
        print("Verified missing-only files:", len(missing))
        print("Import only to the same unchanged, stopped client; never replace existing files.")
        print("No iPhone files changed. No claim of Steam startup success.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-dir", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    prepare(args.client_dir, args.output)
