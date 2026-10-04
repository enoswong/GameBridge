#!/usr/bin/env python3
"""Exercise the native constructor in isolated fixture directories; no Wine prefix."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PointerProvisionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        output = ROOT / 'build' / 'compatibility'
        output.mkdir(parents=True, exist_ok=True)
        cls.build = tempfile.TemporaryDirectory(prefix='native-provision-', dir=output)
        cls.directory = Path(cls.build.name)
        cls.bridge = cls.directory / 'deskrawl-alpha.dylib'
        subprocess.run(['clang', '-arch', 'x86_64', '-dynamiclib', '-fobjc-arc', '-fblocks',
                        '-framework', 'Cocoa', '-framework', 'QuartzCore', '-framework', 'Metal',
                        str(ROOT / 'scripts/compatibility/deskrawl-alpha.m'), '-o', str(cls.bridge)], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(cls.bridge)], check=True, capture_output=True)
        main = cls.directory / 'main.c'
        main.write_text('int main(void) { return 0; }\n')
        cls.executable = cls.directory / 'fixture'
        subprocess.run(['clang', '-arch', 'x86_64', str(main), '-o', str(cls.executable)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=self.directory)
        self.directory_case = Path(self.temporary.name)
        self.prefix = self.directory_case / 'prefix'
        game = self.prefix / 'drive_c/game'
        game.mkdir(parents=True)
        self.game = game / 'Deskrawl.exe'
        shutil.copy2(self.executable, self.game)
        self.target = game / 'version.dll'
        self.ownership = game / 'version.dll.gamebridge-sha256'
        self.source = self.directory_case / 'pointer.dll'

    def tearDown(self):
        self.temporary.cleanup()

    def launch(self, payload=b'first trusted pointer', executable=None, digest=None):
        self.source.write_bytes(payload)
        environment = dict(os.environ, DYLD_INSERT_LIBRARIES=str(self.bridge),
                           GAMEBRIDGE_DESKRAWL_ALPHA='1', WINEPREFIX=str(self.prefix),
                           GAMEBRIDGE_DESKRAWL_POINTER=str(self.source),
                           GAMEBRIDGE_DESKRAWL_POINTER_SHA256=digest or hashlib.sha256(payload).hexdigest())
        subprocess.run([str(executable or self.game)], env=environment, check=True, capture_output=True)

    def test_owned_pointer_upgrades_on_next_launch(self):
        self.launch()
        self.launch(b'new trusted pointer')
        self.assertEqual(self.target.read_bytes(), b'new trusted pointer')
        self.assertEqual(self.ownership.read_text().strip(), hashlib.sha256(b'new trusted pointer').hexdigest())

    def test_unknown_pointer_is_preserved(self):
        self.target.write_bytes(b'foreign version DLL')
        self.launch()
        self.assertEqual(self.target.read_bytes(), b'foreign version DLL')
        self.assertFalse(self.ownership.exists())

    def test_modified_owned_pointer_is_preserved(self):
        self.launch()
        self.target.write_bytes(b'user replaced DLL')
        self.launch(b'new trusted pointer')
        self.assertEqual(self.target.read_bytes(), b'user replaced DLL')

    def test_identical_trusted_pointer_can_repair_missing_ownership(self):
        self.target.write_bytes(b'first trusted pointer')
        self.launch()
        self.assertTrue(self.ownership.exists(), 'Trusted installed DLL needs an ownership record')
        self.assertEqual(self.ownership.read_text().strip(), hashlib.sha256(b'first trusted pointer').hexdigest())

    def test_target_symlink_is_preserved(self):
        outside = self.directory_case / 'outside.dll'
        outside.write_bytes(b'foreign bytes')
        self.target.symlink_to(outside)
        self.launch()
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(outside.read_bytes(), b'foreign bytes')

    def test_ownership_symlink_never_authorizes_replacement(self):
        old = b'old user DLL'
        self.target.write_bytes(old)
        outside = self.directory_case / 'outside-record'
        outside.write_text(hashlib.sha256(old).hexdigest())
        self.ownership.symlink_to(outside)
        self.launch()
        self.assertEqual(self.target.read_bytes(), old)
        self.assertTrue(self.ownership.is_symlink())
        self.assertEqual(outside.read_text(), hashlib.sha256(old).hexdigest())

    def test_malformed_ownership_never_authorizes_replacement(self):
        self.target.write_bytes(b'old user DLL')
        self.ownership.write_text('not an ownership digest')
        self.launch()
        self.assertEqual(self.target.read_bytes(), b'old user DLL')
        self.assertEqual(self.ownership.read_text(), 'not an ownership digest')

    def test_invalid_digest_does_not_install(self):
        self.launch(digest='0' * 64)
        self.assertFalse(self.target.exists())

    def test_unrelated_process_does_not_install(self):
        other = self.game.with_name('Unrelated.exe')
        shutil.copy2(self.game, other)
        self.launch(executable=other)
        self.assertFalse(self.target.exists())

if __name__ == '__main__':
    unittest.main()
