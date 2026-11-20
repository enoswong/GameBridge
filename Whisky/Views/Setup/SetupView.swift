//
//  SetupView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WhiskyKit
import UniformTypeIdentifiers

enum SetupStage {
    case rosetta
    case whiskyWineDownload
    case whiskyWineInstall
}

struct SetupView: View {
    @Binding var showSetup: Bool
    var firstTime: Bool = true
    var initialEnvironment: String? = nil
    var embedded: Bool = false
    @State private var engines: [InstalledEngine] = []
    @State private var environments: [RuntimeEnvironment] = []
    @State private var selectedEngine = ""
    @State private var selectedEnvironment = ""
    @State private var environmentName = "Windows Steam"
    @State private var busy = false
    @State private var message = ""
    @State private var log = ""
    @AppStorage("GameBridge.steamInstallerDirectory") private var installerDirectory = ""
    @State private var archived: [RuntimeEnvironment] = []
    @State private var showRemoveConfirmation = false
    @State private var operationID = UUID()
    @State private var acceptedTerms = false
    @State private var showTerms = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var rosettaInstalled = Rosetta2.isRosettaInstalled
    @State private var bootstrapStage: BootstrapStage?
    @State private var gameLibrary: [SteamInstalledGame]?
    @State private var libraryEnvironment: String?
    @State private var lastLaunch: (environment: String, appID: UInt32?)?
    @State private var failedLaunchEnvironment: String?

