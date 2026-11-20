// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class LegacyGameAuditTests: XCTestCase {
    func testDistinguishesGameFilesAnd32BitWineLibraries() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let games = root.appending(path: "game")
        let prefix = root.appending(path: "prefix")
        let windows = prefix.appending(path: "drive_c/windows")
        let wow64 = windows.appending(path: "syswow64")
        for directory in [games, wow64, windows.appending(path: "system32")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try fixture(is64Bit: false).write(to: games.appending(path: "game.exe"))
        try Data().write(to: wow64.appending(path: "mSvCr120.dll"))
        try Data().write(to: windows.appending(path: "system32/xinput1_3.dll"))
        try FileManager.default.createDirectory(
            at: games.appending(path: "xinput1_3.dll"), withIntermediateDirectories: false
        )

        let audit = try LegacyGameAudit.scan(directory: games, prefix: prefix)
        XCTAssertEqual(audit.executablesScanned, 1)
        XCTAssertEqual(audit.runtimeImports.compactMap(\.component), ["Visual C++ 2013", "DirectX June 2010"])
        XCTAssertEqual(audit.unresolvedImports.map(\.name), ["xinput1_3.dll"])
    }

    func testReadsDelayImportsFrom64BitImageAndReportsMalformedPE() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appending(path: "game.exe")
        let broken = root.appending(path: "broken.dll")
        try fixture(is64Bit: true).write(to: valid)
        try Data([0x4d, 0x5a]).write(to: broken)

        let imports = try WindowsImportReader.read(valid)
        XCTAssertEqual(imports.architecture, "x64")
        XCTAssertEqual(imports.libraries, ["msvcr120.dll", "xinput1_3.dll"])
        let audit = try LegacyGameAudit.scan(directory: root)
        XCTAssertEqual(audit.unreadableExecutables.map { URL(fileURLWithPath: $0).lastPathComponent }, ["broken.dll"])
        XCTAssertEqual(audit.unresolvedImports.count, 2)
    }

    func testAutomaticRepairChoosesTheNeededArchitectureAndSkipsPresentLibraries() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let game = root.appending(path: "game")
        let prefix = root.appending(path: "prefix")
        let system = prefix.appending(path: "drive_c/windows/system32")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        try fixture(is64Bit: false).write(to: game.appending(path: "game.exe"))
        try fixture(is64Bit: true).write(to: game.appending(path: "editor.exe"))
        try Data().write(to: system.appending(path: "xinput1_3.dll"))
        let report = try LegacyGameAudit.scan(directory: game, prefix: prefix)
        XCTAssertEqual(GameFileRepair.components(in: [report, report]), ["vc2013-x64", "vc2013-x86"])

        try Data().write(to: game.appending(path: "msvcr120.dll"))
        let repaired = try LegacyGameAudit.scan(directory: game, prefix: prefix)
        XCTAssertTrue(GameFileRepair.components(in: [repaired]).isEmpty)
    }

    func testCatalogPinsBothArchitecturesForEveryLegacyVersion() throws {
        let installers = LegacyVisualCpp.installers
        XCTAssertEqual(installers.count, 10)
        let identifiers = [2005, 2008, 2010, 2012, 2013].flatMap { ["vc\($0)-x86", "vc\($0)-x64"] }
        XCTAssertEqual(installers.map(\.id), identifiers)
        for installer in installers {
            XCTAssertNoThrow(try installer.validate())
            var modified = installer
            modified.sha256 = String(repeating: "0", count: 64)
            XCTAssertThrowsError(try modified.validate())
        }
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func fixture(is64Bit: Bool) -> Data {
        var data = Data(repeating: 0, count: 1024)
        let optional = 152
        let optionalSize = is64Bit ? 240 : 224
        let directory = optional + (is64Bit ? 112 : 96)
        let section = optional + optionalSize
        let fields: [(Int, Int)] = [
            (0, 0x5a4d), (0x3c, 128), (128, 0x4550), (132, is64Bit ? 0x8664 : 0x14c),
            (134, 1), (148, optionalSize), (optional, is64Bit ? 0x20b : 0x10b),
            (directory - 4, 16), (directory + 8, 0x1000), (directory + 12, 40),
            (directory + 104, 0x1040), (directory + 108, 64),
            (section + 12, 0x1000), (section + 16, 512), (section + 20, 512),
            (524, 0x10c0), (576, 1), (580, 0x10e0)
        ]
        for (offset, value) in fields {
            data[offset] = UInt8(truncatingIfNeeded: value)
            data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        }
        for (offset, name) in [(704, "MSVCR120.dll"), (736, "XINPUT1_3.dll")] {
            let bytes = Data(name.utf8)
            data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
        return data
    }
}
