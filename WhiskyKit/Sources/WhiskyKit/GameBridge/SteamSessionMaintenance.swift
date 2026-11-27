// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GameBridgeCore

/// Observe manifests while Steam runs; never install shared DLLs until the session is idle.
public struct SteamSessionMaintenance {
    public let repair: GameFileRepair
    public let shouldRepair: Bool
    public let announce: @Sendable (String) -> Void

    public init(repair: GameFileRepair, shouldRepair: Bool, announce: @escaping @Sendable (String) -> Void) {
        self.repair = repair
        self.shouldRepair = shouldRepair
        self.announce = announce
    }

    public func prepare(steamPath: String) async throws {
        announce("auditingSteamLibrary")
        try await RuntimeAdapter.confirmIdle(engine: repair.engine, lease: repair.lease)
        let prefix = repair.lease.environment.prefix
        let audit: SteamLibraryPreflight
        do {
            audit = try SteamLibraryPreflight.scan(prefix: prefix, steamRelativePath: steamPath)
        } catch {
            try Task.checkCancellation()
            repair.log("[GameBridge] Library audit unavailable: " + error.localizedDescription + "\n")
            announce("steamLibraryAuditNotice")
            return
        }
        for issue in audit.issues { repair.log("[GameBridge] " + issue + "\n") }
        for game in audit.damagedGames {
            repair.log("[GameBridge] Steam file verification needed: " + game.name + "\n")
        }
        let unresolved = try await repairIfAuthorized(audit)
        announce(unresolved || !audit.damagedGames.isEmpty || !audit.issues.isEmpty
                 ? "steamLibraryAuditNotice" : "steamLibraryAuditFinished")
    }

    private func repairIfAuthorized(_ audit: SteamLibraryPreflight) async throws -> Bool {
        guard shouldRepair else { return audit.hasUnresolvedImports }
        let emit = announce
        let result = try await repair.installMissing(from: audit.reports) {
            emit("repairingGameDependencies")
        }
        return !result.pending.isEmpty || result.reports.contains { !$0.unresolvedImports.isEmpty }
    }

    public func revisions(steamPath: String) -> [SteamManifestRevision]? {
        Self.readRevisions(prefix: repair.lease.environment.prefix, steamPath: steamPath)
    }

    private static func readRevisions(prefix: URL, steamPath: String) -> [SteamManifestRevision]? {
        guard let snapshot = try? SteamLibraryScanner.scanManagedWindows(
            prefix: prefix, steamRelativePath: steamPath
        ), snapshot.issues.isEmpty else { return nil }
        return snapshot.games.map {
            SteamManifestRevision(appID: $0.appID, buildID: $0.buildID,
                                  stateFlags: $0.stateFlags, needsVerification: $0.filesNeedVerification)
        }
    }

    public func observe(steamPath: String, baseline: [SteamManifestRevision]?) -> Task<Bool, Never> {
        let prefix = repair.lease.environment.prefix
        let log = repair.log
        return Task.detached(priority: .utility) {
            var previous = baseline
            var changed = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                guard !Task.isCancelled else { break }
                guard let current = Self.readRevisions(prefix: prefix, steamPath: steamPath) else { continue }
                if let previous {
                    let ids = SteamLibraryChanges.changedAppIDs(before: previous, after: current)
                    if !ids.isEmpty {
                        changed = true
                        log("[GameBridge] Steam manifest changes observed; maintenance deferred until exit.\n")
                    }
                }
                previous = current
            }
            return changed
        }
    }

    public func finish(
        steamPath: String, baseline: [SteamManifestRevision]?, observedChange: Bool
    ) async throws {
        let final = revisions(steamPath: steamPath)
        if !observedChange, let baseline, let final,
           SteamLibraryChanges.changedAppIDs(before: baseline, after: final).isEmpty { return }
        announce("postSteamMaintenance")
        try await prepare(steamPath: steamPath)
    }
}
