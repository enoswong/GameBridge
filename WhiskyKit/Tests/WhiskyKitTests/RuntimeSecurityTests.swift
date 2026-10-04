// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import XCTest
@testable import WhiskyKit

final class RuntimeSecurityTests: XCTestCase {
    func testSignedPayloadIsVerifiedBeforeDecoding() throws {
        let key = Curve25519.Signing.PrivateKey()
        let bytes = Data("not JSON".utf8)
        let envelope = SignedEnvelope(keyID: "test", payload: bytes, signature: Data(repeating: 0, count: 64))
        let verifier = CatalogVerifier(trustedKeys: ["test": key.publicKey.rawRepresentation])
        XCTAssertThrowsError(try verifier.verify(envelope, now: Date(), previous: nil)) {
            XCTAssertEqual($0 as? RuntimeError, .invalidSignature)
        }
    }

    func testValidCatalogAndTampering() throws {
        let key = Curve25519.Signing.PrivateKey()
        let catalog = RuntimeFixture.catalog()
        let envelope = try RuntimeFixture.sign(catalog, key: key)
        let verifier = CatalogVerifier(trustedKeys: ["test": key.publicKey.rawRepresentation])
        XCTAssertEqual(try verifier.verify(envelope, now: RuntimeFixture.now, previous: nil).catalog.revision, 1)
        var tampered = envelope
        tampered.payload.append(32)
        XCTAssertThrowsError(try verifier.verify(tampered, now: RuntimeFixture.now, previous: nil))
    }

    func testUnknownKeyExpiredCatalogAndReplayAreRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = CatalogVerifier(trustedKeys: ["test": key.publicKey.rawRepresentation])
        var envelope = try RuntimeFixture.sign(RuntimeFixture.catalog(), key: key)
        envelope.keyID = "attacker"
        XCTAssertThrowsError(try verifier.verify(envelope, now: RuntimeFixture.now, previous: nil))
        envelope = try RuntimeFixture.sign(RuntimeFixture.catalog(), key: key)
        XCTAssertThrowsError(try verifier.verify(envelope, now: RuntimeFixture.now.addingTimeInterval(7200), previous: nil))
        let previous = CatalogState(revision: 2, payloadSHA256: String(repeating: "a", count: 64), revokedEngineIDs: [])
        XCTAssertThrowsError(try verifier.verify(envelope, now: RuntimeFixture.now, previous: previous))
    }

    func testEqualRevisionMustHaveIdenticalBytesAndRevocationsCannotDisappear() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = CatalogVerifier(trustedKeys: ["test": key.publicKey.rawRepresentation])
        let envelope = try RuntimeFixture.sign(RuntimeFixture.catalog(), key: key)
        let verified = try verifier.verify(envelope, now: RuntimeFixture.now, previous: nil)
        XCTAssertNoThrow(try verifier.verify(envelope, now: RuntimeFixture.now, previous: verified.state))
        var changed = RuntimeFixture.catalog()
        changed.expiresAt += 1
        XCTAssertThrowsError(try verifier.verify(RuntimeFixture.sign(changed, key: key), now: RuntimeFixture.now, previous: verified.state))
        changed.revision = 2
        let revoked = CatalogState(revision: 1, payloadSHA256: verified.state.payloadSHA256, revokedEngineIDs: ["old-engine"])
        XCTAssertThrowsError(try verifier.verify(RuntimeFixture.sign(changed, key: key), now: RuntimeFixture.now, previous: revoked))
    }

    func testManifestRejectsTraversalAndUnsupportedSchema() throws {
        var manifest = RuntimeFixture.manifest()
        for path in ["../wine", "/bin/sh", "bin/../../wine", "bin\\wine", "bin//wine", "bin/./wine"] {
            manifest.winePath = path
            XCTAssertThrowsError(try manifest.validate(), path)
        }
        manifest = RuntimeFixture.manifest()
        manifest.schemaVersion = 99
        XCTAssertThrowsError(try manifest.validate())
        manifest = RuntimeFixture.manifest()
        manifest.id = "../existing"
        XCTAssertThrowsError(try manifest.validate())
    }
}

enum RuntimeFixture {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static func manifest() -> EngineManifest {
        EngineManifest(schemaVersion: 1, id: "test-engine-1", version: "1.0.0", cpuMode: .rosettaX86_64,
                       minimumMacOS: "15.0.0", backends: [.dxmt], synchronizationModes: ["none"],
                       winePath: "bin/wine64", wineserverPath: "bin/wineserver",
                       archiveSHA256: String(repeating: "a", count: 64), archiveBytes: 4096,
                       unpackedBytes: 4096,
                       sources: [RuntimeSource(name: "fixture", url: "https://example.invalid/source",
                                               revision: String(repeating: "b", count: 40), license: "GPL-3.0-or-later")],
                       patchSHA256s: [], toolchain: "test-fixture-only", dependencySHA256s: [:],
                       testReferences: [], distribution: .internalOnly)
    }
    static func catalog() -> EngineCatalog {
        EngineCatalog(schemaVersion: 1, revision: 1, issuedAt: now.timeIntervalSince1970 - 60,
                      expiresAt: now.timeIntervalSince1970 + 3600, engines: [manifest()], revokedEngineIDs: [])
    }
    static func sign(_ catalog: EngineCatalog, key: Curve25519.Signing.PrivateKey) throws -> SignedEnvelope {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(catalog)
        return SignedEnvelope(keyID: "test", payload: payload, signature: try key.signature(for: payload))
    }
}
