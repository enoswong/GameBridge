// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class SteamLibraryTests: XCTestCase {
    func testUnicodeEscapesCommentsAndNestedObjects() throws {
        let document = try ValveKeyValues.parse(#"""
        // library fixture
        "libraryfolders" { "0" { "path" "C:\\遊戲 Library" "label" "A \"quote\"" "apps" { "570" "123" } } }
        """#)
        let folders = try document.object("libraryfolders")
        let folder = try folders.object("0")
        XCTAssertEqual(try folder.string("path"), "C:\\遊戲 Library")
        XCTAssertEqual(try folder.string("label"), "A \"quote\"")
    }
    func testTruncatedOrDuplicateMetadataIsNotAnEmptyLibrary() {
        for text in [#""libraryfolders" { "0" { "path" "cut""#, #""a" "1" "a" "2""#, #""a" { "b" }"#, #""a" "unterminated"#] {
            XCTAssertThrowsError(try ValveKeyValues.parse(text))
        }
    }
    func testScanRetainsGoodGamesAndReportsHalfWrittenManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appending(path: "steamapps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try #""AppState" { "appid" "480" "name" "測試 Game" "installdir" "Demo Game" "buildid" "12345" "StateFlags" "4" }"#.write(to: apps.appending(path: "appmanifest_480.acf"), atomically: true, encoding: .utf8)
        try #""AppState" { "appid" "570""#.write(to: apps.appending(path: "appmanifest_570.acf"), atomically: true, encoding: .utf8)
        let snapshot = try SteamLibraryScanner.scanNativeMac(steamRoot: root)
        XCTAssertEqual(snapshot.games.map(\.appID), [480])
        XCTAssertEqual(snapshot.games.first?.platform, .nativeMacOS)
        XCTAssertEqual(snapshot.games.first?.buildID, "12345")
        XCTAssertEqual(snapshot.issues.count, 1)
    }
    func testWrongFilenameAppIDAndInstallTraversalAreRejected() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appending(path: "steamapps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try #""AppState" { "appid" "481" "name" "bad" "installdir" "../../outside" "StateFlags" "4" }"#.write(to: apps.appending(path: "appmanifest_480.acf"), atomically: true, encoding: .utf8)
        let snapshot = try SteamLibraryScanner.scanNativeMac(steamRoot: root)
        XCTAssertTrue(snapshot.games.isEmpty)
        XCTAssertEqual(snapshot.issues.count, 1)
    }
    func testManagedPlayLibraryStartsEmptyBeforeSteamCreatesItsLibrary() throws {
        let prefix = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let steamPath = "drive_c/Program Files (x86)/Steam/Steam.exe"
        try writeWindowsSteam(to: prefix.appending(path: steamPath))

        let games = try SteamLibraryScanner.scanLaunchableWindows(prefix: prefix, steamRelativePath: steamPath)
        XCTAssertTrue(games.isEmpty)
    }

    func testManagedPlayLibraryListsOnlyCompleteGamesInTheDefaultLibrary() throws {
        let prefix = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let steamPath = "drive_c/Program Files (x86)/Steam/Steam.exe"
        let steam = prefix.appending(path: steamPath)
        try writeWindowsSteam(to: steam)
        let apps = steam.deletingLastPathComponent().appending(path: "steamapps")
        let otherApps = prefix.appending(path: "drive_c/OtherLibrary/steamapps")
        for (directory, appID, name, flags, installed) in [
            (apps, 481, "Zulu", 4, true),
            (apps, 482, "Alpha", 4, true),
            (apps, 483, "Downloading", 1026, true),
            (apps, 484, "Stale", 4, false),
            (apps, 228980, "Steamworks Common Redistributables", 4, true),
            (otherApps, 485, "Other library", 4, true)
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if installed {
                try FileManager.default.createDirectory(at: directory.appending(path: "common/\(name)"), withIntermediateDirectories: true)
            }
            try """
            "AppState" { "appid" "\(appID)" "name" "\(name)" "installdir" "\(name)" "StateFlags" "\(flags)" }
            """.write(to: directory.appending(path: "appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
        }
        try #""libraryfolders" { "1" { "path" "C:\\OtherLibrary" } }"#.write(
            to: apps.appending(path: "libraryfolders.vdf"), atomically: true, encoding: .utf8
        )

        let games = try SteamLibraryScanner.scanLaunchableWindows(prefix: prefix, steamRelativePath: steamPath)
        XCTAssertEqual(games.map(\.appID), [482, 481])
        XCTAssertTrue(games.allSatisfy { $0.platform == .windowsWine })
    }

    private func writeWindowsSteam(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pe = Data(repeating: 0, count: 128)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[0x3c] = 64
        pe[64] = 0x50; pe[65] = 0x45; pe[68] = 0x4c; pe[69] = 0x01
        try pe.write(to: file)
    }

    func testWindowsSteamMustBeAPEBinaryAndLaunchUsesItsPrefix() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let steam = root.appending(path: "drive_c/Program Files (x86)/Steam/Steam.exe")
        try FileManager.default.createDirectory(at: steam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("native-MachO-not-Windows".utf8).write(to: steam)
        XCTAssertThrowsError(try WindowsSteamCommand(prefix: root, steamRelativePath: "drive_c/Program Files (x86)/Steam/Steam.exe", appID: 480))
        var pe = Data(repeating: 0, count: 128)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[0x3c] = 64
        pe[64] = 0x50; pe[65] = 0x45; pe[68] = 0x4c; pe[69] = 0x01
        try pe.write(to: steam)
        let command = try WindowsSteamCommand(prefix: root, steamRelativePath: "drive_c/Program Files (x86)/Steam/Steam.exe", appID: 480)
        XCTAssertEqual(command.arguments, [steam.path, "-cef-disable-gpu", "-applaunch", "480"])
        let library = try WindowsSteamCommand(prefix: root, steamRelativePath: "drive_c/Program Files (x86)/Steam/Steam.exe", appID: nil)
        XCTAssertEqual(library.arguments, [steam.path, "-cef-disable-gpu"])
        XCTAssertEqual(command.environment["WINEPREFIX"], root.path)
        XCTAssertFalse(command.arguments.contains(where: { $0.contains("steam://") }))
        XCTAssertEqual(command.launchArguments(virtualDesktop: false), command.arguments)
        let desktop = command.launchArguments(virtualDesktop: true)
        XCTAssertEqual(Array(desktop.prefix(2)), ["explorer.exe", "/desktop=GameBridge,1280x720"])
        XCTAssertEqual(desktop[2], "Z:" + steam.path.replacingOccurrences(of: "/", with: "\\"))
        XCTAssertEqual(Array(desktop.suffix(2)), ["-applaunch", "480"])

    }
    func testClientStartAndTimeoutNeverBecomeVerifiedGamePlay() throws {
        var session = LaunchEvidence(appID: 480, startedAt: RuntimeFixture.now)
        session.clientDidStart()
        session.checkTimeout(now: RuntimeFixture.now.addingTimeInterval(121))
        XCTAssertEqual(session.state, .notConfirmed)
        XCTAssertFalse(session.isTeamVerified)
        session.observeGame(processID: 123, executable: "game.exe")
        XCTAssertEqual(session.state, .gameObserved)
        XCTAssertFalse(session.isTeamVerified)
        session.confirmByUser()
        XCTAssertEqual(session.state, .userConfirmed)
        XCTAssertFalse(session.isTeamVerified)
    }
}
