// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation
import WhiskyKit

// GameBridge's managed runtime path. Legacy Whisky commands remain separate during migration.
extension Whisky {
    struct Runtime: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "runtime",
            abstract: "Manage verified GameBridge runtimes and Windows Steam environments.",
            subcommands: [
                Bootstrap.self, Host.self, ScanMac.self, Engines.self, InstallEngine.self, Probe.self,
                Environments.self, CreateEnvironment.self, Initialize.self, AttachSteam.self, Launch.self,
                InstallSteam.self, RepairComponents.self, Recover.self, Clone.self, ArchiveEnvironment.self,
                RestoreEnvironment.self
            ]
        )

        static func emit<T: Encodable>(_ value: T) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            var bytes = try encoder.encode(value)
            bytes.append(10)
            try FileHandle.standardOutput.write(contentsOf: bytes)
        }
    }
}

extension Whisky.Runtime {
    struct Options: ParsableArguments {
        @Option(help: "GameBridge managed data directory.") var root: String = GameBridgePaths.dataRoot.path
        func store(keys: [String: Data] = [:]) throws -> EngineStore {
            try EngineStore(root: URL(fileURLWithPath: root), trustedKeys: keys)
        }
        func coordinator() throws -> EnvironmentCoordinator {
            try EnvironmentCoordinator(root: URL(fileURLWithPath: root))
        }
    }

