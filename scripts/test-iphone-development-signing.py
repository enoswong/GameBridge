#!/usr/bin/env python3
"""Synthetic profile tests; no Apple identity or device data is used."""
import datetime as dt
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "preflight", pathlib.Path(__file__).with_name("check-iphone-development-signing.py"))
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        self.bundle = preflight.BUNDLE_ID
        self.signed = {
            "get-task-allow": True,
            "application-identifier": "TESTTEAM." + self.bundle,
            "com.apple.developer.team-identifier": "TESTTEAM",
        }
        self.profile = {
            "ExpirationDate": self.now + dt.timedelta(days=7),
            "TeamIdentifier": ["TESTTEAM"],
            "ApplicationIdentifierPrefix": ["TESTTEAM"],
            "ProvisionedDevices": ["fixture-device"],
            "DeveloperCertificates": [b"fixture-leaf"],
            "Entitlements": {"get-task-allow": True, "application-identifier": "TESTTEAM.*"},
        }

    def check(self, **overrides):
        args = dict(profile=self.profile, signed=self.signed, bundle=self.bundle,
                    leaf=b"fixture-leaf", device="fixture-device", main=True, now=self.now)
        args.update(overrides)
        return preflight.check_profile(**args)

    def test_valid_development_profile(self):
        self.assertEqual(self.check(), "2026-01-08")

    def test_expired(self):
        self.profile["ExpirationDate"] = self.now
        with self.assertRaisesRegex(ValueError, "expired"):
            self.check()

    def test_distribution_profile_rejected(self):
        self.profile["Entitlements"]["get-task-allow"] = False
        with self.assertRaisesRegex(ValueError, "development"):
            self.check()

    def test_no_debugging_rejected(self):
        self.signed["get-task-allow"] = False
        with self.assertRaisesRegex(ValueError, "debugged"):
            self.check()

    def test_wrong_device_rejected(self):
        with self.assertRaisesRegex(ValueError, "not provisioned"):
            self.check(device="other-fixture")

    def test_wrong_certificate_rejected(self):
        with self.assertRaisesRegex(ValueError, "certificate"):
            self.check(leaf=b"unrelated-certificate")

    def test_wrong_team_rejected(self):
        self.signed["com.apple.developer.team-identifier"] = "WRONGTEAM"
        with self.assertRaisesRegex(ValueError, "team"):
            self.check()

    def test_wrong_bundle_rejected(self):
        with self.assertRaisesRegex(ValueError, "identifier"):
            self.check(bundle="com.other.app")

    def test_wrong_profile_identifier_rejected(self):
        self.profile["Entitlements"]["application-identifier"] = "TESTTEAM.com.other.app"
        with self.assertRaisesRegex(ValueError, "authorize"):
            self.check()

    def test_exact_identifier_allowed(self):
        self.profile["Entitlements"]["application-identifier"] = self.signed["application-identifier"]
        self.assertEqual(self.check(), "2026-01-08")


if __name__ == "__main__":
    unittest.main()
