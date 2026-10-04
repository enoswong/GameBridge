// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct LaunchRequest: Codable, Sendable {
    public let environmentID: String
    public let appID: UInt32?
    public init(environmentID: String, appID: UInt32? = nil) {
        self.environmentID = environmentID; self.appID = appID
    }
}
public struct RunnerControlEvent: Codable, Sendable {
    public let sessionID: UUID
    public let kind: String
    public let processID: Int32?
    public let exitStatus: Int32?
}
public enum CommonRuntimeComponent: String, CaseIterable, Sendable {
    case visualCppX64 = "vc-x64"
    case visualCppX86 = "vc-x86"
    case legacyDirectX = "directx-june2010"

    public var relativeInstallerPath: String {
        switch self {
        case .visualCppX64: return "vcredist/2022/VC_redist.x64.exe"
        case .visualCppX86: return "vcredist/2022/VC_redist.x86.exe"
        case .legacyDirectX: return "DirectX/Jun2010/DXSETUP.exe"
        }
    }
    var arguments: [String] {
        switch self {
        case .visualCppX64: return ["/repair", "/quiet", "/norestart", "/log", "C:\\gamebridge-vc-x64.log"]
        case .visualCppX86: return ["/repair", "/quiet", "/norestart", "/log", "C:\\gamebridge-vc-x86.log"]
        case .legacyDirectX: return ["/silent"]
        }
    }
    var installArguments: [String] {
        arguments.map { $0 == "/repair" ? "/install" : $0 }
    }
    func acceptsExitStatus(_ status: Int32) -> Bool {
        // Wine exposes the Unix low byte of Windows ERROR_SUCCESS_REBOOT_REQUIRED (3010).
        status == 0 || (self != .legacyDirectX && status == 194)
    }
}

public enum RuntimeAdapter {
    /// Host probe only: no prefix changes and no implication of game compatibility.
    public static func probeVersion(engine: InstalledEngine) async throws -> String {
        try HostProbe.inspect(storageURL: engine.directory).validate(for: engine.manifest)
        let executable = try ManagedPath.child(engine.manifest.winePath, under: engine.directory)
        return try await probeExecutable(executable, timeout: 15)
    }

