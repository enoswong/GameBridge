#!/usr/bin/env python3
"""Local-only preflight for an already development-signed iPhone research app."""
import argparse
import datetime as dt
import pathlib
import plistlib
import subprocess
import sys
import tempfile

BUNDLE_ID = "org.enostudio.gamebridge.research"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def matches_app_id(pattern, actual):
    if not isinstance(pattern, str) or not isinstance(actual, str):
        return False
    if "*" not in pattern:
        return pattern == actual
    return pattern.endswith(".*") and pattern.count("*") == 1 and actual.startswith(pattern[:-1])


def check_profile(profile, signed, bundle, leaf, device=None, main=False, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    expires = profile.get("ExpirationDate")
    require(isinstance(expires, dt.datetime), "Missing profile expiration")
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=dt.timezone.utc)
    require(expires > now, "Development profile has expired")
    permitted = profile.get("Entitlements", {})
    require(permitted.get("get-task-allow") is True, "Not a development provisioning profile")
    devices = profile.get("ProvisionedDevices", [])
    require(isinstance(devices, list) and bool(devices), "No development devices in profile")
    if device is not None:
        require(device in devices, "Target iPhone is not provisioned")
    teams = profile.get("TeamIdentifier", [])
    team = signed.get("com.apple.developer.team-identifier")
    require(isinstance(team, str) and team in teams, "Signing team does not match profile")
    require(permitted.get("com.apple.developer.team-identifier", team) == team,
            "Profile team entitlement does not match")
    actual = signed.get("application-identifier")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    require(isinstance(actual, str) and any(actual == p + "." + bundle for p in prefixes),
            "Signed application identifier does not match bundle")
    require(matches_app_id(permitted.get("application-identifier"), actual),
            "Profile does not authorize signed application identifier")
    require(isinstance(leaf, bytes) and leaf in profile.get("DeveloperCertificates", []),
            "Signing certificate is not in provisioning profile")
    if main:
        require(signed.get("get-task-allow") is True, "Main app cannot be debugged")
    return expires.date().isoformat()


def command(*args):
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        # Never echo potentially identifying tool output or credentials.
        raise ValueError("Local " + pathlib.Path(args[0]).name + " verification failed")
    return result.stdout


def inspect_bundle(path, expected, device, main=False):
    require(path.is_dir() and not path.is_symlink(), "Missing or linked app/extension")
    with (path / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("CFBundleIdentifier") == expected, "Unexpected bundle identity")
    profile_path = path / "embedded.mobileprovision"
    require(profile_path.is_file(), "Missing embedded development profile")
    profile = plistlib.loads(command("/usr/bin/security", "cms", "-D", "-i", str(profile_path)))
    signed = plistlib.loads(command("/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)))
    with tempfile.TemporaryDirectory(prefix="gamebridge-signature-") as tmp:
        prefix = str(pathlib.Path(tmp) / "certificate")
        command("/usr/bin/codesign", "-d", "--extract-certificates", prefix, str(path))
        leaf = pathlib.Path(prefix + "0").read_bytes()
        expiry = check_profile(profile, signed, expected, leaf, device, main)
    print(expected + ": development profile valid until " + expiry)
    if main:
        # These are requested capabilities, not a proof of working JIT or memory allocation.
        for key in ("com.apple.security.cs.allow-jit",
                    "com.apple.developer.kernel.extended-virtual-addressing",
                    "com.apple.developer.kernel.increased-memory-limit"):
            state = "present" if signed.get(key) is True else "absent"
            print(key + ": " + state)


def inspect_app(path, device):
    require(sys.platform == "darwin", "Run on a Mac with Apple's signing tools")
    require(path.is_dir() and path.suffix == ".app" and not path.is_symlink(),
            "Provide the already development-signed .app directory")
    command("/usr/bin/codesign", "--verify", "--deep", "--strict", str(path))
    inspect_bundle(path, BUNDLE_ID, device, main=True)
    for extension in ("JITHelper", "MemoryHost"):
        child = path / "PlugIns" / ("Madeira" + extension + ".appex")
        inspect_bundle(child, BUNDLE_ID + "." + extension, device)
    print("Local signature/profile checks passed.")
    if device is None:
        print("Specific iPhone provisioning was not checked (no --device supplied).")
    print("Not an install, JIT, login or gameplay test.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--device", help="Optional local target UDID; never printed or uploaded")
    args = parser.parse_args()
    try:
        inspect_app(args.app, args.device)
    except (ValueError, OSError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        # Fixed diagnostic for IO/parse errors: paths/profile data may be private.
        print("Preflight failed: " + (str(error) if type(error) is ValueError else "invalid or missing local input"),
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
