//
//  Main.swift
//  WhiskyCmd
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import WhiskyKit
import SwiftyTextTable
import Progress
import SemanticVersion
import ArgumentParser

@main
struct Whisky: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gamebridge",
        abstract: "A CLI interface for GameBridge.",
        subcommands: [Runtime.self,
                      List.self,
                      Create.self,
                      Add.self,
//                      Export.self,
                      Delete.self,
                      Remove.self,
                      Run.self,
                      Shellenv.self
                      /*Install.self,
                      Uninstall.self*/])
}

extension Whisky {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List existing bottles.")

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let nameCol = TextTableColumn(header: "Name")
            let winVerCol = TextTableColumn(header: "Windows Version")
            let pathCol = TextTableColumn(header: "Path")

            var table = TextTable(columns: [nameCol, winVerCol, pathCol])
            for bottle in bottles {
                table.addRow(values: [bottle.settings.name,
                                      bottle.settings.windowsVersion.pretty(),
                                      bottle.url.prettyPath()])
            }

            print(table.render())
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new bottle.")

        @Argument var name: String

        mutating func run() throws {
            let bottleURL = BottleData.defaultBottleDir.appending(path: UUID().uuidString)

            do {
                try FileManager.default.createDirectory(atPath: bottleURL.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
                // Should allow customisation
                bottle.settings.windowsVersion = .win10
                bottle.settings.name = name
//                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
//                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(0, 0, 0)

                var bottlesList = BottleData()
                bottlesList.paths.append(bottleURL)
                print("Created new bottle \"\(name)\".")
            } catch {
                throw ValidationError("\(error)")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add an existing bottle.")

        @Argument var path: String

        mutating func run() throws {
            // Should be sanitised
            let bottleURL = URL(filePath: path)
            let settings = try BottleSettings.decode(from: bottleURL)
            var bottlesList = BottleData()
            bottlesList.paths.append(bottleURL)
            print("Bottle \"\(settings.name)\" added.")
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export an existing bottle.")

        mutating func run() throws {
//            print("Create a bottle")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete an existing bottle from disk.")

        @Argument var name: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            // Should ask for confirmation
            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove = bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                do {
                    try FileManager.default.removeItem(at: bottleToRemove.url)
                    print("Deleted \"\(name)\".")
                } catch {
                    print(error)
                }
            } else {
                throw ValidationError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove an existing bottle from GameBridge.",
                                                        discussion: "This will not remove the bottle from disk.")

        @Argument var name: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove = bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                print("Removed \"\(name)\".")
            } else {
                throw ValidationError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run a program with GameBridge.")

        @Argument var bottleName: String
        @Argument var path: String
        @Argument var args: [String] = []

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            let url = URL(fileURLWithPath: path)
            let program = Program(url: url, bottle: bottle)
            program.runInTerminal()
        }
    }

    struct Shellenv: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Prints export statements for a Bottle for eval.")

        @Argument var bottleName: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            let envCmd = Wine.generateTerminalEnvironmentCommand(bottle: bottle)
            print(envCmd)

        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install WhiskyWine.")

        mutating func run() throws {

        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Uninstall WhiskyWine.")

        @Flag(name: [.long, .short], help: "Uninstall WhiskyWine") var whiskyWine = false

        mutating func run() throws {

        }
    }
}

// GameBridge's managed runtime path. Legacy Whisky commands remain separate during migration.
extension Whisky {
    struct Runtime: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "runtime", abstract: "Manage verified GameBridge runtimes and Windows Steam environments.",
            subcommands: [Bootstrap.self, Host.self, ScanMac.self, Engines.self, InstallEngine.self, Probe.self, Environments.self,
                          CreateEnvironment.self, Initialize.self, AttachSteam.self, Launch.self, InstallSteam.self, RepairComponents.self, Recover.self, Clone.self, ArchiveEnvironment.self, RestoreEnvironment.self])

        struct Options: ParsableArguments {
            @Option(help: "GameBridge managed data directory.") var root: String = GameBridgePaths.dataRoot.path
            func store(keys: [String: Data] = [:]) throws -> EngineStore {
                try EngineStore(root: URL(fileURLWithPath: root), trustedKeys: keys)
            }
            func coordinator() throws -> EnvironmentCoordinator {
                try EnvironmentCoordinator(root: URL(fileURLWithPath: root))
            }
        }
        static func emit<T: Encodable>(_ value: T) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            var bytes = try encoder.encode(value)
            bytes.append(10)
            try FileHandle.standardOutput.write(contentsOf: bytes)
        }
        struct Bootstrap: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Prepare Windows Steam and bundled compatibility components.")
            @OptionGroup var options: Options
            @Option var payload: String?
            @Flag var newEnvironment = false
            @Flag var acceptComponentLicenses = false
            func run() async throws {
                guard acceptComponentLicenses else { throw ValidationError("Read the bundled Microsoft terms and pass --accept-component-licenses to install.") }
                guard let directory = payload.map({ URL(fileURLWithPath: $0) }) ?? BootstrapPayload.bundledDirectory() else {
                    throw ValidationError("This build has no bundled bootstrap payload.")
                }
                try Runtime.emit(await OneClickBootstrap.prepare(root: URL(fileURLWithPath: options.root), payloadDirectory: directory,
                    newEnvironment: newEnvironment, log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) }))
            }
        }
        struct Host: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Inspect this Mac without claiming game support.")
            @OptionGroup var options: Options
            func run() throws {
                let location = URL(fileURLWithPath: options.root)
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                try Runtime.emit(HostProbe.inspect(storageURL: location))
            }
        }
        struct ScanMac: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "scan-mac", abstract: "Read Mac Steam metadata for candidate discovery only.")
            @Option var steamRoot: String = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Steam").path
            func run() throws { try Runtime.emit(SteamLibraryScanner.scanNativeMac(steamRoot: URL(fileURLWithPath: steamRoot))) }
        }
        struct Engines: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "List verified installed engines.")
            @OptionGroup var options: Options
            func run() async throws { try Runtime.emit(await options.store().installedEngines()) }
        }
        struct InstallEngine: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "install-engine", abstract: "Verify and install an immutable signed runtime package.")
            @OptionGroup var options: Options
            @Option var catalog: String
            @Option var archive: String
            @Option var engine: String
            @Option(help: "Independently trusted public keys JSON, never read from the runtime archive.") var trustKeys: String
            func run() async throws {
                let keys = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: URL(fileURLWithPath: trustKeys)))
                let envelope = try JSONDecoder().decode(SignedEnvelope.self, from: Data(contentsOf: URL(fileURLWithPath: catalog)))
                try Runtime.emit(await options.store(keys: keys).install(engineID: engine, envelope: envelope, archive: URL(fileURLWithPath: archive)))
            }
        }
        struct Probe: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Run the selected engine's version probe; no game compatibility claim.")
            @OptionGroup var options: Options
            @Option var engine: String
            func run() async throws {
                let installed = try await options.store().engine(id: engine)
                try Runtime.emit(["engineID": engine, "versionOutput": await RuntimeAdapter.probeVersion(engine: installed)])
            }
        }
        struct Environments: AsyncParsableCommand {
            @OptionGroup var options: Options
            func run() async throws { try Runtime.emit(await options.coordinator().environments()) }
        }
        struct CreateEnvironment: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "create-environment")
            @OptionGroup var options: Options
            @Option var engine: String
            @Option var name: String
            @Option var backend: String = "wineD3D"
            func run() async throws {
                guard let backend = GraphicsBackend(rawValue: backend) else { throw ValidationError("Unknown graphics backend") }
                let installed = try await options.store().engine(id: engine)
                try HostProbe.inspect(storageURL: installed.directory).validate(for: installed.manifest)
                try Runtime.emit(await options.coordinator().create(name: name, manifest: installed.manifest, backend: backend, synchronization: "none"))
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
                try Runtime.emit(await coordinator.environment(id: environment))
            }
        }
        struct Clone: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Copy an idle environment into a new immutable engine/backend binding.")
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
                let copied = try await coordinator.cloneIdleEnvironment(source: source, name: name, manifest: target.manifest, backend: backend)
                let lease = try await coordinator.lease(id: copied.id)
                if let path = copied.steamRelativePath { try await coordinator.attachSteam(relativePath: path, lease: lease) }
                try Runtime.emit(await coordinator.environment(id: copied.id))
            }
        }
        struct ArchiveEnvironment: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "archive-environment", abstract: "Remove an idle environment from the list while retaining its files and saves.")
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
            static let configuration = CommandConfiguration(abstract: "Wait for an interrupted environment to become idle and revalidate Windows Steam.")
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
                try Runtime.emit(await coordinator.environment(id: environment))
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
                try Runtime.emit(await coordinator.environment(id: environment))
            }
        }
        struct Launch: AsyncParsableCommand {
            @OptionGroup var options: Options
            @Option var environment: String
            @Option var appID: UInt32?
            @Flag(help: "Use a fixed Wine desktop to diagnose transparent-window input.") var virtualDesktop = false
            @Option(help: "Trace window/input events for one executable basename (Wine 11 diagnostic only).") var traceWindowProcess: String?
            func run() async throws {
                _ = try RuntimeAdapter.debugChannels(dxmt: false, traceProcess: traceWindowProcess)
                let coordinator = try options.coordinator()
                let lease = try await coordinator.lease(id: environment)
                let installed = try await options.store().engine(id: lease.environment.binding.engineID)
                try RuntimeAdapter.preflight(engine: installed, lease: lease)
                guard lease.environment.status == .ready, let steamPath = lease.environment.steamRelativePath else {
                    throw RuntimeError.unboundEnvironment
                }
                _ = try WindowsSteamCommand(prefix: lease.environment.prefix, steamRelativePath: steamPath, appID: appID)
                try await coordinator.markStatus(.running, lease: lease)
                do {
                    try await RuntimeAdapter.launch(request: LaunchRequest(environmentID: environment, appID: appID), engine: installed, lease: lease, virtualDesktop: virtualDesktop, traceWindowProcess: traceWindowProcess,
                        control: { event in try? Runtime.emit(event) },
                    log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) })
                    try await coordinator.markStatus(lease.environment.status, lease: lease)
                } catch {
                    try? await coordinator.markStatus(.needsAttention, lease: lease)
                    throw error
                }
            }
        }
        struct RepairComponents: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "repair-components", abstract: "Repair installed VC++ x64/x86 and install legacy DirectX using Steam's downloaded common redistributables in an idle environment.")
            @OptionGroup var options: Options
            @Option var environment: String
            @Option(help: "Directory containing official vcredist/2022 and DirectX/Jun2010 installers; permits provisioning before Steam is installed.") var installerDirectory: String?
            @Flag(help: "Install components into a fresh environment instead of repairing an existing installation.") var install = false
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
                    guard let steamPath = lease.environment.steamRelativePath else { throw RuntimeError.unboundEnvironment }
                    let steam = try ManagedPath.child(steamPath, under: lease.environment.prefix)
                    common = steam.deletingLastPathComponent().appending(path: "steamapps/common/Steamworks Shared/_CommonRedist")
                }
                let installers = try CommonRuntimeComponent.allCases.map { component in
                    let file = try ManagedPath.child(component.relativeInstallerPath, under: common)
                    try WindowsSteamCommand.validatePE(file)
                    return (component, file)
                }
                try await coordinator.markStatus(.running, lease: lease)
                do {
                    for (component, installer) in installers {
                        let status = try await RuntimeAdapter.repairCommonComponent(component, engine: installed, lease: lease, installer: installer, install: install,
                            log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) })
                        try Runtime.emit(["component": component.rawValue, "installerExitStatus": String(status)])
                    }
                    try await coordinator.markStatus(lease.environment.status, lease: lease)
                } catch {
                    try? await coordinator.markStatus(.needsAttention, lease: lease)
                    throw error
                }
            }
        }
        struct InstallSteam: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "install-steam", abstract: "Run the official Windows Steam installer in a managed environment. Complete the installer UI yourself.")
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
                    try await RuntimeAdapter.runSteamInstaller(engine: installed, lease: lease, installer: URL(fileURLWithPath: installer),
                    log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) })
                    try await coordinator.markStatus(lease.environment.status, lease: lease)
                } catch {
                    try? await coordinator.markStatus(.needsAttention, lease: lease)
                    throw error
                }
            }
        }
    }
}