    private var selection: RuntimeEnvironment? { environments.first { $0.id == selectedEnvironment } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Windows 遊戲").font(.title2.bold())
            playerControls
                .disabled(busy)
            if busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(bootstrapStage.map(stageText) ?? "處理中…")
                }
            }
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            DisclosureGroup("進階設定") {
                VStack(alignment: .leading, spacing: 12) { advancedControls }
                    .padding(.top, 8)
                    .disabled(busy)
            }
            if !embedded {
                Button("關閉") { showSetup = false }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            selectedEnvironment = initialEnvironment ?? ""
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
                await refresh()
            }
        }
        .onChange(of: initialEnvironment) { _, environment in
            if let environment { selectedEnvironment = environment }
        }
        .sheet(isPresented: $showTerms) {
            let terms = BootstrapPayload.bundledDirectory().flatMap(termsText)
            VStack(alignment: .leading, spacing: 16) {
                Text("Microsoft 元件授權條款").font(.headline)
                ScrollView {
                    Text(terms ?? "授權條款無法載入，請重新安裝 GameBridge。")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("取消") { showTerms = false }.keyboardShortcut(.cancelAction)
                    Button("同意並開始") {
                        acceptedTerms = true
                        showTerms = false
                        startBootstrap()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(terms == nil || busy)
                }
            }
            .padding(24)
            .frame(width: 640, height: 420)
        }
        .confirmationDialog("移除「\(selection?.name ?? "")」？", isPresented: $showRemoveConfirmation) {
            Button("移除環境", role: .destructive) {
                if let selected = selection {
                    Task { await run(["archive-environment", "--environment", selected.id]) }
                }
            }
        } message: {
            Text("環境會從使用清單移除，遊戲安裝與存檔會保留。你可在「已移除的環境」恢復。")
        }
    }

    @ViewBuilder
    private var playerControls: some View {
        if !loaded {
            ProgressView("正在檢查 Steam 設定…")
        } else if loadFailed {
            Button("重試") { Task { await refresh() } }
                .buttonStyle(.borderedProminent)
        } else if let selected = selection, selected.steamRelativePath != nil {
            switch selected.status {
            case .ready:
                gameControls(for: selected)
            case .running:
                Text("Steam 正在執行。可在 Steam 收藏庫切換遊戲。")
                    .foregroundStyle(.secondary)
                Button("Steam 已關閉？重新檢查") {
                    Task { await run(["recover", "--environment", selected.id]) }
                }
            case .created, .initializing, .needsAttention:
                Text("上次的 Steam 設定或啟動未完成。").foregroundStyle(.secondary)
                retryButton(for: selected)
            }
        } else if BootstrapPayload.bundledDirectory() != nil {
            if rosettaInstalled {
                Text("準備 Windows 版 Steam，之後用你的 Steam 帳號安裝遊戲。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(acceptedTerms || selection != nil ? "繼續設定" : "開始設定") {
                    if acceptedTerms {
                        startBootstrap()
                    } else {
                        showTerms = true
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("請先安裝 Apple Rosetta。開啟一個 Intel 版 Mac App，然後按 macOS 提示安裝。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let help = URL(string: "https://support.apple.com/zh-hk/102527") {
                    Link("Apple Rosetta 安裝指引", destination: help)
                }
            }
        } else {
            Text("此版本未提供自動設定所需的元件。")
                .foregroundStyle(.secondary)
            if let releases = URL(string: "https://github.com/enoswong/GameBridge/releases") {
                Link("查看 GameBridge 下載", destination: releases)
            }
        }
    }

    @ViewBuilder
    private func gameControls(for environment: RuntimeEnvironment) -> some View {
        if failedLaunchEnvironment == environment.id {
            retryButton(for: environment)
        }
        if libraryEnvironment == environment.id, let gameLibrary {
            if gameLibrary.isEmpty {
                Text("在 Steam 登入後，將遊戲安裝到預設位置。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(gameLibrary) { game in
                    HStack {
                        Text(game.name)
                        Spacer()
                        Button("玩") { Task { await launchSteam(in: environment.id, appID: game.appID) } }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("玩 \(game.name)")
                    }
                }
            }
        } else if libraryEnvironment == environment.id {
            Text("暫時無法讀取遊戲清單。仍可從 Steam 開啟遊戲。").foregroundStyle(.secondary)
        } else {
            ProgressView("正在載入遊戲…")
        }
        Button("開啟 Steam") { Task { await launchSteam(in: environment.id) } }
    }

    private func retryButton(for environment: RuntimeEnvironment) -> some View {
        Button("修復並重試") {
            Task {
                let appID = lastLaunch?.environment == environment.id ? lastLaunch?.appID : nil
                if environment.status != .ready {
                    guard await run(["recover", "--environment", environment.id]) else { return }
                }
                await launchSteam(in: environment.id, appID: appID)
            }
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var advancedControls: some View {
            if engines.isEmpty {
                Text("尚未安裝已驗證的執行引擎。正式引擎發佈仍在準備中。")
            } else {
                Picker("建立環境的引擎", selection: $selectedEngine) {
                    ForEach(engines, id: \.manifest.id) { engine in
                        Text(engine.manifest.version + (engine.manifest.distribution == .internalOnly ? " · 內部研究版" : ""))
                            .tag(engine.manifest.id)
                    }
                }
                HStack {
                    TextField("環境名稱", text: $environmentName)
                    Button("建立 Windows 環境") {
                        Task { await run(["create-environment", "--engine", selectedEngine, "--name", environmentName, "--backend", engines.first(where: { $0.manifest.id == selectedEngine })?.manifest.backends.first?.rawValue ?? "wineD3D"]) }
                    }.disabled(selectedEngine.isEmpty || environmentName.isEmpty)
                    Button("檢查引擎") { Task { await run(["probe", "--engine", selectedEngine]) } }
                }
            }
            if !environments.isEmpty {
                Divider()
                Picker("Windows 環境", selection: $selectedEnvironment) {
                    ForEach(environments) { environment in
                        Text(environment.name).tag(environment.id)
                    }
                }
                if let selected = selection {
                    Text("目前環境引擎：\(engines.first(where: { $0.manifest.id == selected.binding.engineID })?.manifest.version ?? selected.binding.engineID)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(statusText(selected.status)).foregroundStyle(.secondary)
                    HStack {
                        Button("初始化") { Task { await run(["initialize", "--environment", selected.id]) } }
                            .disabled(selected.status != .created)
                        Button("安裝 Windows Steam…") { chooseSteamInstaller(for: selected.id) }
                            .disabled(selected.status != .created && selected.status != .ready)
                        Button("辨識已安裝的 Steam") { Task { await run(["attach-steam", "--environment", selected.id]) } }
                            .disabled(selected.status != .created && selected.status != .ready)
                        Button("開啟 Windows Steam") { Task { await launchSteam(in: selected.id) } }
                            .disabled(selected.status != .ready)
                    }
                    HStack {
                        Button("在 Finder 顯示") { NSWorkspace.shared.selectFile(selected.prefix.path, inFileViewerRootedAtPath: "") }
                        Button("恢復環境狀態") { Task { await run(["recover", "--environment", selected.id]) } }
                            .disabled(selected.status == .ready || selected.status == .created)
                        Button("移除環境…", role: .destructive) { showRemoveConfirmation = true }
                            .disabled(selected.status != .ready && selected.status != .created)
                    }
                }
            }
            if !archived.isEmpty {
                DisclosureGroup("已移除的環境（可恢復）") {
                    ForEach(archived) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Button("恢復") { Task { await run(["restore-environment", "--environment", item.id]) } }
                        }
                    }
                }
            }
            if !log.isEmpty {
                DisclosureGroup("執行記錄") {
                    ScrollView { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 130)
                }
            }
            Button("重新整理") { Task { await refresh() } }
    }

    @MainActor private func chooseSteamInstaller(for environmentID: String) {
        let panel = NSOpenPanel()
        panel.title = "選擇 Windows Steam 安裝程式"
        panel.message = "請選擇 SteamSetup.exe。這裡選擇的是安裝檔；Steam 將安裝到目前的 Windows 環境。"
        panel.prompt = "使用此安裝檔"
        panel.allowedContentTypes = [.exe]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        var isDirectory: ObjCBool = false
        if !installerDirectory.isEmpty,
           FileManager.default.fileExists(atPath: installerDirectory, isDirectory: &isDirectory),
           isDirectory.boolValue, FileManager.default.isReadableFile(atPath: installerDirectory) {
            panel.directoryURL = URL(fileURLWithPath: installerDirectory, isDirectory: true)
        } else {
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        panel.begin { result in
            guard result == .OK, let installer = panel.url else { return }
            installerDirectory = installer.deletingLastPathComponent().path
            Task { await run(["install-steam", "--environment", environmentID, "--installer", installer.path]) }
        }
    }

    private func termsText(_ payload: URL) -> String? {
        let terms = ["microsoft-vc14-en.txt", "microsoft-directx-june2010-en.txt"].compactMap {
            try? String(contentsOf: payload.appendingPathComponent("Terms/" + $0), encoding: .utf8)
        }
        guard terms.count == 2, terms.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        return terms.joined(separator: "\n\n────────────\n\n")
    }

    private func stageText(_ stage: BootstrapStage) -> String {
        switch stage {
        case .checkingRequirements: return "正在檢查安裝需求…"
        case .preparingEnvironment: return "正在準備 Windows 遊戲環境…"
        case .installingComponents: return "正在安裝遊戲所需的元件…"
        case .installingSteam: return "正在安裝 Steam…"
        case .finishing: return "正在完成相容性設定…"
        }
    }

    private func startBootstrap() {
        Task { await run(["bootstrap", "--accept-component-licenses", "--show-progress"]) }
    }

    private func statusText(_ status: EnvironmentStatus) -> String {
        switch status {
        case .created: return "環境已建立；可初始化及安裝 Windows Steam。"
        case .ready: return "已辨識 Windows Steam，可啟動。這不代表遊戲已通過測試。"
        case .running, .initializing: return "環境正在使用中；若上次執行中斷，需要先確認 Windows 程序已停止。"
        case .needsAttention: return "上次執行未完成，需要檢查記錄及恢復環境。"
        }
    }

    @MainActor private func refresh() async {
        defer { loaded = true }
        rosettaInstalled = Rosetta2.isRosettaInstalled
        do {
            let store = try EngineStore(root: GameBridgePaths.dataRoot, trustedKeys: [:])
            engines = try await store.installedEngines()
            let coordinator = try EnvironmentCoordinator(root: GameBridgePaths.dataRoot)
            environments = try await coordinator.environments()
            archived = try await coordinator.archivedEnvironments()
            if !engines.contains(where: { $0.manifest.id == selectedEngine }) { selectedEngine = engines.first?.manifest.id ?? "" }
            if selection == nil {
                selectedEnvironment = environments.first(where: { $0.steamRelativePath != nil })?.id
                    ?? environments.last?.id ?? ""
            }
            if loadFailed { message = "" }
            loadFailed = false
            if let environment = selection, environment.status == .ready,
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

    @MainActor private func launchSteam(in environment: String, appID: UInt32? = nil) async {
        guard !busy else { return }
        lastLaunch = (environment, appID)
        failedLaunchEnvironment = nil
        let arguments = ["launch", "--environment", environment] + (appID.map { ["--app-id", String($0)] } ?? [])
        await run(arguments)
    }

    @MainActor @discardableResult private func run(_ arguments: [String]) async -> Bool {
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
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var status: Int32?
            var preparedEnvironment: String?
            var standardOutput = ""
            for await event in try process.runStream(name: "GameBridge helper", fileHandle: nil) {
                switch event {
                case .error(let text):
                    if operationID == operation { log = String((log + text).suffix(16000)) }
                case .message(let text):
                    guard operationID == operation else { continue }
                    log = String((log + text).suffix(16000))
                    guard isBootstrap || isLaunch else { continue }
                    standardOutput += text
                    while let newline = standardOutput.firstIndex(of: "\n") {
                        let line = Data(standardOutput[..<newline].utf8)
                        standardOutput.removeSubrange(...newline)
                        if isBootstrap {
                            if let progress = try? decoder.decode([String: BootstrapStage].self, from: line),
                               let stage = progress["bootstrapStage"] {
                                bootstrapStage = stage
                            } else if let environment = try? decoder.decode(RuntimeEnvironment.self, from: line) {
                                preparedEnvironment = environment.id
                            }
                        } else if let control = try? decoder.decode(RunnerControlEvent.self, from: line),
                                  control.kind == "clientStarted" {
                            // The helper keeps its lease until Steam and Wine exit.
                            await refresh()
                            if operationID == operation { busy = false }
                        }
                    }
                case .terminated(let child): status = child.terminationStatus
                default: break
                }
            }
            let succeeded = status == 0 && (!isBootstrap || preparedEnvironment != nil)
            if operationID == operation {
                if succeeded {
                    message = isLaunch || isBootstrap ? "" : "操作已完成。"
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
