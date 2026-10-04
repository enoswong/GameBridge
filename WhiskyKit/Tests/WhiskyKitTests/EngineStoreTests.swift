// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import XCTest
@testable import WhiskyKit

final class EngineStoreTests: XCTestCase {
    func testInstallIsImmutableAndWrongHashPreservesPreviousEngine() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let archive = root.appending(path: "engine.tar")
        let bytes = TarFixture.archive([("bin/wine64", Data("fixture-wine".utf8)), ("bin/wineserver", Data("fixture-server".utf8))])
        try bytes.write(to: archive)
        var manifest = RuntimeFixture.manifest()
        manifest.archiveSHA256 = DigestTools.sha256(bytes)
        manifest.archiveBytes = UInt64(bytes.count)
        var catalog = RuntimeFixture.catalog()
        catalog.engines = [manifest]
        let store = try EngineStore(root: root.appending(path: "store"), trustedKeys: ["test": key.publicKey.rawRepresentation])
        let installed = try await store.install(engineID: manifest.id, envelope: RuntimeFixture.sign(catalog, key: key), archive: archive, now: RuntimeFixture.now)
        XCTAssertEqual(try Data(contentsOf: installed.directory.appending(path: "bin/wine64")), Data("fixture-wine".utf8))
        let duplicate = try await store.install(engineID: manifest.id, envelope: RuntimeFixture.sign(catalog, key: key), archive: archive, now: RuntimeFixture.now)
        XCTAssertEqual(duplicate.directory, installed.directory)
        catalog.revision = 2
        catalog.engines[0].id = "bad-engine"
        try Data("corrupt".utf8).write(to: archive)
        do {
            _ = try await store.install(engineID: "bad-engine", envelope: RuntimeFixture.sign(catalog, key: key), archive: archive, now: RuntimeFixture.now)
            XCTFail("Corrupted archive was accepted")
        } catch { XCTAssertEqual(error as? RuntimeError, .archiveHashMismatch) }
        XCTAssertEqual(try Data(contentsOf: installed.directory.appending(path: "bin/wine64")), Data("fixture-wine".utf8))
        let entries = try await store.installedEngines()
        XCTAssertEqual(entries.map(\.manifest.id), [manifest.id])
        let reopened = try EngineStore(root: root.appending(path: "store"), trustedKeys: ["test": key.publicKey.rawRepresentation])
        let recovered = try await reopened.installedEngines()
        XCTAssertEqual(recovered.count, 1)
    }

    func testArchiveRejectsTraversalLinksTruncationAndSizeLimit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, type) in [("../escape", UInt8(48)), ("/tmp/escape", 48), ("link", 50), ("hard", 49), ("device", 51)] {
            let archive = root.appending(path: UUID().uuidString)
            try TarFixture.archive([(name, Data("x".utf8))], type: type).write(to: archive)
            let output = root.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            XCTAssertThrowsError(try SafeTarExtractor.extract(archive: archive, into: output, maximumBytes: 100))
        }
        let archive = root.appending(path: "truncated.tar")
        try TarFixture.archive([("large", Data(repeating: 65, count: 1024))]).prefix(600).write(to: archive)
        let output = root.appending(path: "out")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        XCTAssertThrowsError(try SafeTarExtractor.extract(archive: archive, into: output, maximumBytes: 100))
    }

    func testFileLockRejectsSecondWriterAndReleases() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "writer.lock")
        var first: ExclusiveFileLock? = try ExclusiveFileLock(url: url)
        XCTAssertThrowsError(try ExclusiveFileLock(url: url))
        XCTAssertNotNil(first)
        first = nil
        XCTAssertNoThrow(try ExclusiveFileLock(url: url))
    }
}

func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "GameBridgeTests-" + UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

enum TarFixture {
    static func archive(_ entries: [(String, Data)], type: UInt8 = 48) -> Data {
        var result = Data()
        for (name, contents) in entries {
            var header = [UInt8](repeating: 0, count: 512)
            func field(_ text: String, _ offset: Int) {
                for (index, byte) in text.utf8.enumerated() { header[offset + index] = byte }
            }
            field(name, 0); field("0000755", 100); field(String(format: "%011o", contents.count), 124)
            field("ustar", 257); field("00", 263); header[156] = type
            for index in 148..<156 { header[index] = 32 }
            let checksum = header.reduce(0) { $0 + Int($1) }
            field(String(format: "%06o", checksum), 148); header[154] = 0; header[155] = 32
            result.append(contentsOf: header); result.append(contents)
            result.append(Data(repeating: 0, count: (512 - contents.count % 512) % 512))
        }
        result.append(Data(repeating: 0, count: 1024))
        return result
    }
}