    static func probeExecutable(_ executable: URL, timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--version"]
            process.environment = baseEnvironment()
            let startedAt = ProcessInfo.processInfo.systemUptime
            let stream = try process.runStream(name: "runtime-version", fileHandle: nil, drainTimeout: timeout)
            let deadline = DispatchWorkItem {
                // This is only a version probe, which is never allowed to outlive its deadline.
                if process.isRunning { process.terminate() }
            }
            let forceDeadline = DispatchWorkItem {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: forceDeadline)
            defer { deadline.cancel(); forceDeadline.cancel() }
            var output = ""
            var status: Int32?
            for await event in stream {
                switch event {
                case .message(let text), .error(let text):
                    if output.utf8.count < 65536 { output += String(text.prefix(4096)) }
                case .terminated(let child): status = child.terminationStatus
                default: break
                }
            }
            guard status == 0, ProcessInfo.processInfo.systemUptime - startedAt < timeout else { throw RuntimeError.io("runtime version probe failed or exceeded its deadline") }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    /// Reject settings whose provisioning has not yet been implemented and verified.
    static func validateExecution(binding: RuntimeBinding, manifest: EngineManifest) throws {
        try binding.validate(against: manifest)
        guard manifest.backends == [binding.backend] else { throw RuntimeError.invalidManifest("ambiguous backend") }
        guard (binding.backend == .wineD3D || (binding.backend == .dxmt && manifest.dxmtFileSHA256s != nil)), binding.synchronization == "none" else {
            throw RuntimeError.invalidManifest("Unsupported or unprovisioned backend/synchronization")
        }
    }

    public static func initialize(engine: InstalledEngine, lease: EnvironmentLease,
                                  log: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        let status = try await session(engine: engine, lease: lease, arguments: ["wineboot", "--init"], log: log)
        guard status == 0 else { throw RuntimeError.io("Wine environment initialization failed (\(status))") }
    }

    public static func launch(request: LaunchRequest, engine: InstalledEngine, lease: EnvironmentLease,
                              virtualDesktop: Bool = false,
                              traceWindowProcess: String? = nil,
                              control: @escaping @Sendable (RunnerControlEvent) -> Void,
                              log: @escaping @Sendable (String) -> Void) async throws {
        _ = try debugChannels(dxmt: engine.manifest.backends == [.dxmt], traceProcess: traceWindowProcess)
        defer { withExtendedLifetime(lease) {} }
        let environment = lease.environment
        guard request.environmentID == environment.id, environment.status == .ready,
              let steamPath = environment.steamRelativePath else { throw RuntimeError.unboundEnvironment }
        let command = try WindowsSteamCommand(prefix: environment.prefix, steamRelativePath: steamPath, appID: request.appID)
        // Older containers predate bootstrap. Stage bundled fixes on normal launch too.
        try await confirmIdle(engine: engine, lease: lease)
        if try DeskrawlCompatibility.prepareBundled(prefix: environment.prefix, engineID: engine.manifest.id,
                                                    directory: BootstrapPayload.bundledDirectory()) {
            log("[GameBridge] Preparing bundled Deskrawl compatibility for this environment.\n")
            try await runBootstrapTool(engine: engine, lease: lease,
                arguments: ["reg", "add", "HKCU\\Software\\Wine\\AppDefaults\\Deskrawl.exe\\DllOverrides", "/v", "version", "/t", "REG_SZ", "/d", "native,builtin", "/f"], log: log)
        }
        let sessionID = UUID()
        control(RunnerControlEvent(sessionID: sessionID, kind: "prepared", processID: nil, exitStatus: nil))
        let status = try await session(engine: engine, lease: lease, arguments: command.launchArguments(virtualDesktop: virtualDesktop),
                                      sessionID: sessionID, traceWindowProcess: traceWindowProcess, control: control, log: log)
        guard status == 0 else { throw RuntimeError.io("Windows Steam exited with status \(status)") }
    }

    public static func runSteamInstaller(engine: InstalledEngine, lease: EnvironmentLease, installer: URL,
                                         log: @escaping @Sendable (String) -> Void) async throws {
        try WindowsSteamCommand.validatePE(installer)
        let status = try await session(engine: engine, lease: lease, arguments: [installer.path], log: log)
        guard status == 0 else { throw RuntimeError.io("Steam installer exited with status \(status)") }
    }

    static func runBootstrapTool(engine: InstalledEngine, lease: EnvironmentLease, arguments: [String],
                                 log: @escaping @Sendable (String) -> Void) async throws {
        let status = try await session(engine: engine, lease: lease, arguments: arguments, log: log)
        guard status == 0 || status == 194 else { throw RuntimeError.io("Setup component exited with status \(status)") }
    }

    public static func repairCommonComponent(_ component: CommonRuntimeComponent, engine: InstalledEngine,
                                             lease: EnvironmentLease, installer: URL, install: Bool = false,
                                             log: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        try WindowsSteamCommand.validatePE(installer)
        guard installer.lastPathComponent == URL(fileURLWithPath: component.relativeInstallerPath).lastPathComponent else {
            throw RuntimeError.io("Unexpected common component installer filename")
        }
        let status = try await session(engine: engine, lease: lease,
                                       arguments: [installer.path] + (install ? component.installArguments : component.arguments), log: log)
        guard component.acceptsExitStatus(status) else {
            throw RuntimeError.io("\(component.rawValue) installer exited with status \(status); inspect its installation log")
        }
        return status
    }

    public static func preflight(engine: InstalledEngine, lease: EnvironmentLease) throws {
        try validateExecution(binding: lease.environment.binding, manifest: engine.manifest)
        try HostProbe.inspect(storageURL: lease.environment.prefix).validate(for: engine.manifest)
        if lease.environment.binding.backend == .dxmt { try DXMTProvisioner.validate(engine: engine) }
    }

    public static func confirmIdle(engine: InstalledEngine, lease: EnvironmentLease) async throws {
        try preflight(engine: engine, lease: lease)
        try await retainingSession(lease: lease) {
            try await waitForEnvironment(engine: engine, prefix: lease.environment.prefix)
        }
    }

    /// Cancellation stops waiting for neither the owned client nor the Wine server. The user
    /// closes Windows Steam normally; the lock stays held until confirmed idle. Abrupt helper
    /// death leaves a durable running marker which the coordinator refuses to reuse.
    private static func session(engine: InstalledEngine, lease: EnvironmentLease, arguments: [String],
                                sessionID: UUID = UUID(),
                                traceWindowProcess: String? = nil,
                                control: @escaping @Sendable (RunnerControlEvent) -> Void = { _ in },
                                log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Int32 {
        try Task.checkCancellation()
        try preflight(engine: engine, lease: lease)
        return try await retainingSession(lease: lease) {
            if lease.environment.binding.backend == .dxmt, arguments != ["wineboot", "--init"] {
                try DXMTProvisioner.provision(engine: engine, prefix: lease.environment.prefix)
            }
            let status: Int32
            do {
                status = try await execute(engine: engine, prefix: lease.environment.prefix,
                                           arguments: arguments, sessionID: sessionID, traceWindowProcess: traceWindowProcess, control: control, log: log)
            } catch {
                try await waitForEnvironment(engine: engine, prefix: lease.environment.prefix)
                throw error
            }
            control(RunnerControlEvent(sessionID: sessionID, kind: "clientExited", processID: nil, exitStatus: status))
            try await waitForEnvironment(engine: engine, prefix: lease.environment.prefix)
            control(RunnerControlEvent(sessionID: sessionID, kind: "environmentIdle", processID: nil, exitStatus: status))
            return status
        }
    }

    static func retainingSession<T: Sendable>(lease: EnvironmentLease,
                                              operation: @escaping @Sendable () async throws -> T) async throws -> T {
        // An unstructured detached task does not inherit consumer cancellation.
        try await Task.detached {
            defer { withExtendedLifetime(lease) {} }
            return try await operation()
        }.value
    }

    private static func execute(engine: InstalledEngine, prefix: URL, arguments: [String], sessionID: UUID = UUID(),
                                traceWindowProcess: String? = nil,
                                control: @escaping @Sendable (RunnerControlEvent) -> Void = { _ in },
                                log: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let process = Process()
        process.executableURL = try ManagedPath.child(engine.manifest.winePath, under: engine.directory)
        process.arguments = arguments
        process.currentDirectoryURL = prefix
        var environment = baseEnvironment()
        environment["WINEPREFIX"] = prefix.path
        environment["WINEDEBUG"] = try debugChannels(dxmt: engine.manifest.backends == [.dxmt], traceProcess: traceWindowProcess)
        environment["WINEDLLOVERRIDES"] = dllOverrides(dxmt: engine.manifest.backends == [.dxmt])
        let compatibility = try DeskrawlCompatibility.environment(prefix: prefix, engineID: engine.manifest.id)
        if !compatibility.isEmpty {
            environment.merge(compatibility) { _, local in local }
            log("[GameBridge] Verified Deskrawl input/alpha compatibility profile enabled.\n")
        }
        process.environment = environment
        var status: Int32?
        for await event in try process.runStream(name: "windows-steam", fileHandle: nil) {
            switch event {
            case .started(let child): control(RunnerControlEvent(sessionID: sessionID, kind: "clientStarted", processID: child.processIdentifier, exitStatus: nil))
            case .message(let text), .error(let text): log(text)
            case .terminated(let child): status = child.terminationStatus
            }
        }
        return status ?? -1
    }
    /// Unreal bootstrap checks inspect both the version resource and loadability of these
    /// libraries. Wine's builtins can mask a newer installed Microsoft redistributable.
    /// Keep builtin fallback for prefixes where the native libraries are not installed.
    static func dllOverrides(dxmt: Bool) -> String {
        let graphics = dxmt ? DXMTProvisioner.overrides : "winemenubuilder.exe=d"
        return graphics + ";vcruntime140,vcruntime140_1,msvcp140_2=n,b"
    }

    /// Wine 11 supports process-qualified channels. Keep input traces out of Steam's login UI.
    public static func debugChannels(dxmt: Bool, traceProcess: String?) throws -> String {
        let normal = dxmt ? "fixme-all,+loaddll" : "fixme-all"
        guard let name = traceProcess else { return normal }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard name.utf8.count <= 128, name.lowercased().hasSuffix(".exe"), name.count > 4,
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw RuntimeError.io("Window trace requires an executable basename, for example Deskrawl.exe")
        }
        // DWM transparency calls are often stubs: trace alone hides their FIXME evidence.
        return normal + ["event", "win", "cursor", "msg", "rawinput", "ver", "dwmapi", "macdrv"].map { ",\(name):trace+\($0)" }.joined()
            + ",\(name):fixme+dwmapi"
    }
    private static func waitForEnvironment(engine: InstalledEngine, prefix: URL) async throws {
        let process = Process()
        process.executableURL = try ManagedPath.child(engine.manifest.wineserverPath, under: engine.directory)
        process.arguments = ["-w"]
        var environment = baseEnvironment()
        environment["WINEPREFIX"] = prefix.path
        process.environment = environment
        var status: Int32?
        for await event in try process.runStream(name: "environment-wait", fileHandle: nil) {
            if case .terminated(let child) = event { status = child.terminationStatus }
        }
        guard status == 0 else { throw RuntimeError.io("Cannot confirm that the Wine environment is idle") }
    }
    private static func baseEnvironment() -> [String: String] {
        // Do not forward tokens, arbitrary DYLD injection, or the entire parent environment.
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        for key in ["TMPDIR", "LANG", "LC_ALL", "DISPLAY"] {
            if let value = ProcessInfo.processInfo.environment[key] { environment[key] = value }
        }
        return environment
    }
}
