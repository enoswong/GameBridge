#!/usr/bin/env python3
"""Host-independent negative checks for the LocalDebug bootstrap packager."""
import importlib.util
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bootstrap', Path(__file__).with_name('package-bootstrap.py'))
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapPackagingTests(unittest.TestCase):
    def test_unsafe_paths(self):
        for path in ('/file', '../file', 'a/../file', 'a//file', 'a/./file', 'a\\file', 'C:file', 'a\nfile', ''):
            with self.subTest(path=path), self.assertRaises(ValueError):
                bootstrap.safe_path(path)

    def test_tampered_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / 'file'; path.write_bytes(b'original')
            expected = bootstrap.digest(path)
            path.write_bytes(b'tampered')
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                bootstrap.verify_digest(path, expected)

    def test_symlink_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary).resolve() / 'target'; target.write_bytes(b'data')
            link = Path(temporary).resolve() / 'link'; link.symlink_to(target)
            with self.assertRaises(ValueError):
                bootstrap.digest(link)

    def test_release_gate(self):
        bootstrap.release_gate({'distribution': 'internalOnly'}, False)
        with self.assertRaisesRegex(ValueError, 'internalOnly'):
            bootstrap.release_gate({'distribution': 'internalOnly'}, True)
        with self.assertRaisesRegex(ValueError, 'notarization'):
            bootstrap.release_gate({'distribution': 'redistributable'}, True)

    def test_archive_rejects_link_or_user_prefix(self):
        for name, link in [('Libraries/wine', True), ('Users/me/save', False)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary).resolve() / 'runtime.tar'
                with tarfile.open(path, 'w') as archive:
                    entry = tarfile.TarInfo(name)
                    if link:
                        entry.type = tarfile.SYMTYPE; entry.linkname = 'target'
                        archive.addfile(entry)
                    else:
                        entry.size = 1; archive.addfile(entry, io.BytesIO(b'x'))
                engine = {'archiveSHA256': bootstrap.digest(path), 'archiveBytes': path.stat().st_size, 'unpackedBytes': 1, 'winePath': 'Libraries/wine', 'wineserverPath': 'Libraries/wineserver'}
                with self.assertRaises(ValueError):
                    bootstrap.validate_archive(path, engine)

    def test_installer_manifest_requires_pins_and_safe_names(self):
        items = [{'id': name, 'fileName': name + '.exe', 'url': 'https://example.com/' + name, 'sha256': hashlib.sha256(name.encode()).hexdigest(), 'maximumBytes': 1024} for name in ('steam', 'vc-x64', 'vc-x86', 'directx')]
        with tempfile.TemporaryDirectory() as temporary:
            manifest = Path(temporary).resolve() / 'installers.json'
            manifest.write_text(json.dumps(items))
            self.assertEqual(bootstrap.installers_from(manifest), items)
            items[0]['fileName'] = '../steam.exe'
            manifest.write_text(json.dumps(items))
            with self.assertRaises(ValueError):
                bootstrap.installers_from(manifest)


    def test_terms_require_complete_hashes_and_matching_installer_pins(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            terms = []
            for name, ids in [('microsoft-vc14-en.txt', ['vc-x64', 'vc-x86']), ('microsoft-directx-june2010-en.txt', ['directx'])]:
                path = directory / name; path.write_text('License text fixture. ' * 100)
                terms.append({'textFile': name, 'textSHA256': bootstrap.digest(path), 'installerIDs': ids})
            installers = [{'id': name, 'sha256': 'a' * 64} for name in ('vc-x64', 'vc-x86', 'directx')]
            provenance = {'terms': terms, 'installers': installers}
            (directory / 'provenance.json').write_text(json.dumps(provenance))
            self.assertEqual(len(bootstrap.terms_from(directory, installers)), 3)
            wrong_pins = [dict(item, sha256='b' * 64) for item in installers]
            with self.assertRaisesRegex(ValueError, 'pinned installers'):
                bootstrap.terms_from(directory, wrong_pins)
            (directory / 'microsoft-vc14-en.txt').write_text('Tampered')
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                bootstrap.terms_from(directory, installers)


if __name__ == '__main__':
    unittest.main()
