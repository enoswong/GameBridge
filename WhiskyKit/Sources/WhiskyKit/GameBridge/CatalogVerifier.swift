// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

public struct SignedEnvelope: Codable, Sendable {
    public var keyID: String
    public var payload: Data
    public var signature: Data
}
public struct EngineCatalog: Codable, Sendable {
    public var schemaVersion: Int
    public var revision: UInt64
    public var issuedAt: TimeInterval
    public var expiresAt: TimeInterval
    public var engines: [EngineManifest]
    public var revokedEngineIDs: [String]
}
public struct CatalogState: Codable, Sendable {
    public var revision: UInt64
    public var payloadSHA256: String
    public var revokedEngineIDs: [String]
}
public struct VerifiedCatalog: Sendable {
    public let catalog: EngineCatalog
    public let state: CatalogState
    public let envelope: SignedEnvelope
    // Only the verifier can create trusted results.
    fileprivate init(catalog: EngineCatalog, state: CatalogState, envelope: SignedEnvelope) {
        self.catalog = catalog; self.state = state; self.envelope = envelope
    }
}
public struct CatalogVerifier: Sendable {
    private let trustedKeys: [String: Data]
    public init(trustedKeys: [String: Data]) { self.trustedKeys = trustedKeys }

    public func verify(_ envelope: SignedEnvelope, now: Date, previous: CatalogState?) throws -> VerifiedCatalog {
        guard let bytes = trustedKeys[envelope.keyID] else { throw RuntimeError.unknownKey }
        guard envelope.payload.count <= 4 * 1024 * 1024, envelope.signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes),
              key.isValidSignature(envelope.signature, for: envelope.payload)
        else { throw RuntimeError.invalidSignature }
        guard let catalog = try? JSONDecoder().decode(EngineCatalog.self, from: envelope.payload),
              catalog.schemaVersion == 1, catalog.revision > 0,
              catalog.issuedAt.isFinite, catalog.expiresAt.isFinite,
              catalog.issuedAt <= now.timeIntervalSince1970 + 300,
              catalog.expiresAt > catalog.issuedAt,
              catalog.engines.count <= 1000,
              Set(catalog.engines.map(\.id)).count == catalog.engines.count
        else { throw RuntimeError.invalidCatalog }
        guard catalog.expiresAt > now.timeIntervalSince1970 else { throw RuntimeError.expiredCatalog }
        let hash = DigestTools.sha256(envelope.payload)
        if let previous {
            guard catalog.revision >= previous.revision,
                  catalog.revision != previous.revision || hash == previous.payloadSHA256,
                  Set(catalog.revokedEngineIDs).isSuperset(of: previous.revokedEngineIDs)
            else { throw RuntimeError.replayedCatalog }
        }
        for id in catalog.revokedEngineIDs { try ManagedPath.validateID(id) }
        for manifest in catalog.engines { try manifest.validate() }
        return VerifiedCatalog(catalog: catalog,
                               state: CatalogState(revision: catalog.revision, payloadSHA256: hash,
                                                   revokedEngineIDs: catalog.revokedEngineIDs), envelope: envelope)
    }
}
