import pathlib
import struct
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class NativeProbeBuildTests(unittest.TestCase):
    def test_builds_64_bit_windows_gui_without_crt(self):
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run(['bash', str(ROOT / 'scripts/build-mobile-native-probe.sh'), directory], check=True)
            path = pathlib.Path(directory, 'GameBridge-native-smoke-x64.exe')
            data = path.read_bytes()
            self.assertEqual(data[:2], b'MZ')
            pe = struct.unpack_from('<I', data, 0x3c)[0]
            self.assertEqual(data[pe:pe+4], b'PE\0\0')
            self.assertEqual(struct.unpack_from('<H', data, pe+4)[0], 0x8664)
            self.assertEqual(struct.unpack_from('<H', data, pe+24)[0], 0x20b)
            self.assertEqual(struct.unpack_from('<H', data, pe+24+68)[0], 2)
            self.assertNotIn(b'msvcrt.dll', data.lower())
            self.assertNotIn(b'ucrtbase.dll', data.lower())
            self.assertIn(b'KERNEL32.dll', data)
            self.assertIn(b'USER32.dll', data)

if __name__ == '__main__':
    unittest.main()
