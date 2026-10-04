// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit

public enum RuntimeError: Error, Equatable, LocalizedError {
    case invalidSignature, unknownKey, invalidCatalog, expiredCatalog, replayedCatalog, revokedEngine
    case invalidManifest(String), unsafePath(String), invalidArchive(String), archiveHashMismatch
    case engineNotFound, engineAlreadyInstalled, environmentBusy, unsupportedHost, unboundEnvironment
    case database(String), io(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSignature: return "The runtime catalog signature is invalid."
        case .unknownKey: return "The runtime catalog uses an untrusted signing key."
        case .invalidCatalog: return "The runtime catalog is malformed."
        case .expiredCatalog: return "The runtime catalog has expired. Refresh it before installing."
        case .replayedCatalog: return "The runtime catalog is older than the accepted revision or conflicts with it."
        case .revokedEngine: return "This runtime has been revoked."
        case .invalidManifest(let field): return "Invalid runtime manifest: \(field)."
        case .unsafePath(let path): return "Unsafe package path: \(path)."
        case .invalidArchive(let reason): return "Invalid runtime archive: \(reason)."
        case .archiveHashMismatch: return "The downloaded runtime does not match its signed hash."
        case .engineNotFound: return "The selected runtime is not installed."
        case .engineAlreadyInstalled: return "A different runtime already uses this immutable identifier."
        case .environmentBusy: return "This environment or library is already in use."
        case .unsupportedHost: return "This Mac does not meet the runtime requirements."
        case .unboundEnvironment: return "This environment has no verified runtime binding."
        case .database(let reason): return "Runtime registry error: \(reason)."
        case .io(let reason): return "Runtime storage error: \(reason)."
        }
    }
}

public enum RuntimeCPU: String, Codable, Sendable { case rosettaX86_64, arm64 }
public enum GraphicsBackend: String, Codable, Sendable { case dxmt, dxvk, d3dMetal, wineD3D }
public enum RuntimeDistribution: String, Codable, Sendable { case internalOnly, redistributable }

public struct RuntimeSource: Codable, Equatable, Sendable {
    public var name: String
    public var url: String
    public var revision: String
    public var license: String
}

public struct EngineManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var version: String
    public var cpuMode: RuntimeCPU
    public var minimumMacOS: String
    public var backends: [GraphicsBackend]
    public var synchronizationModes: [String]
    public var winePath: String
    public var wineserverPath: String
    public var archiveSHA256: String
    public var archiveBytes: UInt64
    public var unpackedBytes: UInt64
    public var sources: [RuntimeSource]
    public var patchSHA256s: [String]
    public var toolchain: String
    public var dependencySHA256s: [String: String]
    public var testReferences: [String]
    public var dxmtFileSHA256s: [String: String]? = nil
    public var distribution: RuntimeDistribution

    public func validate() throws {
        guard schemaVersion == 1 else { throw RuntimeError.invalidManifest("schemaVersion") }
        try ManagedPath.validateID(id)
        if let hashes = dxmtFileSHA256s {
            guard Set(hashes.keys) == Set(DXMTProvisioner.requiredPaths), hashes.values.allSatisfy(DigestTools.isSHA256) else {
                throw RuntimeError.invalidManifest("DXMT file hashes")
            }
        }
        guard !version.isEmpty, OSVersion(minimumMacOS) != nil, !toolchain.isEmpty,
              !backends.isEmpty, Set(backends).count == backends.count,
              !synchronizationModes.isEmpty, synchronizationModes.allSatisfy({ ["none", "esync", "msync"].contains($0) }),
              archiveBytes > 0, archiveBytes <= 8 * 1024 * 1024 * 1024,
              unpackedBytes > 0, unpackedBytes <= 64 * 1024 * 1024 * 1024,
              DigestTools.isSHA256(archiveSHA256),
              patchSHA256s.allSatisfy(DigestTools.isSHA256),
              dependencySHA256s.values.allSatisfy(DigestTools.isSHA256),
              !sources.isEmpty else { throw RuntimeError.invalidManifest("required fields") }
        try ManagedPath.validateRelative(winePath)
        try ManagedPath.validateRelative(wineserverPath)
        guard winePath != wineserverPath else { throw RuntimeError.invalidManifest("executable paths") }
        for source in sources {
            guard !source.name.isEmpty, !source.license.isEmpty,
                  let url = URL(string: source.url), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil,
                  [40, 64].contains(source.revision.count), source.revision.allSatisfy({ $0.isHexDigit && $0.isASCII })
            else { throw RuntimeError.invalidManifest("source lock") }
        }
        if distribution == .redistributable && testReferences.isEmpty {
            throw RuntimeError.invalidManifest("release test evidence")
        }
    }
}

public struct OSVersion: Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public init?(_ text: String) {
        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count), components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(components[0]), let minor = Int(components[1]),
              let patch = components.count == 3 ? Int(components[2]) : 0 else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum ManagedPath {
    public static func validateID(_ id: String) throws {
        guard (1...128).contains(id.utf8.count), let first = id.utf8.first,
              (48...57).contains(first) || (65...90).contains(first) || (97...122).contains(first),
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) })
        else { throw RuntimeError.unsafePath(id) }
    }
    public static func validateRelative(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 1024, !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw RuntimeError.unsafePath(path) }
    }
    public static func child(_ relative: String, under root: URL) throws -> URL {
        try validateRelative(relative)
        let target = root.appending(path: relative)
        var check = target
        while check.path != root.path {
            if (try? check.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw RuntimeError.unsafePath(relative)
            }
            check.deleteLastPathComponent()
        }
        return target
    }
}

public enum DigestTools {
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    public static func sha256(file: URL, maximumBytes: UInt64) throws -> (hash: String, bytes: UInt64) {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var digest = SHA256()
        var total: UInt64 = 0
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
            guard UInt64(data.count) <= maximumBytes - total else { throw RuntimeError.invalidArchive("size limit") }
            total += UInt64(data.count)
            digest.update(data: data)
        }
        return (digest.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }
}
