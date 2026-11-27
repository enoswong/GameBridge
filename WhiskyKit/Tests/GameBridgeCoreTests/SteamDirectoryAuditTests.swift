// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GameBridgeCore
import XCTest

final class SteamDirectoryAuditTests: XCTestCase {
    func testSharedClassification() {
        XCTAssertEqual(RuntimeDependencyPolicy.component(for: "MSVCR80.dll"), "Visual C++ 2005")
        XCTAssertEqual(RuntimeDependencyPolicy.component(for: "msvcp120.dll"), "Visual C++ 2013")
        XCTAssertEqual(RuntimeDependencyPolicy.component(for: "vcruntime140_1.dll"), "Visual C++ v14")
        XCTAssertEqual(RuntimeDependencyPolicy.component(for: "d3dx9_43.dll"), "DirectX June 2010")
        XCTAssertEqual(RuntimeDependencyPolicy.component(for: "openal32.dll"), "OpenAL")
        XCTAssertNil(RuntimeDependencyPolicy.component(for: "steam_api64.dll"))
    }

    func testMissingLibraryAndBoundedScan() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = try SteamDirectoryAudit.scan(prefix: root)
        XCTAssertTrue(empty.reports.isEmpty)
        XCTAssertFalse(empty.isPartial)
        let library = root.appending(path: "drive_c/Program Files/Steam Big Picture/steamapps/common")
        for name in ["a", "b"] {
            let folder = library.appending(path: name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([0x4d, 0x5a]).write(to: folder.appending(path: "invalid.exe"))
        }
        let audit = try SteamDirectoryAudit.scan(prefix: root, maxGames: 1)
        XCTAssertEqual(audit.reports.count, 1)
        XCTAssertEqual(audit.skippedDirectories, 1)
        XCTAssertTrue(audit.isPartial)
        XCTAssertEqual(audit.reports.first?.unreadableExecutables.count, 1)
    }

    func testLinkedLibraryIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appending(path: "drive_c/Program Files/Steam Big Picture/steamapps")
        let external = root.appending(path: "outside")
        for folder in [parent, external] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: parent.appending(path: "common"), withDestinationURL: external)
        XCTAssertThrowsError(try SteamDirectoryAudit.scan(prefix: root))
    }
}
