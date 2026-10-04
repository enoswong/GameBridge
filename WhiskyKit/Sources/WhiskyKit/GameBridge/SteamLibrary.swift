// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum SteamPlatform: String, Codable, Sendable { case nativeMacOS, windowsWine }
public struct SteamInstalledGame: Codable, Sendable, Identifiable {
    public var id: String { libraryURL.path + ":" + String(appID) }
    public let appID: UInt32
    public let name: String
    public let buildID: String?
    public let installDirectory: URL
    public let libraryURL: URL
    public let stateFlags: UInt64
    public let platform: SteamPlatform
    public var isFullyInstalled: Bool { stateFlags == 4 }
}
public struct SteamScanIssue: Codable, Sendable {
    public let path: String
    public let message: String
}
public struct SteamLibrarySnapshot: Codable, Sendable {
    public let games: [SteamInstalledGame]
    public let issues: [SteamScanIssue]
    public let scannedAt: Date
}
public enum SteamLibraryScanner {
    public static func scanNativeMac(steamRoot: URL) throws -> SteamLibrarySnapshot {
        try scan(steamRoot: steamRoot, prefix: nil)
    }
    public static func scanWindows(steamRoot: URL, prefix: URL) throws -> SteamLibrarySnapshot {
        try WindowsSteamCommand.validatePE(steamRoot.appending(path: "Steam.exe"))
        return try scan(steamRoot: steamRoot, prefix: prefix)
    }
    private static func scan(steamRoot: URL, prefix: URL?) throws -> SteamLibrarySnapshot {
        var libraries = [steamRoot.standardizedFileURL.resolvingSymlinksInPath()]
        var issues: [SteamScanIssue] = []
        let foldersFile = steamRoot.appending(path: "steamapps/libraryfolders.vdf")
        guard FileManager.default.fileExists(atPath: steamRoot.appending(path: "steamapps").path) else {
            throw SteamMetadataError.unavailable(steamRoot.path)
        }
        if FileManager.default.fileExists(atPath: foldersFile.path) {
            do {
                let folders = try ValveKeyValues.read(foldersFile).object("libraryfolders")
                for key in folders.values.keys.sorted() where UInt32(key) != nil {
                    guard let value = folders.values[key] else { continue }
                    let path: String
                    switch value {
                    case .string(let text): path = text
                    case .object(let folder): path = try folder.string("path")
                    }
                    let library: URL
                    if let prefix {
                        let normalized = path.replacingOccurrences(of: "\\", with: "/")
                        guard normalized.lowercased().hasPrefix("c:/") else { throw SteamMetadataError.unavailable(path) }
                        library = try ManagedPath.child("drive_c/" + String(normalized.dropFirst(3)), under: prefix)
                    } else {
                        guard path.hasPrefix("/"), !path.contains("\0") else { throw SteamMetadataError.malformed }
                        library = URL(fileURLWithPath: path)
                    }
                    let canonical = library.standardizedFileURL.resolvingSymlinksInPath()
                    if !libraries.contains(canonical) { libraries.append(canonical) }
                }
            } catch { issues.append(SteamScanIssue(path: foldersFile.path, message: error.localizedDescription)) }
        }
        var games: [SteamInstalledGame] = []
        for library in libraries {
            let apps = library.appending(path: "steamapps")
            do {
                let files = try FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                    do {
                        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw SteamMetadataError.malformed }
                        let app = try ValveKeyValues.read(file).object("appstate")
                        guard let appID = UInt32(try app.string("appid")), appID > 0,
                              file.lastPathComponent == "appmanifest_\(appID).acf",
                              let flags = UInt64(try app.string("stateflags")) else { throw SteamMetadataError.malformed }
                        let directory = try app.string("installdir")
                        try ManagedPath.validateRelative(directory)
                        let location = try ManagedPath.child(directory, under: apps.appending(path: "common"))
                        games.append(SteamInstalledGame(appID: appID, name: try app.string("name"),
                                                        buildID: try? app.string("buildid"), installDirectory: location,
                                                        libraryURL: library, stateFlags: flags,
                                                        platform: prefix == nil ? .nativeMacOS : .windowsWine))
                    } catch { issues.append(SteamScanIssue(path: file.path, message: error.localizedDescription)) }
                }
            } catch { issues.append(SteamScanIssue(path: apps.path, message: error.localizedDescription)) }
        }
        return SteamLibrarySnapshot(games: games, issues: issues, scannedAt: Date())
    }
}
