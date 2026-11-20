// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation
import WhiskyKit

private struct LegacyAuditOutput: Encodable {
    let reports: [LegacyGameAudit]
    let issues: [String]
}

extension Whisky.Runtime {
    struct AuditLegacy: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "audit-legacy",
            abstract: "Inspect Windows game folders and installed Windows Steam games for PE dependencies."
        )
        @OptionGroup var options: Options
        @Option(help: "Managed environment. Its installed Steam games are included unless disabled.")
        var environment: String?
        @Option(help: "A Windows game directory to scan. Repeat to scan more than one directory.")
        var gameDirectory: [String] = []
        @Flag(help: "Scan only the specified game directories.")
        var standaloneOnly = false
        @Flag(help: "Print a human-readable report.")
        var text = false

        func run() async throws {
            guard !gameDirectory.isEmpty || (environment != nil && !standaloneOnly) else {
                throw ValidationError("Specify an environment or one or more --game-directory paths.")
            }
            let environment = try await loadEnvironment()
            var directories = gameDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            var issues: [String] = []
            if let environment, !standaloneOnly {
                do {
                    let snapshot = try steamLibrary(in: environment)
                    directories += snapshot.games.filter {
                        $0.stateFlags & 4 != 0 && $0.appID != 228980
                    }.map(\.installDirectory)
                    issues += snapshot.issues.map { $0.path + ": " + $0.message }
                } catch {
                    issues.append(error.localizedDescription)
                }
            }
            var reports: [LegacyGameAudit] = []
            var seen = Set<URL>()
            for path in directories {
                let directory = path.standardizedFileURL.resolvingSymlinksInPath()
                guard seen.insert(directory).inserted else { continue }
                do {
                    reports.append(try LegacyGameAudit.scan(directory: directory, prefix: environment?.prefix))
                } catch {
                    issues.append(directory.path + ": " + error.localizedDescription)
                }
            }
            if text {
                let entries = reports.map(\.summary) + issues
                print(entries.isEmpty ? "未找到已安裝嘅 Windows 遊戲。" : entries.joined(separator: "\n\n"))
            } else {
                try Whisky.Runtime.emit(LegacyAuditOutput(reports: reports, issues: issues))
            }
        }

        private func loadEnvironment() async throws -> RuntimeEnvironment? {
            guard let environment else { return nil }
            return try await options.coordinator().environment(id: environment)
        }

        private func steamLibrary(in environment: RuntimeEnvironment) throws -> SteamLibrarySnapshot {
            guard let path = environment.steamRelativePath else { throw RuntimeError.unboundEnvironment }
            let steam = try ManagedPath.child(path, under: environment.prefix)
            return try SteamLibraryScanner.scanWindows(
                steamRoot: steam.deletingLastPathComponent(), prefix: environment.prefix
            )
        }
    }

    struct PrepareLegacy: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prepare-legacy",
            abstract: "Install optional Microsoft Visual C++ 2005–2013 x86 and x64 packages in one environment."
        )
        @OptionGroup var options: Options
        @Option var environment: String
        @Flag(help: "Run all installers again instead of resuming from the checkpoint.")
        var reinstall = false

        func run() async throws {
            let completed = try await LegacyVisualCpp.prepare(
                root: URL(fileURLWithPath: options.root), environmentID: environment, reinstall: reinstall,
                log: { text in try? FileHandle.standardError.write(contentsOf: Data(text.utf8)) }
            )
            try Whisky.Runtime.emit(["prepared": completed])
        }
    }
}
