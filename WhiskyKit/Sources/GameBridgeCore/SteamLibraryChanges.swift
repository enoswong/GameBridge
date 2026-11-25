// SPDX-License-Identifier: GPL-3.0-or-later

/// A portable observation of a Steam manifest, not proof of file integrity.
public struct SteamManifestRevision: Sendable, Equatable {
    public let appID: UInt32
    public let buildID: String?
    public let stateFlags: UInt64
    public let needsVerification: Bool

    public init(appID: UInt32, buildID: String?, stateFlags: UInt64, needsVerification: Bool) {
        self.appID = appID
        self.buildID = buildID
        self.stateFlags = stateFlags
        self.needsVerification = needsVerification
    }
}

public enum SteamLibraryChanges {
    public static func changedAppIDs(
        before: [SteamManifestRevision], after: [SteamManifestRevision]
    ) -> [UInt32] {
        let previous = Dictionary(grouping: before, by: \.appID)
        let current = Dictionary(grouping: after, by: \.appID)
        return Set(previous.keys).union(current.keys).filter {
            previous[$0] != current[$0]
        }.sorted()
    }
}
