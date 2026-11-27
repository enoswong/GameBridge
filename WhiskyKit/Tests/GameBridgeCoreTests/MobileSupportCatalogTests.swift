// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import GameBridgeCore
#if canImport(CryptoKit)
import CryptoKit

final class MobileSupportCatalogTests: XCTestCase {
    private let now = 1_800_000_000
    private let key = Curve25519.Signing.PrivateKey()

    private func payload(revision: Int = 1, expires: Int? = nil, badPath: Bool = false) -> [String: Any] {
        let hash = String(repeating: "a", count: 64)
        let suffix = String(repeating: "b", count: 40)
        let names = ["steam_win32.zip.", "bins_win32.zip.", "bins_win64_win32.zip."]
        let packages = names.enumerated().map { index, name in
            ["file": badPath && index == 0 ? "../bad.zip" : name + suffix,
             "bytes": 123, "sha256": hash] as [String: Any]
        }
        return ["schemaVersion": 1, "revision": revision, "issuedAt": now - 10,
                "expiresAt": expires ?? now + 3600, "packages": packages, "clientSHA256": hash]
    }

    private func envelope(_ payload: [String: Any], wrongKey: Bool = false) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signer = wrongKey ? Curve25519.Signing.PrivateKey() : key
        return try JSONSerialization.data(withJSONObject: [
            "keyID": "fixture", "payload": data.base64EncodedString(),
            "signature": try signer.signature(for: data).base64EncodedString()
        ])
    }

    private func verify(
        _ data: Data, revision: Int = 0, digest: String? = nil
    ) throws -> MobileSupportCatalog.Verified {
        try MobileSupportCatalog.verify(data, keyID: "fixture", publicKey: key.publicKey.rawRepresentation,
                                        now: now, minimumRevision: revision, acceptedDigest: digest)
    }

    func testValidCatalogAndSameRevision() throws {
        let data = try envelope(payload())
        let verified = try verify(data)
        XCTAssertEqual(verified.payload.revision, 1)
        XCTAssertEqual(verified.payload.packages.count, 3)
        XCTAssertEqual(try verify(data, revision: 1, digest: verified.digest).digest, verified.digest)
    }

    func testRejectWrongKey() throws {
        XCTAssertThrowsError(try verify(envelope(payload(), wrongKey: true)))
    }

    func testRejectExpired() throws {
        XCTAssertThrowsError(try verify(envelope(payload(expires: now))))
    }

    func testRejectPathAndRollback() throws {
        XCTAssertThrowsError(try verify(envelope(payload(badPath: true))))
        XCTAssertThrowsError(try verify(envelope(payload()), revision: 2))
    }

    func testRejectChangedRevisionPayload() throws {
        let first = try verify(envelope(payload()))
        XCTAssertThrowsError(try verify(envelope(payload(expires: now + 5000)),
                                        revision: 1, digest: first.digest))
    }
}
#endif

final class MobileSupportSignalTests: XCTestCase {
    func testSanitizedLoaderSignals() {
        XCTAssertEqual(MobileSupportSignals.signal(from: "err:module:import_dll Library ABC.dll not found"),
                       "missing:abc.dll")
        XCTAssertEqual(MobileSupportSignals.signal(from: "Fatal Error: Could not load module 'bin/vgui2_s.dll'"),
                       "load-failed:vgui2_s.dll")
        XCTAssertNil(MobileSupportSignals.signal(from: "Could not load module 'C:\\private\\secret.dll'"))
        XCTAssertNil(MobileSupportSignals.signal(from: "normal account login message"))
    }

    func testBoundedHistory() throws {
        let name = "GameBridge.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let signals = MobileSupportSignals(defaults: defaults)
        for index in 0..<40 { signals.record("err:module:import_dll Library test\(index).dll not found") }
        XCTAssertEqual(signals.recent().count, 32)
        signals.record("err:module:import_dll Library test39.dll not found")
        XCTAssertEqual(signals.recent().count, 32)
    }
}
