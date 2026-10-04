// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct BootstrapInstaller: Codable, Sendable {
    var id: String
    var fileName: String
    var url: String
    var sha256: String
    var maximumBytes: UInt64
    func validate() throws {
        let names = ["steam": "SteamSetup.exe", "vc-x64": "VC_redist.x64.exe", "vc-x86": "VC_redist.x86.exe", "directx": "directx_Jun2010_redist.exe"]
        let hosts = ["aka.ms", "download.microsoft.com", "cdn.akamai.steamstatic.com"]
        guard names[id] == fileName, let source = URL(string: url), source.scheme == "https",
              let host = source.host, hosts.contains(host), source.user == nil, source.password == nil,
              (id == "steam") == (host == "cdn.akamai.steamstatic.com"),
              DigestTools.isSHA256(sha256), maximumBytes > 0, maximumBytes <= 256 * 1024 * 1024 else {
            throw RuntimeError.invalidManifest("bootstrap installer")
        }
    }
    static func matches(_ file: URL, digest: String, maximumBytes: UInt64) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RuntimeError.unsafePath(file.path) }
        return try DigestTools.sha256(file: file, maximumBytes: maximumBytes).hash == digest
    }
    func obtain(cache: URL, log: @escaping @Sendable (String) -> Void) async throws -> URL {
        try validate()
        let directory = try ManagedPath.child(sha256, under: cache)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = try ManagedPath.child(fileName, under: directory)
        if try Self.matches(target, digest: sha256, maximumBytes: maximumBytes) { return target }
        log("下載官方元件：\(fileName)\n")
        let (temporary, response) = try await URLSession.shared.download(from: URL(string: url)!)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https",
              try Self.matches(temporary, digest: sha256, maximumBytes: maximumBytes) else { throw RuntimeError.archiveHashMismatch }
        // Verified complete file only; interrupted downloads never become cache entries.
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: temporary, to: target)
        return target
    }
}

public struct BootstrapPayload: Codable, Sendable {
    var schema: Int
    var engineID: String
    var catalogFile: String
    var trustKeysFile: String
    var archiveFile: String
    var bridgeFile: String
    var bridgeSHA256: String
    var pointerFile: String
    var pointerSHA256: String
    var installers: [BootstrapInstaller]

    public static func bundledDirectory() -> URL? {
        let candidates = [Bundle.main.resourceURL,
                          URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()]
        return candidates.compactMap { $0?.appendingPathComponent("Bootstrap") }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("bootstrap.json").path)
        }
    }
    public static func load(from directory: URL) throws -> BootstrapPayload {
        let manifest = try ManagedPath.child("bootstrap.json", under: directory)
        guard (try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 65536 else { throw RuntimeError.invalidManifest("bootstrap size") }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: manifest))
        guard value.schema == 1, value.installers.count == 4,
              Set(value.installers.map(\.id)) == Set(["steam", "vc-x64", "vc-x86", "directx"]),
              DigestTools.isSHA256(value.bridgeSHA256), DigestTools.isSHA256(value.pointerSHA256) else {
            throw RuntimeError.invalidManifest("bootstrap contents")
        }
        try ManagedPath.validateID(value.engineID)
        for name in [value.catalogFile, value.trustKeysFile, value.archiveFile, value.bridgeFile, value.pointerFile] {
            _ = try ManagedPath.child(name, under: directory)
        }
        for item in value.installers { try item.validate() }
        for (name, digest) in [(value.bridgeFile, value.bridgeSHA256), (value.pointerFile, value.pointerSHA256)] {
            guard try BootstrapInstaller.matches(ManagedPath.child(name, under: directory), digest: digest, maximumBytes: 4 * 1024 * 1024) else {
                throw RuntimeError.archiveHashMismatch
            }
        }
        return value
    }
}

struct BootstrapState: Codable {
    var environmentID: String
    var engineID: String
    var completed: [String: String]
    func contains(_ step: String, digest: String) -> Bool { completed[step] == digest }
}

