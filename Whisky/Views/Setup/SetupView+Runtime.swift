// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftUI
import WhiskyKit

extension SetupView {
    @MainActor func refresh() async {
        defer { loaded = true }
        rosettaInstalled = Rosetta2.isRosettaInstalled
        do {
            let store = try EngineStore(root: GameBridgePaths.dataRoot, trustedKeys: [:])
            engines = try await store.installedEngines()
            let coordinator = try EnvironmentCoordinator(root: GameBridgePaths.dataRoot)
            environments = try await coordinator.environments()
            archived = try await coordinator.archivedEnvironments()
            if !engines.contains(where: { $0.manifest.id == selectedEngine }) {
                selectedEngine = engines.first?.manifest.id ?? "" }
            if selection == nil {
                selectedEnvironment = environments.first(where: { $0.steamRelativePath != nil })?.id
                    ?? environments.last?.id ?? ""
            }
            if loadFailed { message = "" }
            loadFailed = false
            if showAdvancedSettings, let environment = selection, environment.status == .ready,
               let steamPath = environment.steamRelativePath {
                let games = await Task.detached(priority: .utility) {
                    try? SteamLibraryScanner.scanLaunchableWindows(
                        prefix: environment.prefix, steamRelativePath: steamPath
                    )
                }.value
                if !Task.isCancelled, selection?.id == environment.id {
                    libraryEnvironment = environment.id
                    gameLibrary = games
                }
            }
        } catch {
            loadFailed = true
            message = "未能讀取 Steam 設定，請重試。"
        }
    }

    @MainActor func launchSteam(in environment: String, appID: UInt32? = nil, verifyFiles: Bool = false) async {
        guard !busy else { return }
        lastLaunch = (environment, appID)
        failedLaunchEnvironment = nil
        let arguments = ["launch", "--environment", environment] + (appID.map { ["--app-id", String($0)] } ?? [])
        let libraryRepair = appID == nil && autoRepairLibrary ? ["--repair-library"] : []
        await run(arguments + libraryRepair + (verifyFiles ? ["--verify-files"] : []))
    }

    @MainActor @discardableResult func run(_ arguments: [String]) async -> Bool {
        guard !busy else { return false }
        guard let executable = Bundle.main.url(forResource: "WhiskyCmd", withExtension: nil) else {
            message = "此版本缺少執行元件，請重新安裝 GameBridge。"
            return false
        }
        let isBootstrap = arguments.first == "bootstrap"
        let isLaunch = arguments.first == "launch"
        busy = true; message = ""; log = ""
        bootstrapStage = isBootstrap ? .checkingRequirements : nil
        let operation = UUID()
        operationID = operation
        defer {
            if operationID == operation {
                busy = false
                bootstrapStage = nil
            }
        }
        do {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["runtime"] + arguments
            let (status, preparedEnvironment) = try await readEvents(
                process.runStream(name: "GameBridge helper", fileHandle: nil),
                command: arguments.first, operation: operation
            )
            let succeeded = status == 0 && (!isBootstrap || preparedEnvironment != nil)
            if operationID == operation {
                if succeeded {
                    if !isLaunch, !isBootstrap { message = "操作已完成。" }
                } else {
                    reportFailure(arguments)
                }
            }
            await refresh()
            if operationID == operation, succeeded, let id = preparedEnvironment {
                selectedEnvironment = id
                busy = false
                await launchSteam(in: id)
            }
            return succeeded
        } catch {
            if operationID == operation {
                log = String((log + "\n" + error.localizedDescription).suffix(16000))
                reportFailure(arguments)
            }
            return false
        }
    }

    @MainActor private func appendOutput(_ text: String, audit: Bool) {
        guard audit else {
            log = String((log + text).suffix(16_000))
            return
        }
        let limit = 1_000_000
        guard log.count <= limit else { return }
        let remaining = limit - log.count
        log += text.prefix(remaining)
        if text.count > remaining { log += "\n已達顯示上限，可用命令列讀取完整報告。\n" }
    }

    @MainActor private func readEvents(
        _ events: AsyncStream<ProcessOutput>, command: String?, operation: UUID
    ) async -> (status: Int32?, preparedEnvironment: String?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var status: Int32?
        var preparedEnvironment: String?
        var standardOutput = ""
        for await event in events {
            switch event {
            case .terminated(let child):
                status = child.terminationStatus
            case .error(let text) where operationID == operation:
                appendOutput(text, audit: command == "audit-legacy")
            case .message(let text) where operationID == operation:
                appendOutput(text, audit: command == "audit-legacy")
                guard command == "bootstrap" || command == "launch" else { continue }
                standardOutput += text
                while let newline = standardOutput.firstIndex(of: "\n") {
                    let line = Data(standardOutput[..<newline].utf8)
                    standardOutput.removeSubrange(...newline)
                    if command == "bootstrap" {
                        preparedEnvironment = readBootstrapEvent(line, decoder: decoder) ?? preparedEnvironment
                    } else if let control = try? decoder.decode(RunnerControlEvent.self, from: line) {
                        await receiveLaunchEvent(control, operation: operation)
                    }
                }
            default:
                break
            }
        }
        return (status, preparedEnvironment)
    }

    @MainActor private func receiveLaunchEvent(_ event: RunnerControlEvent, operation: UUID) async {
        guard operationID == operation else { return }
        switch event.kind {
        case "postSteamMaintenance":
            busy = true
            message = "Steam 已退出，正在處理新安裝或更新的遊戲…"
        case "auditingSteamLibrary":
            message = "正在檢查已安裝的 Steam 遊戲…"
        case "steamLibraryAuditNotice":
            message = "部分遊戲需進一步檢查，可在進階設定查看記錄。"
        case "steamLibraryAuditFinished":
            message = "已完成本次依賴檢查，正在開啟 Steam。"
        case "repairingGameDependencies":
            message = "正在補齊遊戲所需元件…"
        case "someDependenciesUnresolved":
            message = "部份元件仍未齊全。遊戲會繼續由 Steam 啟動。"
        case "verifyingGameFiles":
            message = "Windows Steam 將驗證遊戲檔案，完成後可在 Steam 開始遊戲。"
        case "gameDependenciesReady":
            message = ""
        case "clientStarted":
            // The helper keeps its lease until Steam and Wine exit.
            await refresh()
            if operationID == operation { busy = false }
        default:
            break
        }
    }

    private func readBootstrapEvent(_ line: Data, decoder: JSONDecoder) -> String? {
        if let stages = try? decoder.decode([String: BootstrapStage].self, from: line),
           let stage = stages["bootstrapStage"] {
            bootstrapStage = stage
            return nil
        }
        return (try? decoder.decode(RuntimeEnvironment.self, from: line))?.id
    }

    private func reportFailure(_ arguments: [String]) {
        switch arguments.first {
        case "bootstrap":
            message = "Steam 設定未完成。請確認網絡、磁碟空間及 macOS 的安裝提示，然後繼續設定。"
        case "launch":
            failedLaunchEnvironment = arguments.dropFirst(2).first
            message = "未能啟動 Steam 或遊戲。請先在 Steam 選單結束 Steam，再重試。"
        case "recover":
            message = "未能恢復 Steam。請確認已從 Steam 選單結束，再重試。"
        default:
            message = "操作未完成，可在進階設定查看執行記錄。"
        }
    }
}
