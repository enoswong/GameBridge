// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

public struct InstalledEngine: Codable, Sendable {
    public let manifest: EngineManifest
    public let directory: URL
    public let catalogRevision: UInt64
}
struct InstallationJournal: Codable, Sendable {
    var id: String
    var engineID: String
    var stage: String
    var updatedAt: Date
}

public actor EngineStore {
    public let root: URL
    private let registry: RuntimeRegistry
    private let verifier: CatalogVerifier

    public init(root: URL, trustedKeys: [String: Data]) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for folder in ["Engines", "Staging", "Locks"] {
            let url = try ManagedPath.child(folder, under: self.root)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        registry = try RuntimeRegistry(url: ManagedPath.child("registry.sqlite", under: self.root))
        verifier = CatalogVerifier(trustedKeys: trustedKeys)
    }

    public func install(engineID: String, envelope: SignedEnvelope, archive: URL, now: Date = Date()) throws -> InstalledEngine {
        let lock = try ExclusiveFileLock(url: root.appending(path: "Locks/store.lock"))
        defer { withExtendedLifetime(lock) {} }
        let previous = try registry.get(CatalogState.self, key: "catalog")
        let verified = try verifier.verify(envelope, now: now, previous: previous)
        // Persist new revocations even if the requested engine is not installable.
        try registry.put(verified.state, key: "catalog")
        guard !verified.catalog.revokedEngineIDs.contains(engineID) else { throw RuntimeError.revokedEngine }
        guard let manifest = verified.catalog.engines.first(where: { $0.id == engineID }) else { throw RuntimeError.engineNotFound }
        if let existing = try registry.get(InstalledEngine.self, key: "engine:" + engineID) {
            guard existing.manifest == manifest else { throw RuntimeError.engineAlreadyInstalled }
            try validateExecutables(existing)
            return existing
        }
        let destination = try ManagedPath.child("Engines/" + engineID, under: root)
        // A directory left after a crash between rename and registration is quarantined,
        // never implicitly adopted or overwritten.
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw RuntimeError.engineAlreadyInstalled }
        let id = UUID().uuidString
        let stage = try ManagedPath.child("Staging/" + id, under: root)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var journal = InstallationJournal(id: id, engineID: engineID, stage: "staging", updatedAt: now)
        try registry.put(journal, key: "journal:" + id)
        do {
            let snapshot = stage.appending(path: "archive.tar")
            try snapshotArchive(archive, to: snapshot, manifest: manifest)
            let payload = stage.appending(path: "payload")
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try SafeTarExtractor.extract(archive: snapshot, into: payload, maximumBytes: manifest.unpackedBytes)
            let candidate = InstalledEngine(manifest: manifest, directory: payload, catalogRevision: verified.catalog.revision)
            try validateExecutables(candidate)
            journal.stage = "validated"
            try registry.put(journal, key: "journal:" + id)
            try syncDirectoryTree(payload)
            try FileManager.default.moveItem(at: payload, to: destination)
            try syncDirectory(stage)
            let directoryFD = open(destination.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
            guard directoryFD >= 0 else { throw RuntimeError.io("open engine directory") }
            let syncResult = fsync(directoryFD)
            close(directoryFD)
            guard syncResult == 0 else { throw RuntimeError.io("sync engine directory") }
            let installed = InstalledEngine(manifest: manifest, directory: destination, catalogRevision: verified.catalog.revision)
            try registry.put(installed, key: "engine:" + engineID)
            journal.stage = "committed"
            try registry.put(journal, key: "journal:" + id)
            try? FileManager.default.removeItem(at: stage)
            return installed
        } catch {
            journal.stage = "interrupted"
            try? registry.put(journal, key: "journal:" + id)
            // Keep the failed staging area for explicit recovery; old engines are untouched.
            throw error
        }
    }

    public func installedEngines() throws -> [InstalledEngine] {
        let state = try registry.get(CatalogState.self, key: "catalog")
        return try registry.keys(prefix: "engine:").compactMap { key in
            guard let engine = try registry.get(InstalledEngine.self, key: key),
                  state?.revokedEngineIDs.contains(engine.manifest.id) != true else { return nil }
            try validateExecutables(engine)
            return engine
        }
    }

    public func engine(id: String) throws -> InstalledEngine {
        try ManagedPath.validateID(id)
        if try registry.get(CatalogState.self, key: "catalog")?.revokedEngineIDs.contains(id) == true { throw RuntimeError.revokedEngine }
        guard let engine = try registry.get(InstalledEngine.self, key: "engine:" + id) else { throw RuntimeError.engineNotFound }
        try validateExecutables(engine)
        return engine
    }

    public func interruptedInstallations() throws -> [String] {
        try registry.keys(prefix: "journal:").compactMap { key in
            guard let item = try registry.get(InstallationJournal.self, key: key), item.stage != "committed" else { return nil }
            return item.id
        }
    }

    private func syncDirectoryTree(_ root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw RuntimeError.io("enumerate runtime directories")
        }
        var directories = [root]
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { directories.append(url) }
        }
        for directory in directories.reversed() { try syncDirectory(directory) }
    }
    private func syncDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RuntimeError.io("open runtime directory") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw RuntimeError.io("sync runtime directory") }
    }

    private func validateExecutables(_ engine: InstalledEngine) throws {
        try engine.manifest.validate()
        for path in [engine.manifest.winePath, engine.manifest.wineserverPath] {
            let file = try ManagedPath.child(path, under: engine.directory)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  FileManager.default.isExecutableFile(atPath: file.path) else { throw RuntimeError.invalidArchive("missing executable") }
        }
    }

    private func snapshotArchive(_ source: URL, to snapshot: URL, manifest: EngineManifest) throws {
        guard FileManager.default.createFile(atPath: snapshot.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw RuntimeError.io("create archive snapshot") }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: snapshot)
        defer { try? output.close() }
        var size: UInt64 = 0
        while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            guard UInt64(bytes.count) <= manifest.archiveBytes - size else { throw RuntimeError.archiveHashMismatch }
            size += UInt64(bytes.count)
            try output.write(contentsOf: bytes)
        }
        try output.synchronize()
        guard size == manifest.archiveBytes,
              try DigestTools.sha256(file: snapshot, maximumBytes: manifest.archiveBytes).hash == manifest.archiveSHA256
        else { throw RuntimeError.archiveHashMismatch }
    }
}
