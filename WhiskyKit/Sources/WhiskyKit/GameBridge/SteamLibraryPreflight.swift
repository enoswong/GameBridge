// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Read-only inspection of the managed Windows Steam library before the client starts.
public struct SteamLibraryPreflight: Sendable {
    public let reports: [LegacyGameAudit]
    public let damagedGames: [SteamInstalledGame]
    public let issues: [String]

    public var hasUnresolvedImports: Bool {
        reports.contains { !$0.unresolvedImports.isEmpty }
    }

    public static func scan(prefix: URL, steamRelativePath: String) throws -> Self {
        let games = try SteamLibraryScanner.scanLaunchableWindows(
            prefix: prefix, steamRelativePath: steamRelativePath
        )
        return try inspect(games: games, prefix: prefix)
    }

    static func inspect(games: [SteamInstalledGame], prefix: URL) throws -> Self {
        var reports: [LegacyGameAudit] = []
        var damaged: [SteamInstalledGame] = []
        var issues: [String] = []
        for game in games {
            try Task.checkCancellation()
            guard game.platform == .windowsWine, game.appID != 228980,
                  game.isInstalledOrDamaged else { continue }
            if game.filesNeedVerification {
                damaged.append(game)
                continue
            }
            do {
                let report = try LegacyGameAudit.scan(directory: game.installDirectory, prefix: prefix)
                reports.append(report)
                if report.scanLimitReached || !report.unreadableExecutables.isEmpty {
                    issues.append("Partial dependency scan: " + game.name)
                }
            } catch {
                issues.append("Unable to audit " + game.name + ": " + error.localizedDescription)
            }
        }
        return Self(reports: reports, damagedGames: damaged, issues: issues)
    }
}
