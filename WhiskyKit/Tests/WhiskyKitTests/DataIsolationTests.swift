// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class DataIsolationTests: XCTestCase {
    // A helper or test bundle must not redirect GameBridge's runtime to its own namespace.
    func testRuntimeUsesGameBridgeNamespaceUnderForeignBundle() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(WhiskyWineInstaller.applicationFolder,
                       support.appending(path: "com.enos.GameBridge"))
    }

    // The CLI and GUI must discover the same bottle registry rather than per-executable registries.
    func testBottleRegistryUsesSharedGameBridgeNamespace() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(BottleData.bottleEntriesDir,
                       home.appending(path: "Library/Containers/com.enos.GameBridge/BottleVM.plist"))
        XCTAssertEqual(BottleData.defaultBottleDir,
                       home.appending(path: "Library/Containers/com.enos.GameBridge/Bottles"))
    }

    // Log cleanup must select this product's directory, never Whisky's directory.
    func testLogsStayInsideGameBridgeNamespace() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(Wine.logsFolder, library.appending(path: "Logs/com.enos.GameBridge"))
    }
}
