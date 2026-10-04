// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class BootstrapTests: XCTestCase {
    func testInstallerRejectsUntrustedURLsAndOversizedArtifacts() throws {
        var item = BootstrapInstaller(id: "steam", fileName: "SteamSetup.exe", url: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe", sha256: String(repeating: "a", count: 64), maximumBytes: 268435456)
        XCTAssertNoThrow(try item.validate())
        item.url = "https://evil.example/SteamSetup.exe"
        XCTAssertThrowsError(try item.validate())
        item.url = "http://cdn.akamai.steamstatic.com/file"
        XCTAssertThrowsError(try item.validate())
        item.url = "https://cdn.akamai.steamstatic.com/file"; item.fileName = "../SteamSetup.exe"
        XCTAssertThrowsError(try item.validate())
        item.fileName = "SteamSetup.exe"; item.maximumBytes = UInt64.max
        XCTAssertThrowsError(try item.validate())
    }
    func testCheckpointRequiresMatchingArtifactsBeforeSkippingInstall() throws {
        var state = BootstrapState(environmentID: "environment", engineID: "engine", completed: [:])
        XCTAssertFalse(state.contains("vc-x64", digest: "one"))
        state.completed["vc-x64"] = "one"
        XCTAssertTrue(state.contains("vc-x64", digest: "one"))
        XCTAssertFalse(state.contains("vc-x64", digest: "two"))
        let restored = try JSONDecoder().decode(BootstrapState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(restored.contains("vc-x64", digest: "one"))
    }
    func testCachedInstallerMustMatchHashAndRejectSymlink() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("installer.exe")
        let bytes = Data("verified installer".utf8)
        try bytes.write(to: path)
        XCTAssertTrue(try BootstrapInstaller.matches(path, digest: DigestTools.sha256(bytes), maximumBytes: 100))
        XCTAssertFalse(try BootstrapInstaller.matches(path, digest: String(repeating: "a", count: 64), maximumBytes: 100))
        let link = root.appendingPathComponent("link.exe")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
        XCTAssertThrowsError(try BootstrapInstaller.matches(link, digest: DigestTools.sha256(bytes), maximumBytes: 100))
    }
}
