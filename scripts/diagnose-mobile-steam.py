#!/usr/bin/env python3
"""Inspect the isolated desktop Steam install and its pinned official archives.

Read-only: no guest files are modified, and no account/log content is printed.
"""
import argparse
import hashlib
import pathlib
import struct
import subprocess
import tempfile
import zipfile

ORIGIN = "https://client-update.akamai.steamstatic.com/"
PACKAGES = (
    ("steam_win32.zip.3e96965d109fc2d4cc14206b2fc4ec960a746ed3", 2307664,
     "1369615c795b60de822876b4dc4042186cf58d0dc8f63ea1371167f667e16925"),
    ("bins_win32.zip.23e34a6d4b10596a44561a5100dac5585d2517da", 59544006,
     "8b712b2a3412a9066b7725f4e1c5cef9a7ca5b187b6585a5b92d25d09df0ba62"),
    ("bins_win64_win32.zip.f29d67dc38a4be027f1734802697c668621a6da1", 10509550,
     "345f6e4bdc19b27ae53bf752c21e2d894e0e899d94823222fb426e890d1226b5"),
)
WATCH = ("steam.exe", "bin/vgui2_s.dll", "steamclient.dll", "steamclient64.dll",
         "steamui.dll", "bin/filesystem_stdio.dll")
WATCH_BASENAMES = {pathlib.PurePosixPath(x).name for x in WATCH}


def facts(data):
    if len(data) < 64 or data[:2] != b"MZ":
        return "invalid MZ"
    offset = struct.unpack_from("<I", data, 60)[0]
    if offset + 24 > len(data) or data[offset:offset+4] != b"PE\0\0":
        return "invalid PE"
    machine = struct.unpack_from("<H", data, offset + 4)[0]
    return {0x14c: "x86", 0x8664: "x64", 0xa641: "ARM64EC", 0xaa64: "ARM64"}.get(
        machine, hex(machine))


def inventory():
    seen = set()
    all_files = set()
    client_hash = None
    with tempfile.TemporaryDirectory(prefix="gamebridge-steam-inventory-") as folder:
        for name, size, sha in PACKAGES:
            file = pathlib.Path(folder) / name
            subprocess.run(["curl", "--proto", "=https", "--fail", "--silent", "--show-error",
                            "--retry", "2", "--connect-timeout", "20", "--max-time", "120",
                            "--max-filesize", str(size), "-o", str(file), ORIGIN + name], check=True)
            if file.stat().st_size != size:
                raise ValueError("Official archive size mismatch")
            with file.open("rb") as f:
                if hashlib.file_digest(f, "sha256").hexdigest() != sha:
                    raise ValueError("Official archive hash mismatch")
            with zipfile.ZipFile(file) as archive:
                print(name.split(".zip")[0] + ": verified; " + str(len(archive.infolist())) + " entries")
                for entry in archive.infolist():
                    relative = entry.filename.replace("\\", "/").lower()
                    if entry.is_dir() or relative.endswith("/"):
                        continue
                    parts = relative.split("/")
                    if not relative or any(not part or part in {".", ".."} or ":" in part for part in parts):
                        raise ValueError("Unsafe official ZIP path")
                    if relative in all_files:
                        raise ValueError("Conflicting file in official archive cohort: " + relative)
                    all_files.add(relative)
                    if pathlib.PurePosixPath(relative).name not in WATCH_BASENAMES:
                        continue
                    if entry.file_size > 64 * 1024 * 1024:
                        raise ValueError("Unexpected watched entry size")
                    data = archive.read(entry)
                    print("  " + relative + ": " + str(len(data)) + " bytes; " + facts(data))
                    seen.add(relative)
                    if relative == "steamclient64.dll":
                        client_hash = hashlib.sha256(data).hexdigest()
    if not {"steam.exe", "bin/vgui2_s.dll", "steamclient64.dll"}.issubset(seen):
        raise ValueError("Pinned desktop cohort is incomplete")
    if client_hash != "71b391fe9f3e2006cbc81a5c75eef3eb4186012deabfdb2c8b7e8d4850ecf640":
        raise ValueError("Pinned Steam client64 identity mismatch")
    print("Pinned packages contain bin/vgui2_s.dll:", "bin/vgui2_s.dll" in seen)
    print("Non-conflicting verified file cohort:", len(all_files))
    print("Inventory only; no files installed and no desktop startup claimed.")


def inspect_client(root):
    if not root.is_dir() or root.is_symlink():
        raise ValueError("Provide the copied isolated Steam client folder")
    for relative in WATCH:
        candidate = root
        for component in relative.split("/"):
            if not candidate.is_dir() or candidate.is_symlink():
                candidate = None
                break
            matches = [p for p in candidate.iterdir() if p.name.lower() == component.lower()]
            if len(matches) != 1 or matches[0].is_symlink():
                candidate = None
                break
            candidate = matches[0]
        if candidate is None or not candidate.is_file():
            print(relative + ": missing or conflicting")
        elif candidate.stat().st_size > 128 * 1024 * 1024:
            print(relative + ": oversized; not parsed")
        else:
            data = candidate.read_bytes()
            print(relative + ": " + str(len(data)) + " bytes; " + facts(data))
    print("Presence/PE checks do not establish that a DLL can be loaded.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--official-packages", action="store_true")
    parser.add_argument("--client-dir", type=pathlib.Path)
    args = parser.parse_args()
    if not args.official_packages and args.client_dir is None:
        parser.error("choose --official-packages and/or --client-dir")
    if args.client_dir is not None:
        inspect_client(args.client_dir)
    if args.official_packages:
        inventory()


if __name__ == "__main__":
    main()
