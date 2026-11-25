// SPDX-License-Identifier: GPL-3.0-or-later

/// Platform-independent Steam manifest classification; does not read or modify a Steam installation.
public enum SteamManifestPolicy {
    public static func isFullyInstalled(stateFlags: UInt64) -> Bool {
        stateFlags == 4
    }

    public static func hasDamage(stateFlags: UInt64) -> Bool {
        stateFlags & (32 | 128) != 0
    }

    public static func shouldInspect(appID: UInt32, stateFlags: UInt64, isWindows: Bool) -> Bool {
        isWindows && appID > 0 && appID != 228980
            && (isFullyInstalled(stateFlags: stateFlags) || hasDamage(stateFlags: stateFlags))
    }
}
