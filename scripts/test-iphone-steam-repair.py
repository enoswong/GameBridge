import importlib.util
import pathlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "repair", pathlib.Path(__file__).with_name("prepare-iphone-steam-repair.py"))
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


class RepairTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.stage = self.root / "stage"
        self.stage.mkdir()
        self.snapshot = self.root / "snapshot"
        self.snapshot.mkdir()

    def archive(self, entries):
        path = self.root / "fixture.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in entries:
                archive.writestr(name, data)
        return path

    def test_missing_only_and_executable_last(self):
        files = repair.extract_archives([self.archive([
            ("steam.exe", b"exe"), ("bin\\vgui2_s.dll", b"dll"), ("steamclient.dll", b"client")
        ])], self.stage)
        (self.snapshot / "steamclient.dll").write_bytes(b"client")
        self.assertEqual(repair.plan(self.snapshot, self.stage, files), ["bin/vgui2_s.dll", "steam.exe"])
        self.assertFalse((self.snapshot / "bin").exists())

    def test_newer_client_conflict(self):
        files = repair.extract_archives([self.archive([("steam.exe", b"old")])], self.stage)
        (self.snapshot / "steam.exe").write_bytes(b"new")
        with self.assertRaisesRegex(ValueError, "differs"):
            repair.plan(self.snapshot, self.stage, files)
        self.assertEqual((self.snapshot / "steam.exe").read_bytes(), b"new")

    def test_path_escape_rejected(self):
        with self.assertRaises(ValueError):
            repair.extract_archives([self.archive([("../escape.dll", b"bad")])], self.stage)

    def test_case_collision_rejected(self):
        with self.assertRaises(ValueError):
            repair.extract_archives([self.archive([("A.dll", b"one"), ("a.dll", b"two")])], self.stage)

    def test_symlink_rejected(self):
        files = repair.extract_archives([self.archive([("bin/a.dll", b"dll")])], self.stage)
        (self.snapshot / "bin").symlink_to(self.stage, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Linked"):
            repair.plan(self.snapshot, self.stage, files)


if __name__ == "__main__":
    unittest.main()
