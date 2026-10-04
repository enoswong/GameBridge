// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct WindowsSteamCommand: Sendable {
    public let arguments: [String]
    public let environment: [String: String]
    public init(prefix: URL, steamRelativePath: String, appID: UInt32?) throws {
        let executable = try ManagedPath.child(steamRelativePath, under: prefix)
        guard executable.lastPathComponent.lowercased() == "steam.exe" else { throw SteamMetadataError.notWindowsExecutable }
        try Self.validatePE(executable)
        if let appID, appID == 0 { throw SteamMetadataError.malformed }
        // CEF's D3D11 window surfaces can fail under Wine/DXMT independently of
        // game rendering. Keep Steam's browser UI on its software renderer.
        arguments = [executable.path, "-cef-disable-gpu"] + (appID.map { ["-applaunch", String($0)] } ?? [])
        environment = ["WINEPREFIX": prefix.path, "WINEDEBUG": "fixme-all"]
    }
    /// Fixed diagnostic desktop; no persisted game settings or registry changes.
    public func launchArguments(virtualDesktop: Bool) -> [String] {
        guard virtualDesktop else { return arguments }
        let windowsPath = "Z:" + arguments[0].replacingOccurrences(of: "/", with: "\\")
        return ["explorer.exe", "/desktop=GameBridge,1280x720", windowsPath] + arguments.dropFirst()
    }

    public static func validatePE(_ file: URL) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw SteamMetadataError.notWindowsExecutable }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 64), header.count == 64,
              header[0] == 0x4d, header[1] == 0x5a else { throw SteamMetadataError.notWindowsExecutable }
        let offset = (0..<4).reduce(UInt64(0)) { $0 | UInt64(header[0x3c + $1]) << ($1 * 8) }
        guard offset >= 64, offset + 6 <= UInt64(values.fileSize ?? 0) else { throw SteamMetadataError.notWindowsExecutable }
        try handle.seek(toOffset: offset)
        guard let signature = try handle.read(upToCount: 6), signature.count == 6,
              Array(signature.prefix(4)) == [0x50, 0x45, 0, 0],
              [[0x4c, 0x01], [0x64, 0x86], [0x64, 0xaa]].contains(Array(signature.suffix(2)))
        else { throw SteamMetadataError.notWindowsExecutable }
    }
}

public enum LaunchState: String, Codable, Sendable {
    case prepared, clientStarted, notConfirmed, gameObserved, userConfirmed, failed, exited
}
public struct LaunchEvidence: Codable, Sendable {
    public let sessionID: UUID
    public let appID: UInt32
    public let startedAt: Date
    public private(set) var state: LaunchState = .prepared
    public private(set) var observedProcessID: Int32?
    public private(set) var observedExecutable: String?
    public var isTeamVerified: Bool { false } // Team verification belongs to a separately reviewed evidence record.
    public init(appID: UInt32, startedAt: Date = Date()) {
        self.appID = appID; self.startedAt = startedAt; self.sessionID = UUID()
    }
    public mutating func clientDidStart() { if state == .prepared { state = .clientStarted } }
    public mutating func checkTimeout(now: Date) {
        if state == .clientStarted && now.timeIntervalSince(startedAt) >= 120 { state = .notConfirmed }
    }
    public mutating func observeGame(processID: Int32, executable: String) {
        guard processID > 0, !executable.isEmpty, [.clientStarted, .notConfirmed].contains(state) else { return }
        observedProcessID = processID; observedExecutable = executable; state = .gameObserved
    }
    public mutating func confirmByUser() { if state == .gameObserved { state = .userConfirmed } }
}
