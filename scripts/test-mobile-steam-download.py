#!/usr/bin/env python3
"""Offline regression tests for the official archive transfer policy."""
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "diagnose_mobile_steam", pathlib.Path(__file__).with_name("diagnose-mobile-steam.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DownloadTests(unittest.TestCase):
    def exercise(self, responses, succeeds, delays):
        with tempfile.TemporaryDirectory() as folder:
            target = pathlib.Path(folder) / "archive.zip"
            target.write_bytes(b"stale")
            answers = iter(responses)

            def curl(args, **kwargs):
                self.assertFalse(target.exists(), "Previous partial transfer retained")
                self.assertEqual(args[-1], module.ORIGIN + "archive.zip")
                self.assertEqual(args[args.index("--max-filesize") + 1], "100")
                self.assertIn("--fail", args)
                self.assertEqual(args[args.index("--proto") + 1], "=https")
                code, status = next(answers)
                target.write_bytes(b"complete" if code == 0 else b"partial")
                return subprocess.CompletedProcess(args, code, status, "")

            with patch.object(module.subprocess, "run", side_effect=curl) as run, \
                 patch.object(module.time, "sleep") as sleep:
                if succeeds:
                    module.download_archive("archive.zip", 100, target)
                    self.assertEqual(target.read_bytes(), b"complete")
                else:
                    with self.assertRaises(RuntimeError):
                        module.download_archive("archive.zip", 100, target)
                    self.assertFalse(target.exists())
                self.assertEqual(run.call_count, len(responses))
                self.assertEqual([call.args[0] for call in sleep.call_args_list], delays)

    def test_proxy_504_then_success(self):
        self.exercise([(56, "000 504"), (0, "200 200")], True, [5])

    def test_http_504_then_success(self):
        self.exercise([(22, "504 000"), (0, "200 000")], True, [5])

    def test_transport_failure_then_success(self):
        self.exercise([(56, "200 200"), (0, "200 200")], True, [5])

    def test_retry_exhausted(self):
        self.exercise([(56, "000 504")] * 3, False, [5, 10])

    def test_permanent_not_found(self):
        self.exercise([(22, "404 000")], False, [])

    def test_certificate_failure(self):
        self.exercise([(60, "000 200")], False, [])

    def test_size_limit(self):
        self.exercise([(63, "200 200")], False, [])

    def test_proxy_authentication_failure(self):
        self.exercise([(56, "000 407")], False, [])


if __name__ == "__main__":
    unittest.main()
