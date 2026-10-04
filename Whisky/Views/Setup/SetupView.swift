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
    @State private var acceptTerms = false
    @State private var showTerms = false

    private var selection: RuntimeEnvironment? { environments.first { $0.id == selectedEnvironment } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GameBridge · Windows Steam").font(.title2.bold())
            Text("Windows 遊戲必須在 GameBridge 內的 Windows 版 Steam 安裝。Mac 版 Steam 的遊戲不會列入相容性驗收。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let payload = BootstrapPayload.bundledDirectory() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("首次使用").font(.headline)
                    Text("自動準備 Windows Steam、VC++、DirectX 與遊戲相容性修正。需要網絡及足夠的磁碟空間。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("閱讀 Microsoft 元件條款") { showTerms = true }
                    Toggle("我已閱讀並接受 Microsoft 元件授權條款", isOn: $acceptTerms)
                    Button("一鍵準備 Windows Steam") {
                        Task { await run(["bootstrap", "--accept-component-licenses"]) }
                    }.buttonStyle(.borderedProminent).disabled(busy || !acceptTerms)
                }
                .sheet(isPresented: $showTerms) {
                    VStack {
                        ScrollView {
                            Text(termsText(payload)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("關閉") { showTerms = false }
                    }.padding().frame(width: 680, height: 500)
                }
                Divider()
            }
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
                        Button("開啟 Windows Steam") { Task { await run(["launch", "--environment", selected.id]) } }
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
            Text("DXMT／DX11 遊戲相容性正在驗證；程序啟動不代表遊戲通過驗收。登入、授權與遊戲下載由 Windows Steam 處理。")
                .font(.caption).foregroundStyle(.secondary)
            if busy {
                HStack { ProgressView().controlSize(.small); Text("執行中。若已開啟 Windows Steam，請正常結束它以釋放環境。") }
            }
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            if !log.isEmpty {
                DisclosureGroup("執行記錄") {
                    ScrollView { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 130)
                }
            }
            HStack {
                Button("重新整理") { Task { await refresh() } }
                Spacer()
                if !embedded { Button("關閉") { showSetup = false }.keyboardShortcut(.cancelAction) }
            }
        }
        .padding(24).frame(width: 680)
        .task {
            selectedEnvironment = initialEnvironment ?? ""
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
                await refresh()
            }
        }
        .confirmationDialog("移除「\(selection?.name ?? "")」？", isPresented: $showRemoveConfirmation) {
            Button("移除環境", role: .destructive) {
                if let selected = selection { Task { await run(["archive-environment", "--environment", selected.id]) } }
            }
        } message: {
            Text("環境會從使用清單移除，遊戲安裝與存檔會保留。你可在「已移除的環境」恢復。")
        }
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

    private func termsText(_ payload: URL) -> String {
        ["microsoft-vc14-en.txt", "microsoft-directx-june2010-en.txt"].map {
            (try? String(contentsOf: payload.appendingPathComponent("Terms/" + $0), encoding: .utf8)) ?? "授權條款無法載入，請重新安裝 GameBridge。"
        }.joined(separator: "\n\n────────────\n\n")
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
        do {
            let store = try EngineStore(root: GameBridgePaths.dataRoot, trustedKeys: [:])
            engines = try await store.installedEngines()
            let coordinator = try EnvironmentCoordinator(root: GameBridgePaths.dataRoot)
            environments = try await coordinator.environments()
            archived = try await coordinator.archivedEnvironments()
            if !engines.contains(where: { $0.manifest.id == selectedEngine }) { selectedEngine = engines.first?.manifest.id ?? "" }
            if !environments.contains(where: { $0.id == selectedEnvironment }) { selectedEnvironment = environments.last?.id ?? "" }
        } catch { message = error.localizedDescription }
    }

    @MainActor private func run(_ arguments: [String]) async {
        guard !busy, let executable = Bundle.main.url(forResource: "WhiskyCmd", withExtension: nil) else {
            message = "找不到執行輔助程式。"; return
        }
        busy = true; message = ""; log = ""
        let operation = UUID()
        operationID = operation
        defer { if operationID == operation { busy = false } }
        do {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["runtime"] + arguments
            var status: Int32?
            var preparedEnvironment: String?
            for await event in try process.runStream(name: "GameBridge helper", fileHandle: nil) {
                switch event {
                case .message(let text), .error(let text):
                    if operationID == operation {
                        log = String((log + text).suffix(16000))
                        if arguments.first == "bootstrap" {
                            for line in log.split(separator: "\n").reversed() {
                                if let result = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                                   let id = result["id"] as? String { preparedEnvironment = id; break }
                            }
                        }
                        // The helper owns the session lease. Once prepared, allow browsing
                        // and managing other environments while Steam keeps running.
                        if arguments.first == "launch", text.contains("\"kind\":\"prepared\"") {
                            busy = false
                            await refresh()
                        }
                    }
                case .terminated(let child): status = child.terminationStatus
                default: break
                }
            }
            if operationID == operation {
                message = status == 0 ? "操作已完成。" : "操作未完成，請查看執行記錄。"
            }
            await refresh()
            if arguments.first == "bootstrap", status == 0, let id = preparedEnvironment {
                selectedEnvironment = id
                busy = false
                await run(["launch", "--environment", id])
            }
        } catch { if operationID == operation { message = error.localizedDescription } }
    }
}
