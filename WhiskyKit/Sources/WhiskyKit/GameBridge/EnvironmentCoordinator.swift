// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

public struct RuntimeBinding: Codable, Equatable, Sendable {
    public var engineID: String
    public var cpuMode: RuntimeCPU
    public var backend: GraphicsBackend
    public var synchronization: String
    public func validate(against manifest: EngineManifest) throws {
        try manifest.validate()
        guard engineID == manifest.id, cpuMode == manifest.cpuMode,
              manifest.backends.contains(backend), manifest.synchronizationModes.contains(synchronization)
        else { throw RuntimeError.invalidManifest("runtime binding") }
    }
}
public enum EnvironmentStatus: String, Codable, Sendable { case created, initializing, ready, running, needsAttention }
public struct RuntimeEnvironment: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let prefix: URL
    public let binding: RuntimeBinding
    public let createdAt: Date
    public var status: EnvironmentStatus
    public var steamRelativePath: String?
}
public final class EnvironmentLease: @unchecked Sendable {
    public let environment: RuntimeEnvironment
    private let locks: [ExclusiveFileLock]
    init(environment: RuntimeEnvironment, locks: [ExclusiveFileLock]) { self.environment = environment; self.locks = locks }
}

public actor EnvironmentCoordinator {
    private let root: URL
    private let registry: RuntimeRegistry
    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in ["Environments", "Locks"] {
            try FileManager.default.createDirectory(at: ManagedPath.child(name, under: self.root), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        registry = try RuntimeRegistry(url: ManagedPath.child("environments.sqlite", under: self.root))
    }

    public func create(name: String, manifest: EngineManifest, backend: GraphicsBackend, synchronization: String) throws -> RuntimeEnvironment {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else { throw RuntimeError.invalidManifest("environment name") }
        let binding = RuntimeBinding(engineID: manifest.id, cpuMode: manifest.cpuMode, backend: backend, synchronization: synchronization)
        try binding.validate(against: manifest)
        let id = UUID().uuidString
        let prefix = try ManagedPath.child("Environments/\(id)/prefix", under: root)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let environment = RuntimeEnvironment(id: id, name: name, prefix: prefix, binding: binding,
                                             createdAt: Date(), status: .created, steamRelativePath: nil)
        try registry.put(environment, key: "environment:" + id)
        return environment
    }
    /// Caller must confirm Wine idle while holding the source lease. Existing prefixes and
    /// their immutable bindings are never modified. FileManager copies symlinks as links.
    public func cloneIdleEnvironment(source: EnvironmentLease, name: String, manifest: EngineManifest,
                                     backend: GraphicsBackend) throws -> RuntimeEnvironment {
        defer { withExtendedLifetime(source) {} }
        let original = try environment(id: source.environment.id)
        guard original.prefix == source.environment.prefix,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else {
            throw RuntimeError.unboundEnvironment
        }
        let binding = RuntimeBinding(engineID: manifest.id, cpuMode: manifest.cpuMode, backend: backend, synchronization: "none")
        try binding.validate(against: manifest)
        guard binding.cpuMode == original.binding.cpuMode else { throw RuntimeError.invalidManifest("clone CPU mode") }
        let id = UUID().uuidString
        let directory = try ManagedPath.child("Environments/\(id)", under: root)
        let prefix = directory.appending(path: "prefix")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        // No registry entry is published until copying completes. Interrupted orphan
        // directories are retained for explicit cleanup rather than adopted as usable.
        try FileManager.default.copyItem(at: original.prefix, to: prefix)
        try finalizeClone(prefix, source: original.prefix)
        let record = RuntimeEnvironment(id: id, name: name, prefix: prefix, binding: binding,
                                        createdAt: Date(), status: .created, steamRelativePath: original.steamRelativePath)
        try registry.put(record, key: "environment:" + id)
        return record
    }

    private func finalizeClone(_ prefix: URL, source: URL) throws {
        guard let entries = FileManager.default.enumerator(at: prefix, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]) else {
            throw RuntimeError.io("enumerate cloned prefix")
        }
        var directories = [prefix]
        for case let entry as URL in entries {
            let values = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true {
                let link = try FileManager.default.destinationOfSymbolicLink(atPath: entry.path)
                let sourceEntry = source.appending(path: String(entry.path.dropFirst(prefix.path.count + 1)))
                let target = (link.hasPrefix("/") ? URL(fileURLWithPath: link) : sourceEntry.deletingLastPathComponent().appending(path: link))
                    .standardizedFileURL.resolvingSymlinksInPath()
                if target.path == source.path || target.path.hasPrefix(source.path + "/") {
                    let suffix = String(target.path.dropFirst(source.path.count))
                    try FileManager.default.removeItem(at: entry)
                    try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: prefix.path + suffix)
                } else if target.path.hasPrefix(root.appending(path: "Environments").path + "/") {
                    throw RuntimeError.unsafePath("clone aliases another managed environment")
                }
                // Wine's existing host-folder/Z: mappings are retained; this is not a sandbox.
            } else if values.isDirectory == true {
                directories.append(entry)
            } else if values.isRegularFile == true {
                try synchronize(entry)
            } else { throw RuntimeError.unsafePath("special file in prefix clone") }
        }
        for directory in directories.reversed() { try synchronize(directory) }
        try synchronize(prefix.deletingLastPathComponent())
        try synchronize(prefix.deletingLastPathComponent().deletingLastPathComponent())
    }
    private func synchronize(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw RuntimeError.io("open cloned entry") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw RuntimeError.io("sync cloned entry") }
    }

    public func environments() throws -> [RuntimeEnvironment] {
        try allEnvironments().filter { try !isArchived($0.id) }
    }
    private func allEnvironments() throws -> [RuntimeEnvironment] {
        try registry.keys(prefix: "environment:").compactMap { try registry.get(RuntimeEnvironment.self, key: $0) }
    }
    private func isArchived(_ id: String) throws -> Bool {
        try registry.get(Bool.self, key: "archived:" + id) == true
    }
    public func archivedEnvironments() throws -> [RuntimeEnvironment] {
        try allEnvironments().filter { try isArchived($0.id) }
    }
    /// Caller confirms Wine idle under this lease. Archive only hides the record;
    /// the prefix and saves remain in place, so interruption cannot orphan data.
    public func archive(lease: EnvironmentLease) throws {
        defer { withExtendedLifetime(lease) {} }
        let record = try environment(id: lease.environment.id)
        guard record.status == .created || record.status == .ready else { throw RuntimeError.environmentBusy }
        try registry.put(true, key: "archived:" + record.id)
    }
    public func restore(id: String) throws {
        try ManagedPath.validateID(id)
        let lock = try ExclusiveFileLock(url: ManagedPath.child("Locks/environment-\(id).lock", under: root))
        defer { withExtendedLifetime(lock) {} }
        guard try isArchived(id), try registry.get(RuntimeEnvironment.self, key: "environment:" + id) != nil else {
            throw RuntimeError.unboundEnvironment
        }
        try registry.put(false, key: "archived:" + id)
    }
    public func environment(id: String) throws -> RuntimeEnvironment {
        try ManagedPath.validateID(id)
        guard try !isArchived(id) else { throw RuntimeError.unboundEnvironment }
        guard let environment = try registry.get(RuntimeEnvironment.self, key: "environment:" + id), environment.id == id,
              environment.prefix == root.appending(path: "Environments/\(id)/prefix") else { throw RuntimeError.unboundEnvironment }
        _ = try ManagedPath.child("Environments/\(id)/prefix", under: root)
        return environment
    }
    public func lease(id: String) throws -> EnvironmentLease {
        try acquireLease(id: id, recovering: false)
    }
    /// Recovery still requires exclusive ownership and confirmed wineserver idle.
    public func recoveryLease(id: String) throws -> EnvironmentLease {
        try acquireLease(id: id, recovering: true)
    }
    private func acquireLease(id: String, recovering: Bool) throws -> EnvironmentLease {
        try ManagedPath.validateID(id)
        let lock = try ExclusiveFileLock(url: ManagedPath.child("Locks/environment-\(id).lock", under: root))
        let environment = try environment(id: id)
        guard recovering || environment.status == .created || environment.status == .ready else { throw RuntimeError.environmentBusy }
        // A fresh environment owns its Steam library. External/shared libraries remain unsupported
        // until separately registered; no implicit Wine dosdevices symlink is followed.
        return EnvironmentLease(environment: environment, locks: [lock])
    }
    public func markStatus(_ status: EnvironmentStatus, lease: EnvironmentLease) throws {
        var record = try environment(id: lease.environment.id)
        record.status = status
        try registry.put(record, key: "environment:" + record.id)
    }
    public func attachSteam(relativePath: String, lease: EnvironmentLease) throws {
        var record = try environment(id: lease.environment.id)
        _ = try WindowsSteamCommand(prefix: record.prefix, steamRelativePath: relativePath, appID: nil)
        record.steamRelativePath = relativePath
        record.status = .ready
        try registry.put(record, key: "environment:" + record.id)
    }
}
