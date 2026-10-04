// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class DXMTProvisionerTests: XCTestCase {
    func testProvisionCopiesNativeDLLsAndRejectsTamperBeforeWrites() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var manifest = RuntimeFixture.manifest()
        var hashes: [String: String] = [:]
        for path in DXMTProvisioner.requiredPaths {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var bytes = Data(repeating: 0, count: 256)
            bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[0x3c] = 128
            bytes[128] = 0x50; bytes[129] = 0x45; bytes[132] = 0x64; bytes[133] = 0x86
            if path.hasSuffix("winemetal.dll") { bytes.replaceSubrange(64..<81, with: Data("Wine builtin DLL\0".utf8)) }
            try bytes.write(to: file)
            hashes[path] = DigestTools.sha256(bytes)
        }
        manifest.dxmtFileSHA256s = hashes
        let engine = InstalledEngine(manifest: manifest, directory: root, catalogRevision: 1)
        let prefix = root.appending(path: "prefix")
        for name in ["system32", "syswow64"] {
            try FileManager.default.createDirectory(at: prefix.appending(path: "drive_c/windows/" + name), withIntermediateDirectories: true)
        }
        try DXMTProvisioner.provision(engine: engine, prefix: prefix)
        let target = prefix.appending(path: "drive_c/windows/system32/d3d11.dll")
        let expected = try Data(contentsOf: target)
        try Data("tampered".utf8).write(to: root.appending(path: "Libraries/DXMT/x32/dxgi.dll"))
        XCTAssertThrowsError(try DXMTProvisioner.provision(engine: engine, prefix: prefix))
        XCTAssertEqual(try Data(contentsOf: target), expected)
        XCTAssertTrue(DXMTProvisioner.overrides.contains("d3d11,dxgi,d3d10core=n"))
    }

    func testMissingOrTamperedPayloadCannotModifyPrefix() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appending(path: "prefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let marker = prefix.appending(path: "keep")
        try Data("unchanged".utf8).write(to: marker)
        let engine = InstalledEngine(manifest: RuntimeFixture.manifest(), directory: root, catalogRevision: 1)
        XCTAssertThrowsError(try DXMTProvisioner.provision(engine: engine, prefix: prefix))
        XCTAssertEqual(try Data(contentsOf: marker), Data("unchanged".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: prefix.path), ["keep"])
    }
}
