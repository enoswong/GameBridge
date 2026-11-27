// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(CryptoKit)
import CryptoKit

/// A remote data-only catalog for one coherent official Valve desktop seed.
public enum MobileSupportCatalog {
    public struct Package: Codable, Equatable, Sendable {
        public let file: String
        public let bytes: Int
        public let sha256: String
        public init(file: String, bytes: Int, sha256: String) {
            self.file = file
            self.bytes = bytes
            self.sha256 = sha256
        }
    }

    public struct Payload: Codable, Sendable {
        public let schemaVersion: Int
        public let revision: Int
        public let issuedAt: Int
        public let expiresAt: Int
        public let packages: [Package]
        public let clientSHA256: String
    }

    public struct Envelope: Codable {
        public let keyID: String
        public let payload: Data
        public let signature: Data
    }

    public struct Verified: Sendable {
        public let payload: Payload
        public let digest: String
    }

    public enum Failure: Error {
        case invalidSignature, invalidCatalog, staleOrChangedRevision
    }

    public static let maxEnvelopeBytes = 64 * 1024
    private static let expected = ["steam_win32.zip.", "bins_win32.zip.", "bins_win64_win32.zip."]

    private static func hex(_ string: String, length: Int) -> Bool {
        string.utf8.count == length && string.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func validPackages(_ packages: [Package]) -> Bool {
        guard packages.count == expected.count else { return false }
        return expected.allSatisfy { prefix in
            packages.filter { package in
                package.file.hasPrefix(prefix)
                && hex(String(package.file.dropFirst(prefix.count)), length: 40)
                && (1...64 * 1024 * 1024).contains(package.bytes)
                && hex(package.sha256, length: 64)
            }.count == 1
        }
    }

    /// The trust key is supplied by the installed native app, never by the network response.
    public static func verify(
        _ data: Data, keyID: String, publicKey: Data, now: Int,
        minimumRevision: Int = 0, acceptedDigest: String? = nil
    ) throws -> Verified {
        guard !data.isEmpty, data.count <= maxEnvelopeBytes, now > 0 else {
            throw Failure.invalidCatalog
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard envelope.keyID == keyID, envelope.signature.count == 64,
              key.isValidSignature(envelope.signature, for: envelope.payload) else {
            throw Failure.invalidSignature
        }
        let payload = try JSONDecoder().decode(Payload.self, from: envelope.payload)
        guard payload.schemaVersion == 1, payload.revision > 0,
              payload.issuedAt > 0, payload.issuedAt <= now,
              payload.expiresAt > now, payload.expiresAt - payload.issuedAt <= 31 * 86400,
              validPackages(payload.packages), hex(payload.clientSHA256, length: 64) else {
            throw Failure.invalidCatalog
        }
        let digest = SHA256.hash(data: envelope.payload).map { String(format: "%02x", $0) }.joined()
        guard payload.revision >= minimumRevision,
              payload.revision != minimumRevision || acceptedDigest == digest else {
            throw Failure.staleOrChangedRevision
        }
        return Verified(payload: payload, digest: digest)
    }
}
#endif

/// A small local failure history, collected even when the Wine log view is hidden.
/// Only parsed DLL basenames and failure categories survive; raw text is never uploaded.
public final class MobileSupportSignals: @unchecked Sendable {
    public static let shared = MobileSupportSignals()
    private let lock = NSLock()
    private let storageKey = "GameBridge.recentModuleFailures.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func signal(from raw: String) -> String? {
        guard raw.utf8.count <= 4096 else { return nil }
        let lower = raw.lowercased()
        let candidate: String
        let kind: String
        if lower.contains("err:module:import_dll"), lower.contains(" not found"),
           let marker = lower.range(of: "library ") {
            candidate = String(lower[marker.upperBound...].prefix(while: { !$0.isWhitespace }))
            kind = "missing"
        } else if let marker = lower.range(of: "could not load module '"),
                  let end = lower[marker.upperBound...].firstIndex(of: "'") {
            let path = String(lower[marker.upperBound..<end]).replacingOccurrences(of: "\\", with: "/")
            guard !path.contains(":"), !path.hasPrefix("/") else { return nil }
            candidate = path.split(separator: "/").last.map(String.init) ?? ""
            kind = "load-failed"
        } else {
            return nil
        }
        guard candidate.utf8.count <= 120, candidate.hasSuffix(".dll"),
              !candidate.hasPrefix("."),
              candidate.utf8.allSatisfy({
                  (97...122).contains($0) || (48...57).contains($0) || [43, 45, 46, 95].contains($0)
              }) else { return nil }
        return kind + ":" + candidate
    }

    public func record(_ raw: String) {
        guard let signal = Self.signal(from: raw) else { return }
        lock.lock()
        defer { lock.unlock() }
        var values = defaults.stringArray(forKey: storageKey) ?? []
        if values.last == signal { return }
        values.removeAll { $0 == signal }
        values.append(signal)
        defaults.set(Array(values.suffix(32)), forKey: storageKey)
    }

    public func recent() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array((defaults.stringArray(forKey: storageKey) ?? []).suffix(32))
    }
}