    struct Bootstrap: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Prepare Windows Steam and bundled compatibility components.")
        @OptionGroup var options: Options
        @Option var payload: String?
        @Flag var newEnvironment = false
        @Flag var acceptComponentLicenses = false
        @Flag(help: "Emit setup stage events before the final JSON result.") var showProgress = false
        func run() async throws {
            guard acceptComponentLicenses else { throw ValidationError(
                "Read the bundled Microsoft terms and pass --accept-component-licenses to install.") }
            guard let directory = payload.map({ URL(
                fileURLWithPath: $0) }) ?? BootstrapPayload.bundledDirectory() else {
                throw ValidationError("This build has no bundled bootstrap payload.")
            }
            let emitProgress = showProgress
            try Whisky.Runtime.emit(await OneClickBootstrap.prepare(
                root: URL(fileURLWithPath: options.root), payloadDirectory: directory,
                newEnvironment: newEnvironment,
                progress: { stage in
                    if emitProgress { try? Whisky.Runtime.emit(["bootstrapStage": stage.rawValue]) }
                },
                log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) }))
        }
    }
    struct Host: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Inspect this Mac without claiming game support.")
        @OptionGroup var options: Options
        func run() throws {
            let location = URL(fileURLWithPath: options.root)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            try Whisky.Runtime.emit(HostProbe.inspect(storageURL: location))
        }
    }
    struct ScanMac: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "scan-mac", abstract: "Read Mac Steam metadata for candidate discovery only.")
        @Option var steamRoot: String = FileManager.default.homeDirectoryForCurrentUser.appending(
            path: "Library/Application Support/Steam").path
        func run() throws { try Whisky.Runtime.emit(
            SteamLibraryScanner.scanNativeMac(steamRoot: URL(fileURLWithPath: steamRoot))) }
    }
    struct Engines: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List verified installed engines.")
        @OptionGroup var options: Options
        func run() async throws { try Whisky.Runtime.emit(await options.store().installedEngines()) }
    }
    struct InstallEngine: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install-engine", abstract: "Verify and install an immutable signed runtime package.")
        @OptionGroup var options: Options
        @Option var catalog: String
        @Option var archive: String
        @Option var engine: String
        @Option(
            help: "Independently trusted public keys JSON, never read from the runtime archive.") var trustKeys: String
        func run() async throws {
            let keys = try JSONDecoder().decode([
                String: Data].self, from: Data(contentsOf: URL(fileURLWithPath: trustKeys)))
            let envelope = try JSONDecoder().decode(
                SignedEnvelope.self, from: Data(contentsOf: URL(fileURLWithPath: catalog)))
            try Whisky.Runtime.emit(await options.store(keys: keys).install(
                engineID: engine, envelope: envelope, archive: URL(fileURLWithPath: archive)))
        }
    }
    struct Probe: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the selected engine's version probe; no game compatibility claim.")
        @OptionGroup var options: Options
        @Option var engine: String
        func run() async throws {
            let installed = try await options.store().engine(id: engine)
            try Whisky.Runtime.emit([
                "engineID": engine, "versionOutput": await RuntimeAdapter.probeVersion(engine: installed)])
        }
    }
    struct Environments: AsyncParsableCommand {
        @OptionGroup var options: Options
        func run() async throws { try Whisky.Runtime.emit(await options.coordinator().environments()) }
    }
    struct CreateEnvironment: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create-environment")
        @OptionGroup var options: Options
        @Option var engine: String
        @Option var name: String
        @Option var backend: String = "wineD3D"
        func run() async throws {
            guard let backend = GraphicsBackend(
                rawValue: backend) else { throw ValidationError("Unknown graphics backend") }
            let installed = try await options.store().engine(id: engine)
            try HostProbe.inspect(storageURL: installed.directory).validate(for: installed.manifest)
            try Whisky.Runtime.emit(await options.coordinator().create(
                name: name, manifest: installed.manifest, backend: backend, synchronization: "none"))
        }
    }
    struct Initialize: AsyncParsableCommand {
        @OptionGroup var options: Options
        @Option var environment: String
        func run() async throws {
            let coordinator = try options.coordinator()
            let lease = try await coordinator.lease(id: environment)
            let installed = try await options.store().engine(id: lease.environment.binding.engineID)
            try RuntimeAdapter.preflight(engine: installed, lease: lease)
            try await coordinator.markStatus(.initializing, lease: lease)
            do {
                try await RuntimeAdapter.initialize(engine: installed, lease: lease,
                    log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) })
                try await coordinator.markStatus(.created, lease: lease)
            } catch {
                try? await coordinator.markStatus(.needsAttention, lease: lease)
                throw error
            }
            try Whisky.Runtime.emit(await coordinator.environment(id: environment))
        }
    }
    struct Clone: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Copy an idle environment into a new immutable engine/backend binding.")
        @OptionGroup var options: Options
        @Option var environment: String
        @Option var engine: String
        @Option var name: String
        @Option var backend: String
        func run() async throws {
            guard let backend = GraphicsBackend(rawValue: backend) else { throw ValidationError("Unknown backend") }
            let coordinator = try options.coordinator()
            let source = try await coordinator.recoveryLease(id: environment)
            defer { withExtendedLifetime(source) {} }
            let oldEngine = try await options.store().engine(id: source.environment.binding.engineID)
            let target = try await options.store().engine(id: engine)
            try await RuntimeAdapter.confirmIdle(engine: oldEngine, lease: source)
            let copied = try await coordinator.cloneIdleEnvironment(
                source: source, name: name, manifest: target.manifest, backend: backend)
            let lease = try await coordinator.lease(id: copied.id)
            if let path = copied.steamRelativePath { try await coordinator.attachSteam(relativePath: path,
                lease: lease) }
            try Whisky.Runtime.emit(await coordinator.environment(id: copied.id))
        }
    }
    struct ArchiveEnvironment: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "archive-environment",
            abstract: "Remove an idle environment from the list while retaining its files and saves.")
        @OptionGroup var options: Options
        @Option var environment: String
        func run() async throws {
            let coordinator = try options.coordinator()
            let lease = try await coordinator.lease(id: environment)
            let engine = try await options.store().engine(id: lease.environment.binding.engineID)
            try await RuntimeAdapter.confirmIdle(engine: engine, lease: lease)
            try await coordinator.archive(lease: lease)
        }
    }
    struct RestoreEnvironment: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "restore-environment")
        @OptionGroup var options: Options
        @Option var environment: String
        func run() async throws { try await options.coordinator().restore(id: environment) }
    }
    struct Recover: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Wait for an interrupted environment to become idle and revalidate Windows Steam.")
        @OptionGroup var options: Options
        @Option var environment: String
        func run() async throws {
            let coordinator = try options.coordinator()
            let lease = try await coordinator.recoveryLease(id: environment)
            defer { withExtendedLifetime(lease) {} }
            let installed = try await options.store().engine(id: lease.environment.binding.engineID)
            try await RuntimeAdapter.confirmIdle(engine: installed, lease: lease)
            if let path = lease.environment.steamRelativePath {
                try await coordinator.attachSteam(relativePath: path, lease: lease)
            } else {
                try await coordinator.markStatus(.created, lease: lease)
            }
            try Whisky.Runtime.emit(await coordinator.environment(id: environment))
        }
    }
    struct AttachSteam: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "attach-steam")
        @OptionGroup var options: Options
        @Option var environment: String
        @Option var relativePath: String = "drive_c/Program Files (x86)/Steam/Steam.exe"
        func run() async throws {
            let coordinator = try options.coordinator()
            let lease = try await coordinator.lease(id: environment)
            try await coordinator.attachSteam(relativePath: relativePath, lease: lease)
            try Whisky.Runtime.emit(await coordinator.environment(id: environment))
        }
    }
    struct Launch: AsyncParsableCommand {
        @OptionGroup var options: Options
        @Option var environment: String
        @Option var appID: UInt32?
        @Flag(help: "Use a fixed Wine desktop to diagnose transparent-window input.") var virtualDesktop = false
        @Option(
            help: "Trace window/input events for one executable basename (Wine 11 diagnostic only)."
        ) var traceWindowProcess: String?
        func run() async throws {
            _ = try RuntimeAdapter.debugChannels(dxmt: false, traceProcess: traceWindowProcess)
            let coordinator = try options.coordinator()
            let lease = try await coordinator.lease(id: environment)
            let installed = try await options.store().engine(id: lease.environment.binding.engineID)
            try RuntimeAdapter.preflight(engine: installed, lease: lease)
            guard lease.environment.status == .ready, let steamPath = lease.environment.steamRelativePath else {
                throw RuntimeError.unboundEnvironment
            }
            _ = try WindowsSteamCommand(prefix: lease.environment.prefix, steamRelativePath: steamPath,
                appID: appID)
            try await coordinator.markStatus(.running, lease: lease)
            do {
                let request = LaunchRequest(environmentID: environment, appID: appID)
                try await RuntimeAdapter.launch(
                    request: request, engine: installed, lease: lease, virtualDesktop: virtualDesktop,
                    traceWindowProcess: traceWindowProcess,
                    control: { event in try? Whisky.Runtime.emit(event) },
                log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) })
                try await coordinator.markStatus(lease.environment.status, lease: lease)
            } catch {
                try? await coordinator.markStatus(.needsAttention, lease: lease)
                throw error
            }
        }
    }
    struct RepairComponents: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "repair-components",
            abstract: "Repair VC++ and install legacy DirectX using Steam redistributables in an idle environment."
        )
        @OptionGroup var options: Options
        @Option var environment: String
        @Option(
            help: "Directory with official VC++ and DirectX installers for provisioning before Steam is installed."
        ) var installerDirectory: String?
        @Flag(
            help: "Install components into a fresh environment instead of repairing an existing installation."
        ) var install = false
        func run() async throws {
            let coordinator = try options.coordinator()
            let lease = try await coordinator.lease(id: environment)
            let installed = try await options.store().engine(id: lease.environment.binding.engineID)
            try RuntimeAdapter.preflight(engine: installed, lease: lease)
            try await RuntimeAdapter.confirmIdle(engine: installed, lease: lease)
            let common: URL
            if let installerDirectory {
                common = URL(fileURLWithPath: installerDirectory, isDirectory: true)
            } else {
                guard let steamPath = lease.environment.steamRelativePath else {
                    throw RuntimeError.unboundEnvironment }
                let steam = try ManagedPath.child(steamPath, under: lease.environment.prefix)
                common = steam.deletingLastPathComponent().appending(
                    path: "steamapps/common/Steamworks Shared/_CommonRedist")
            }
            let installers = try CommonRuntimeComponent.allCases.map { component in
                let file = try ManagedPath.child(component.relativeInstallerPath, under: common)
                try WindowsSteamCommand.validatePE(file)
                return (component, file)
            }
            try await coordinator.markStatus(.running, lease: lease)
            do {
                for (component, installer) in installers {
                    let status = try await RuntimeAdapter.repairCommonComponent(
                        component, engine: installed, lease: lease, installer: installer, install: install,
                        log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) })
                    try Whisky.Runtime.emit(["component": component.rawValue, "installerExitStatus": String(status)])
                }
                try await coordinator.markStatus(lease.environment.status, lease: lease)
            } catch {
                try? await coordinator.markStatus(.needsAttention, lease: lease)
                throw error
            }
        }
    }
    struct InstallSteam: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install-steam",
            abstract: "Run the official Windows Steam installer. Complete the installer UI yourself."
        )
        @OptionGroup var options: Options
        @Option var environment: String
        @Option var installer: String
        func run() async throws {
            let coordinator = try options.coordinator()
            let lease = try await coordinator.lease(id: environment)
            let installed = try await options.store().engine(id: lease.environment.binding.engineID)
            try RuntimeAdapter.preflight(engine: installed, lease: lease)
            try WindowsSteamCommand.validatePE(URL(fileURLWithPath: installer))
            try await coordinator.markStatus(.running, lease: lease)
            do {
                try await RuntimeAdapter.runSteamInstaller(
                    engine: installed, lease: lease, installer: URL(fileURLWithPath: installer),
                log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) })
                try await coordinator.markStatus(lease.environment.status, lease: lease)
            } catch {
                try? await coordinator.markStatus(.needsAttention, lease: lease)
                throw error
            }
        }
    }
}
