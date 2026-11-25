#!/usr/bin/env python3
"""Inspect a locally produced research IPA; no signing or distribution."""
import hashlib
import plistlib
import struct
import sys
import zipfile

BUNDLE = "org.enostudio.gamebridge.research"
ROOT = "Payload/Madeira.app/"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def pe_machine(archive, name):
    with archive.open(ROOT + name) as f:
        header = f.read(64)
        require(len(header) == 64 and header[:2] == b"MZ", "missing PE header: " + name)
        offset = struct.unpack_from("<I", header, 60)[0]
        require(64 <= offset <= 1024 * 1024, "invalid PE offset: " + name)
        f.seek(offset)
        pe = f.read(6)
        require(len(pe) == 6 and pe[:4] == b"PE\0\0", "invalid PE signature: " + name)
        return struct.unpack_from("<H", pe, 4)[0]


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "duplicate ZIP entries")
        require(archive.testzip() is None, "damaged IPA")
        info = plistlib.loads(archive.read(ROOT + "Info.plist"))
        require(info.get("CFBundleIdentifier") == BUNDLE, "incorrect app identity")
        require(set(info.get("UIDeviceFamily", [])) == {1, 2}, "iPhone/iPad target missing")
        require(info.get("CFBundleDisplayName") == "GameBridge Research", "incorrect display name")
        schemes = [scheme for item in info.get("CFBundleURLTypes", [])
                   for scheme in item.get("CFBundleURLSchemes", [])]
        require("gamebridge-research" in schemes and "madeira" not in schemes, "incorrect callback scheme")
        executable = info["CFBundleExecutable"]
        with archive.open(ROOT + executable) as f:
            magic, cpu = struct.unpack("<II", f.read(8))
        require(magic == 0xfeedfacf and cpu == 0x0100000c, "app is not arm64 Mach-O")
        require(pe_machine(archive, "arm64ec-windows/xtajit64.dll") in {0xa641, 0x8664},
                "missing x64 translation module")
        require(pe_machine(archive, "i386-windows/ntdll.dll") == 0x14c, "missing x86 guest runtime")
        for name in names:
            if name.startswith(ROOT + "PlugIns/") and name.endswith(".appex/Info.plist"):
                ext = plistlib.loads(archive.read(name))
                require(ext["CFBundleIdentifier"].startswith(BUNDLE + "."), "extension identity mismatch")
        require(ROOT + "prefix-template.tar.gz" in names, "missing Windows prefix template")
    with open(path, "rb") as f:
        digest = hashlib.file_digest(f, "sha256").hexdigest()
    print("Research IPA structure verified (not a device or signing test). SHA256:", digest)


if __name__ == "__main__":
    verify(sys.argv[1])
