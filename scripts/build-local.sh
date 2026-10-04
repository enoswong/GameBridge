#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
mkdir -p build/evidence
# This is an unsigned local Debug build. Release never permits this lint skip.
xcodebuild \
  -project Whisky.xcodeproj \
  -scheme Whisky \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/local \
  -clonedSourcePackagesDirPath build/baseline/SourcePackages \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  GAMEBRIDGE_SKIP_LINT=YES \
  build > build/evidence/gamebridge-build.log 2>&1 || {
    tail -80 build/evidence/gamebridge-build.log
    exit 1
  }
tail -10 build/evidence/gamebridge-build.log
printf 'Local app: %s/build/local/Build/Products/Debug/GameBridge.app\n' "$repo_root"
