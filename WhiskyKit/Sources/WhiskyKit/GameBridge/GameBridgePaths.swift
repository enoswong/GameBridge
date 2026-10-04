// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum GameBridgePaths {
    public static var dataRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier).appending(path: "ManagedRuntime")
    }
}
