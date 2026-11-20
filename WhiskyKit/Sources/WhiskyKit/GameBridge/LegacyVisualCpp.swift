// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum LegacyVisualCpp {
    // Microsoft installer URLs and hashes from Winetricks f3890f670867b5ffbc3938726db45c0f7d16c8ba.
    static let installers: [BootstrapInstaller] = [
        package(2005, "x86", "8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A",
                "8648c5fc29c44b9112fe52f9a33f80e7fc42d10f3b5b42b2121542a13e44adfd"),
        package(2005, "x64", "8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A",
                "4487570bd86e2e1aac29db2a1d0a91eb63361fcaac570808eb327cd4e0e2240d"),
        package(2008, "x86", "5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE",
                "8742bcbf24ef328a72d2a27b693cc7071e38d3bb4b9b44dec42aa3d2c8d61d92"),
        package(2008, "x64", "5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE",
                "c5e273a4a16ab4d5471e91c7477719a2f45ddadb76c7f98a38fa5074a6838654"),
        package(2010, "x86", "5/B/C/5BC5DBB3-652D-4DCE-B14A-475AB85EEF6E",
                "31d32fa39d52cac9a765a43660431f7a127eee784b54b2f5e2af3e2b763a1af8"),
        package(2010, "x64", "A/8/0/A80747C3-41BD-45DF-B505-E9710D2744E0",
                "2fddbc3aaaab784c16bc673c3bae5f80929d5b372810dbc28649283566d33255"),
        package(2012, "x86", "1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4",
                "b924ad8062eaf4e70437c8be50fa612162795ff0839479546ce907ffa8d6e386"),
        package(2012, "x64", "1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4",
                "681be3e5ba9fd3da02c09d7e565adfa078640ed66a0d58583efad2c1e3cc4064"),
        package(2013, "x86", "0/5/6/056dcda9-d667-4e27-8001-8a0c6971d6b1",
                "89f4e593ea5541d1c53f983923124f9fd061a1c0c967339109e375c661573c17"),
        package(2013, "x64", "0/5/6/056dcda9-d667-4e27-8001-8a0c6971d6b1",
                "20e2645b7cd5873b1fa3462b99a665ac8d6e14aae83ded9d875fea35ffdd7d7e")
    ]

    private static func package(_ year: Int, _ arch: String, _ path: String, _ digest: String) -> BootstrapInstaller {
        let file = "vcredist_\(arch)." + (year == 2005 ? "EXE" : "exe")
        return BootstrapInstaller(
            id: "vc\(year)-\(arch)", fileName: file, url: "https://download.microsoft.com/download/\(path)/\(file)",
            sha256: digest, maximumBytes: 64 * 1024 * 1024
        )
    }

    public static func prepare(
        root: URL, environmentID: String, reinstall: Bool = false,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> [String] {
        let coordinator = try EnvironmentCoordinator(root: root)
        let lease = try await coordinator.lease(id: environmentID)
        defer { withExtendedLifetime(lease) {} }
        let environment = lease.environment
        let store = try EngineStore(root: root, trustedKeys: [:])
        let engine = try await store.engine(id: environment.binding.engineID)
        try await RuntimeAdapter.confirmIdle(engine: engine, lease: lease)
        let windows = try ManagedPath.child("drive_c/windows", under: environment.prefix)
        guard try windows.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw RuntimeError.io("Initialize the Windows environment before preparing legacy components")
        }
        let stateFile = try ManagedPath.child(
            "legacy-visual-cpp.json", under: environment.prefix.deletingLastPathComponent()
        )
        let cache = try ManagedPath.child("Downloads", under: root)
        try await coordinator.markStatus(.initializing, lease: lease)
        do {
            let completed = try await install(
                engine: engine, lease: lease, paths: (stateFile, cache), reinstall: reinstall, log: log
            )
            try await coordinator.markStatus(environment.status, lease: lease)
            return completed
        } catch {
            if (try? await RuntimeAdapter.confirmIdle(engine: engine, lease: lease)) != nil {
                try? await coordinator.markStatus(environment.status, lease: lease)
            } else {
                try? await coordinator.markStatus(.needsAttention, lease: lease)
            }
            throw error
        }
    }

    private static func install(
        engine: InstalledEngine, lease: EnvironmentLease, paths: (state: URL, cache: URL), reinstall: Bool,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> [String] {
        var completed: [String: String] = [:]
        if !reinstall, FileManager.default.fileExists(atPath: paths.state.path) {
            completed = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: paths.state))
        }
        if reinstall {
            try JSONEncoder().encode(completed).write(to: paths.state, options: .atomic)
        }
        for item in installers where completed[item.id] != item.sha256 {
            try Task.checkCancellation()
            log("準備 \(item.id)。請在安裝器視窗完成安裝。\n")
            let installer = try await item.obtain(cache: paths.cache, log: log)
            try WindowsSteamCommand.validatePE(installer)
            try await RuntimeAdapter.runBootstrapTool(
                engine: engine, lease: lease, arguments: [installer.path], log: log
            )
            completed[item.id] = item.sha256
            try JSONEncoder().encode(completed).write(to: paths.state, options: .atomic)
        }
        return installers.map(\.id)
    }
}
