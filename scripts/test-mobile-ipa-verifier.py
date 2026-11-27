#!/usr/bin/env python3
"""Synthetic structural fixtures only; no actual IPA or guest is executed."""
import importlib.util
import pathlib
import plistlib
import struct
import tempfile
import unittest
import zipfile

script = pathlib.Path(__file__).with_name("verify-mobile-research-ipa.py")
spec = importlib.util.spec_from_file_location("verifier", script)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def pe(machine):
    header = bytearray(64)
    header[:2] = b"MZ"
    struct.pack_into("<I", header, 60, 64)
    return header + b"PE\0\0" + struct.pack("<H", machine)


def entries():
    root = verifier.ROOT
    bundle = verifier.BUNDLE
    mach = struct.pack("<8I", 0xfeedfacf, 0x0100000c, 0, 2, 0, 0, 0, 0)
    files = {
        root + "Info.plist": plistlib.dumps({
            "CFBundleIdentifier": bundle, "UIDeviceFamily": [1, 2],
            "CFBundleDisplayName": "GameBridge Research", "CFBundleExecutable": "Madeira",
            "CFBundleURLTypes": [{"CFBundleURLSchemes": ["gamebridge-research"]}]
        }),
        root + "Madeira": mach,
        root + "arm64ec-windows/xtajit64.dll": pe(0xa641),
        root + "i386-windows/ntdll.dll": pe(0x14c),
        root + "prefix-template.tar.gz": b"synthetic"
    }
    for name in ("JITHelper", "MemoryHost"):
        folder = root + "PlugIns/Madeira" + name + ".appex/"
        files[folder + "Info.plist"] = plistlib.dumps({
            "CFBundleIdentifier": bundle + "." + name, "CFBundleExecutable": name
        })
        files[folder + name] = mach
    return files


class StructuralTests(unittest.TestCase):
    def check_files(self, files):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "fixture.ipa"
            with zipfile.ZipFile(path, "w") as archive:
                for name, data in files.items():
                    archive.writestr(name, data)
            verifier.verify(path)

    def test_valid_structure(self):
        self.check_files(entries())

    def test_missing_jit_helper(self):
        files = entries()
        del files[verifier.ROOT + "PlugIns/MadeiraJITHelper.appex/Info.plist"]
        with self.assertRaises(KeyError):
            self.check_files(files)

    def test_wrong_x86_architecture(self):
        files = entries()
        files[verifier.ROOT + "i386-windows/ntdll.dll"] = pe(0x8664)
        with self.assertRaisesRegex(ValueError, "missing x86"):
            self.check_files(files)

    def test_truncated_executable(self):
        files = entries()
        files[verifier.ROOT + "Madeira"] = struct.pack("<II", 0xfeedfacf, 0x0100000c)
        with self.assertRaisesRegex(ValueError, "truncated"):
            self.check_files(files)

    def test_extension_identifier_must_match(self):
        files = entries()
        key = verifier.ROOT + "PlugIns/MadeiraMemoryHost.appex/Info.plist"
        info = plistlib.loads(files[key])
        info["CFBundleIdentifier"] = "com.willfaust.madeora.MemoryHost"
        files[key] = plistlib.dumps(info)
        with self.assertRaisesRegex(ValueError, "extension identity"):
            self.check_files(files)


if __name__ == "__main__":
    unittest.main()
