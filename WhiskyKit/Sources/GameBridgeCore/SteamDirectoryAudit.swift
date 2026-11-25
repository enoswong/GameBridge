// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Read-only dependency inventory for a single managed Steam client directory.
public struct SteamDirectoryAudit: Sendable {
    public let reports: [PortableLegacyGameAudit]
    public let skippedDirectories: Int
    public let failedDirectories: Int

    public var unresolvedFamilies: [String] {
        Set(reports.flatMap(\.unresolvedImports).compactMap(\.component)).sorted()
    }

    public var isPartial: Bool {
        skippedDirectories > 0 || failedDirectories > 0 || reports.contains {
            $0.scanLimitReached || !$0.unreadableExecutables.isEmpty || $0.executablesScanned == 0
        }
    }

    public static func scan(prefix: URL, maxGames: Int = 16, maxExecutables: Int = 256) throws -> Self {
        let prefix = prefix.resolvingSymlinksInPath().standardizedFileURL
        let library = prefix.appending(path: "drive_c/Program Files/Steam Big Picture/steamapps/common")
        guard library.resolvingSymlinksInPath().standardizedFileURL.path == library.path else {
            throw PortableLegacyGameAudit.AuditError.unavailableDirectory(library.path)
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: library.path) else {
            return Self(reports: [], skippedDirectories: 0, failedDirectories: 0)
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = try fm.contentsOfDirectory(at: library, includingPropertiesForKeys: Array(keys))
        let directories = try entries.filter {
            let values = try $0.resourceValues(forKeys: keys)
            return values.isDirectory == true && values.isSymbolicLink == false
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let selected = directories.prefix(min(64, max(1, maxGames)))
        var reports: [PortableLegacyGameAudit] = []
        var failures = 0
        for directory in selected {
            try Task.checkCancellation()
            do {
                reports.append(try PortableLegacyGameAudit.scan(
                    directory: directory, prefix: prefix, maxExecutables: maxExecutables
                ))
            } catch {
                try Task.checkCancellation()
                failures += 1
            }
        }
        return Self(reports: reports, skippedDirectories: directories.count - selected.count,
                    failedDirectories: failures)
    }
}