public enum OneClickBootstrap {
    public static func prepare(root: URL, payloadDirectory: URL, newEnvironment: Bool = false,
                               name: String = "Windows Steam", log: @escaping @Sendable (String) -> Void) async throws -> RuntimeEnvironment {
        let payload = try BootstrapPayload.load(from: payloadDirectory)
        let keys = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: ManagedPath.child(payload.trustKeysFile, under: payloadDirectory)))
        let store = try EngineStore(root: root, trustedKeys: keys)
        let coordinator = try EnvironmentCoordinator(root: root)
        let lock = try ExclusiveFileLock(url: ManagedPath.child("Locks/bootstrap.lock", under: root))
        defer { withExtendedLifetime(lock) {} }
        let envelope = try JSONDecoder().decode(SignedEnvelope.self, from: Data(contentsOf: ManagedPath.child(payload.catalogFile, under: payloadDirectory)))
        let verified = try CatalogVerifier(trustedKeys: keys).verify(envelope, now: Date(), previous: nil)
        guard let manifest = verified.catalog.engines.first(where: { $0.id == payload.engineID }), manifest.backends == [.dxmt] else { throw RuntimeError.invalidManifest("bootstrap engine") }
        #if !DEBUG
        guard manifest.distribution == .redistributable else { throw RuntimeError.invalidManifest("internal runtime cannot be used in a public build") }
        #endif
        try HostProbe.inspect(storageURL: root).validate(for: manifest)
        let engine: InstalledEngine
        if let installed = try await store.installedEngines().first(where: { $0.manifest.id == payload.engineID }) {
            guard installed.manifest == manifest else { throw RuntimeError.engineAlreadyInstalled }
            engine = installed
        } else {
            log("準備 Windows 遊戲引擎…\n")
            engine = try await store.install(engineID: payload.engineID, envelope: envelope, archive: ManagedPath.child(payload.archiveFile, under: payloadDirectory))
        }
        let stateURL = try ManagedPath.child("bootstrap-state.json", under: root)
        var state: BootstrapState
        let activeIDs = Set(try await coordinator.environments().map(\.id))
        let previous = FileManager.default.fileExists(atPath: stateURL.path) ? try JSONDecoder().decode(BootstrapState.self, from: Data(contentsOf: stateURL)) : nil
        if !newEnvironment, let previous, activeIDs.contains(previous.environmentID) {
            state = previous
            guard state.engineID == payload.engineID else { throw RuntimeError.invalidManifest("bootstrap resume engine") }
        } else {
            let environment = try await coordinator.create(name: name, manifest: manifest, backend: .dxmt, synchronization: "none")
            state = BootstrapState(environmentID: environment.id, engineID: manifest.id, completed: [:])
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        }
        let lease = try await coordinator.recoveryLease(id: state.environmentID)
        defer { withExtendedLifetime(lease) {} }
        try await RuntimeAdapter.confirmIdle(engine: engine, lease: lease)
        try await coordinator.markStatus(.initializing, lease: lease)
        do {
            if !state.contains("initialize", digest: manifest.archiveSHA256) {
                log("建立 Windows 環境…\n")
                try await RuntimeAdapter.initialize(engine: engine, lease: lease, log: log)
                state.completed["initialize"] = manifest.archiveSHA256
                try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
            }
            let cache = try ManagedPath.child("Downloads", under: root)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            for id in ["vc-x64", "vc-x86", "directx", "steam"] {
                let item = payload.installers.first { $0.id == id }!
                if state.contains(id, digest: item.sha256) { continue }
                let installer = try await item.obtain(cache: cache, log: log)
                log("安裝 \(item.fileName)…\n")
                if let component = CommonRuntimeComponent(rawValue: id), id != "directx" {
                    _ = try await RuntimeAdapter.repairCommonComponent(component, engine: engine, lease: lease, installer: installer, install: true, log: log)
                } else if id == "directx" {
                    let folder = try ManagedPath.child("drive_c/GameBridge/DirectX", under: lease.environment.prefix)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try await RuntimeAdapter.runBootstrapTool(engine: engine, lease: lease, arguments: [installer.path, "/Q", "/T:C:\\GameBridge\\DirectX"], log: log)
                    let setup = try ManagedPath.child("DXSETUP.exe", under: folder)
                    _ = try await RuntimeAdapter.repairCommonComponent(.legacyDirectX, engine: engine, lease: lease, installer: setup, install: true, log: log)
                } else {
                    try await RuntimeAdapter.runBootstrapTool(engine: engine, lease: lease, arguments: [installer.path, "/S"], log: log)
                }
                state.completed[id] = item.sha256
                try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
            }
            log("配置自動遊戲相容性修正…\n")
            try DeskrawlCompatibility.provision(payload: payload, directory: payloadDirectory, prefix: lease.environment.prefix)
            try await RuntimeAdapter.runBootstrapTool(engine: engine, lease: lease, arguments: ["reg", "add", "HKCU\\Software\\Wine\\AppDefaults\\Deskrawl.exe\\DllOverrides", "/v", "version", "/t", "REG_SZ", "/d", "native,builtin", "/f"], log: log)
            try await coordinator.attachSteam(relativePath: "drive_c/Program Files (x86)/Steam/Steam.exe", lease: lease)
            log("Windows Steam 已準備完成。登入後即可安裝遊戲。\n")
            return try await coordinator.environment(id: state.environmentID)
        } catch {
            try? await coordinator.markStatus(.needsAttention, lease: lease)
            throw error
        }
    }
}
