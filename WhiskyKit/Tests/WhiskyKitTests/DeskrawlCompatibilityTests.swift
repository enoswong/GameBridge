// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class DeskrawlCompatibilityTests: XCTestCase {
    func testAbsentProfileDoesNotChangeLaunch() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(try DeskrawlCompatibility.environment(prefix: root.appendingPathComponent("prefix"), engineID: "engine").isEmpty)
    }
    func testProvisionedProfileIsBoundToEngineAndBothFileDigests() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appendingPathComponent("prefix")
        let directory = root.appendingPathComponent("Compatibility")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bridge = directory.appendingPathComponent("deskrawl-alpha.dylib")
        let pointer = prefix.appendingPathComponent(DeskrawlCompatibility.pointerPath)
        try FileManager.default.createDirectory(at: pointer.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("local-test-artifact".utf8)
        try bytes.write(to: bridge); try bytes.write(to: pointer)
        let profile = DeskrawlCompatibility.Profile(schema: 1, engineID: "engine", bridgeSHA256: DigestTools.sha256(bytes), pointerSHA256: DigestTools.sha256(bytes))
        try JSONEncoder().encode(profile).write(to: directory.appendingPathComponent("deskrawl-v1.json"))
        let env = try DeskrawlCompatibility.environment(prefix: prefix, engineID: "engine")
        XCTAssertEqual(env["DYLD_INSERT_LIBRARIES"], bridge.path)
        XCTAssertEqual(env["GAMEBRIDGE_DESKRAWL_ALPHA"], "1")
        XCTAssertNil(env["GAMEBRIDGE_ALPHA_TRACE"])
        XCTAssertThrowsError(try DeskrawlCompatibility.environment(prefix: prefix, engineID: "other-engine"))
        try Data("changed".utf8).write(to: pointer)
        XCTAssertThrowsError(try DeskrawlCompatibility.environment(prefix: prefix, engineID: "engine"))
        try bytes.write(to: pointer)
        try FileManager.default.removeItem(at: bridge)
        try FileManager.default.createSymbolicLink(at: bridge, withDestinationURL: pointer)
        XCTAssertThrowsError(try DeskrawlCompatibility.environment(prefix: prefix, engineID: "engine"))
    }
    func testBundledProfileWorksBeforeGameInstallationAndRejectsTampering() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Compatibility")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data("bundled component".utf8)
        for file in ["deskrawl-alpha.dylib", "deskrawl-pointer.dll"] { try bytes.write(to: directory.appendingPathComponent(file)) }
        let profile = DeskrawlCompatibility.Profile(schema: 2, engineID: "engine", bridgeSHA256: DigestTools.sha256(bytes), pointerSHA256: DigestTools.sha256(bytes))
        try JSONEncoder().encode(profile).write(to: directory.appendingPathComponent("deskrawl-v1.json"))
        let prefix = root.appendingPathComponent("prefix")
        let env = try DeskrawlCompatibility.environment(prefix: prefix, engineID: "engine")
        XCTAssertEqual(env["GAMEBRIDGE_DESKRAWL_POINTER"], directory.appendingPathComponent("deskrawl-pointer.dll").path)
        XCTAssertEqual(env["GAMEBRIDGE_DESKRAWL_POINTER_SHA256"], DigestTools.sha256(bytes))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prefix.path))
        try Data("tampered".utf8).write(to: directory.appendingPathComponent("deskrawl-pointer.dll"))
        XCTAssertThrowsError(try DeskrawlCompatibility.environment(prefix: prefix, engineID: "engine"))
    }

    func testOrdinaryLaunchProvisionsOldEnvironmentAndPreservesExplicitProfile() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let bytes = Data("verified compatibility".utf8)
        for name in ["bridge", "pointer"] { try bytes.write(to: bundle.appendingPathComponent(name)) }
        let installers = [("steam", "SteamSetup.exe", "https://cdn.akamai.steamstatic.com/a"),
                          ("vc-x64", "VC_redist.x64.exe", "https://aka.ms/a"),
                          ("vc-x86", "VC_redist.x86.exe", "https://aka.ms/a"),
                          ("directx", "directx_Jun2010_redist.exe", "https://download.microsoft.com/a")].map {
            BootstrapInstaller(id: $0.0, fileName: $0.1, url: $0.2, sha256: DigestTools.sha256(bytes), maximumBytes: 100)
        }
        let payload = BootstrapPayload(schema: 1, engineID: "engine", catalogFile: "catalog", trustKeysFile: "keys", archiveFile: "archive", bridgeFile: "bridge", bridgeSHA256: DigestTools.sha256(bytes), pointerFile: "pointer", pointerSHA256: DigestTools.sha256(bytes), installers: installers)
        try JSONEncoder().encode(payload).write(to: bundle.appendingPathComponent("bootstrap.json"))
        let prefix = root.appendingPathComponent("environment/prefix")
        XCTAssertFalse(try DeskrawlCompatibility.prepareBundled(prefix: prefix, engineID: "other", directory: bundle))
        XCTAssertTrue(try DeskrawlCompatibility.environment(prefix: prefix, engineID: "engine").isEmpty)
        XCTAssertTrue(try DeskrawlCompatibility.prepareBundled(prefix: prefix, engineID: "engine", directory: bundle))
        XCTAssertEqual(try DeskrawlCompatibility.environment(prefix: prefix, engineID: "engine")["GAMEBRIDGE_DESKRAWL_ALPHA"], "1")
        let gameDLL = prefix.appendingPathComponent(DeskrawlCompatibility.pointerPath)
        try FileManager.default.createDirectory(at: gameDLL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: gameDLL)
        let profileURL = prefix.deletingLastPathComponent().appendingPathComponent("Compatibility/deskrawl-v1.json")
        let legacy = DeskrawlCompatibility.Profile(schema: 1, engineID: "engine", bridgeSHA256: DigestTools.sha256(bytes), pointerSHA256: DigestTools.sha256(bytes))
        let legacyBytes = try JSONEncoder().encode(legacy)
        try legacyBytes.write(to: profileURL)
        XCTAssertFalse(try DeskrawlCompatibility.prepareBundled(prefix: prefix, engineID: "engine", directory: bundle))
        XCTAssertEqual(try Data(contentsOf: profileURL), legacyBytes)
    }

}
