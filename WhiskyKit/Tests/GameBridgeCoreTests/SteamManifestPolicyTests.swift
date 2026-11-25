// SPDX-License-Identifier: GPL-3.0-or-later
import GameBridgeCore
import XCTest

final class SteamManifestPolicyTests: XCTestCase {
    func testOnlyInstalledOrDamagedWindowsGamesAreInspected() {
        XCTAssertTrue(SteamManifestPolicy.shouldInspect(appID: 10, stateFlags: 4, isWindows: true))
        XCTAssertTrue(SteamManifestPolicy.shouldInspect(appID: 10, stateFlags: 36, isWindows: true))
        XCTAssertTrue(SteamManifestPolicy.shouldInspect(appID: 10, stateFlags: 128, isWindows: true))
        XCTAssertFalse(SteamManifestPolicy.shouldInspect(appID: 10, stateFlags: 2, isWindows: true))
        XCTAssertFalse(SteamManifestPolicy.shouldInspect(appID: 10, stateFlags: 4, isWindows: false))
        XCTAssertFalse(SteamManifestPolicy.shouldInspect(appID: 228980, stateFlags: 4, isWindows: true))
        XCTAssertFalse(SteamManifestPolicy.shouldInspect(appID: 0, stateFlags: 4, isWindows: true))
    }
}
