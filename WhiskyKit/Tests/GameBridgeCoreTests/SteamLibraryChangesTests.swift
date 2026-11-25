// SPDX-License-Identifier: GPL-3.0-or-later
import GameBridgeCore
import XCTest

final class SteamLibraryChangesTests: XCTestCase {
    func testNewUpdatedRemovedAndDamagedGames() {
        let before = [
            revision(10, "1"), revision(20, "1"), revision(30, "1"), revision(40, "1")
        ]
        let after = [
            revision(10, "2"), revision(20, "1", damaged: true), revision(40, "1"), revision(50, "1")
        ]
        XCTAssertEqual(SteamLibraryChanges.changedAppIDs(before: before, after: after), [10, 20, 30, 50])
    }

    func testUnchangedReorderedLibraryDoesNotScheduleRepair() {
        let before = [revision(10, "1"), revision(20, "2")]
        XCTAssertTrue(SteamLibraryChanges.changedAppIDs(before: before, after: Array(before.reversed())).isEmpty)
    }

    func testDamageFlagAndBuildIDChangesAreObserved() {
        let before = [revision(10, nil)]
        XCTAssertEqual(SteamLibraryChanges.changedAppIDs(before: before, after: [revision(10, "1")]), [10])
        XCTAssertEqual(
            SteamLibraryChanges.changedAppIDs(before: before, after: [revision(10, nil, damaged: true)]), [10]
        )
    }

    private func revision(_ appID: UInt32, _ buildID: String?, damaged: Bool = false) -> SteamManifestRevision {
        SteamManifestRevision(appID: appID, buildID: buildID,
                              stateFlags: damaged ? 32 : 4, needsVerification: damaged)
    }
}
