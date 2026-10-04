// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Verified compatibility profile bound to one environment and engine.
/// Schema 2 stages bundled components before the game is installed.
enum DeskrawlCompatibility {
    struct Profile: Codable {
        let schema: Int
        let engineID: String
        let bridgeSHA256: String
        let pointerSHA256: String
    }
    static let pointerPath = "drive_c/Program Files (x86)/Steam/steamapps/common/Deskrawl/version.dll"

    static func environment(prefix: URL, engineID: String) throws -> [String: String] {
        let root = prefix.deletingLastPathComponent()
        let profileURL = try ManagedPath.child("Compatibility/deskrawl-v1.json", under: root)
        guard FileManager.default.fileExists(atPath: profileURL.path) else { return [:] }
        let size = try profileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, (size.fileSize ?? Int.max) <= 4096 else {
            throw RuntimeError.invalidManifest("Deskrawl compatibility profile")
        }
        let profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: profileURL))
        guard [1, 2].contains(profile.schema), profile.engineID == engineID else {
            throw RuntimeError.invalidManifest("Deskrawl compatibility engine binding")
        }
        let bridge = try ManagedPath.child("Compatibility/deskrawl-alpha.dylib", under: root)
        let pointer = profile.schema == 1
            ? try ManagedPath.child(pointerPath, under: prefix)
            : try ManagedPath.child("Compatibility/deskrawl-pointer.dll", under: root)
        for (file, hash) in [(bridge, profile.bridgeSHA256), (pointer, profile.pointerSHA256)] {
            let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  try DigestTools.sha256(file: file, maximumBytes: 4 * 1024 * 1024).hash == hash else {
                throw RuntimeError.archiveHashMismatch
            }
        }
        // Each bridge additionally gates activation to Deskrawl.exe in-process.
        // The path must be one DYLD entry, not a colon-separated injection list.
        guard !bridge.path.contains(":") else { throw RuntimeError.unsafePath(bridge.path) }
        var result = ["DYLD_INSERT_LIBRARIES": bridge.path, "GAMEBRIDGE_DESKRAWL_ALPHA": "1"]
        if profile.schema == 2 {
            result["GAMEBRIDGE_DESKRAWL_POINTER"] = pointer.path
            result["GAMEBRIDGE_DESKRAWL_POINTER_SHA256"] = profile.pointerSHA256
        }
        return result
    }
    /// Called only with an idle environment lease, before Steam can spawn games.
    /// Explicit schema-1 profiles retain their already accepted local components.
    static func prepareBundled(prefix: URL, engineID: String, directory: URL?) throws -> Bool {
        guard let directory else { return false }
        let profileURL = try ManagedPath.child("Compatibility/deskrawl-v1.json", under: prefix.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: profileURL.path) {
            _ = try environment(prefix: prefix, engineID: engineID)
            let profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: profileURL))
            if profile.schema == 1 { return false }
        }
        let payload = try BootstrapPayload.load(from: directory)
        guard payload.engineID == engineID else { return false }
        try provision(payload: payload, directory: directory, prefix: prefix)
        return true
    }

    static func provision(payload: BootstrapPayload, directory: URL, prefix: URL) throws {
        _ = try BootstrapPayload.load(from: directory)
        let root = prefix.deletingLastPathComponent()
        let output = try ManagedPath.child("Compatibility", under: root)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, source) in [("deskrawl-alpha.dylib", payload.bridgeFile), ("deskrawl-pointer.dll", payload.pointerFile)] {
            let target = try ManagedPath.child(name, under: output)
            try Data(contentsOf: ManagedPath.child(source, under: directory)).write(to: target, options: .atomic)
        }
        let profile = Profile(schema: 2, engineID: payload.engineID, bridgeSHA256: payload.bridgeSHA256, pointerSHA256: payload.pointerSHA256)
        try JSONEncoder().encode(profile).write(to: ManagedPath.child("deskrawl-v1.json", under: output), options: .atomic)
    }

}
