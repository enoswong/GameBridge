// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct GameFileRepair {
    public let engine: InstalledEngine
    public let lease: EnvironmentLease
    public let root: URL
    public let log: @Sendable (String) -> Void

    public init(
        engine: InstalledEngine, lease: EnvironmentLease, root: URL, log: @escaping @Sendable (String) -> Void
    ) {
        self.engine = engine
        self.lease = lease
        self.root = root
        self.log = log
    }

    static func components(in reports: [LegacyGameAudit]) -> [String] {
        let supported = Set(LegacyVisualCpp.installers.map(\.id) + ["vc-x86", "vc-x64", "directx"])
        let requested = reports.flatMap(\.unresolvedImports).compactMap { item -> String? in
            if item.component == "DirectX June 2010" { return "directx" }
            guard let component = item.component, component.hasPrefix("Visual C++ ") else { return nil }
            let version = component.dropFirst("Visual C++ ".count)
            let identifier = version == "v14" ? "vc-\(item.architecture)" : "vc\(version)-\(item.architecture)"
            return supported.contains(identifier) ? identifier : nil
        }
        return Set(requested).sorted()
    }

    public func installMissing(
        from reports: [LegacyGameAudit], progress: @Sendable () -> Void = {}
    ) async throws -> [String] {
        let identifiers = Self.components(in: reports)
        guard !identifiers.isEmpty else { return [] }
        let windows = try ManagedPath.child("drive_c/windows", under: lease.environment.prefix)
        guard (try? windows.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw RuntimeError.io("Initialize the Windows environment before repairing game dependencies")
        }
        try await RuntimeAdapter.confirmIdle(engine: engine, lease: lease)
        let cache = try ManagedPath.child("Downloads", under: root)
        progress()
        var failed: [String] = []
        for id in identifiers {
            try Task.checkCancellation()
            do {
                try await install(id, cache: cache)
            } catch {
                try Task.checkCancellation()
                log("[GameBridge] \(id): \(error.localizedDescription)\n")
                failed.append(id)
            }
        }
        let prefix = lease.environment.prefix
        let checked = reports.compactMap { try? LegacyGameAudit.scan(directory: $0.directory, prefix: prefix) }
        return Set(failed + Self.components(in: checked)).sorted()
    }

    private func install(_ id: String, cache: URL) async throws {
        log("[GameBridge] Installing missing component: \(id)\n")
        if let item = LegacyVisualCpp.installers.first(where: { $0.id == id }) {
            let file = try await item.obtain(cache: cache, log: log)
            try WindowsSteamCommand.validatePE(file)
            try await RuntimeAdapter.runBootstrapTool(
                engine: engine, lease: lease, arguments: [file.path, "/q"], log: log
            )
            return
        }
        guard let payloadDirectory = BootstrapPayload.bundledDirectory() else {
            throw RuntimeError.io("This build does not include the verified setup catalog")
        }
        let payload = try BootstrapPayload.load(from: payloadDirectory)
        guard let item = payload.installers.first(where: { $0.id == id }) else {
            throw RuntimeError.invalidManifest("missing setup component \(id)")
        }
        let file = try await item.obtain(cache: cache, log: log)
        let session = BootstrapSession(engine: engine, lease: lease, progress: { _ in }, log: log)
        try await session.install(id, at: file)
    }
}
