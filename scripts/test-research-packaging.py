#!/usr/bin/env python3
import importlib.util
import io
import tarfile
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('packaging', Path(__file__).with_name('prepare-research-runtime.py'))
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


def archive(entries):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode='w') as handle:
        for name, payload, target in entries:
            info = tarfile.TarInfo(name)
            if target is not None:
                info.type = tarfile.SYMTYPE
                info.linkname = target
                handle.addfile(info)
            else:
                info.size = len(payload)
                info.mode = 0o755
                handle.addfile(info, io.BytesIO(payload))
    raw.seek(0)
    return raw


class PackagingTests(unittest.TestCase):
    def test_contained_links_become_regular_files(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / 'runtime.tar'
            packaging.normalize_tar(archive([('bin/wine', b'executable', None), ('bin/wine64', b'', 'wine')]), out, 'fixture')
            with tarfile.open(out) as result:
                self.assertTrue(result.getmember('bin/wine64').isfile())
                self.assertEqual(result.extractfile('bin/wine64').read(), b'executable')

    def test_unsafe_paths_and_links_fail_closed(self):
        cases = [ [('bin/wine', b'', '../../outside')], [('bin/wine', b'', '/bin/sh')],
                  [('bin/a', b'', 'b'), ('bin/b', b'', 'a')], [('../wine', b'bad', None)],
                  [('Wine', b'a', None), ('wine', b'b', None)] ]
        for entries in cases:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    packaging.normalize_tar(archive(entries), Path(directory) / 'runtime.tar', 'fixture')

    def test_expansion_limit_counts_materialized_links(self):
        with tempfile.TemporaryDirectory() as directory:
            old = packaging.MAX_BYTES
            packaging.MAX_BYTES = 10
            try:
                with self.assertRaises(ValueError):
                    packaging.normalize_tar(archive([('file', b'123456', None), ('copy', b'', 'file')]), Path(directory) / 'runtime.tar', 'fixture')
            finally:
                packaging.MAX_BYTES = old


if __name__ == '__main__':
    unittest.main()
