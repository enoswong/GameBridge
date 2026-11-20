// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import WhiskyKit

struct LegacyGameControls: View {
    let environment: RuntimeEnvironment?
    let run: @MainActor ([String]) async -> String?
    @State private var auditReport = ""
    @State private var showAudit = false
    @State private var showSetup = false
    @State private var reinstall = false

    var body: some View {
        Menu("舊遊戲檔案與元件") {
            Button("檢查已安裝的 Steam 遊戲") {
                guard let environment else { return }
                audit(["--environment", environment.id])
            }
            .disabled(environment?.steamRelativePath == nil)
            Button("檢查獨立 Windows 遊戲資料夾…") { selectDirectory() }
            Button("預先補齊 Visual C++…") { requestSetup(reinstall: false) }
                .disabled(!canPrepare)
            Button("重新安裝 Visual C++…") { requestSetup(reinstall: true) }
                .disabled(!canPrepare)
            if let help = URL(string: "https://help.steampowered.com/en/faqs/view/0C48-FCBD-DA71-93EB") {
                Link("Steam 驗證遊戲原裝檔案指引", destination: help)
            }
        }
        .sheet(isPresented: $showAudit) {
            VStack(alignment: .leading, spacing: 12) {
                Text("舊遊戲檔案檢查").font(.headline)
                ScrollView {
                    Text(auditReport).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("關閉") { showAudit = false }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: 660, height: 440)
        }
        .confirmationDialog("預先安裝舊版 Visual C++？", isPresented: $showSetup) {
            Button("開始安裝") {
                guard let environment else { return }
                let options = reinstall ? ["--reinstall"] : []
                let arguments = ["prepare-legacy", "--environment", environment.id] + options
                Task { _ = await run(arguments) }
            }
        } message: {
            Text("會從 Microsoft 下載並驗證舊版 Visual C++ 2005、2008、2010、2012、2013 安裝器。"
                + "請在每個安裝視窗閱讀條款並完成安裝。")
        }
    }

    private var canPrepare: Bool {
        environment?.status == .ready || environment?.status == .created
    }

    private func requestSetup(reinstall: Bool) {
        self.reinstall = reinstall
        showSetup = true
    }

    @MainActor private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.title = "選擇 Windows 遊戲資料夾"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let folder = panel.url {
            let options = environment.map { ["--environment", $0.id] } ?? []
            audit(options + ["--standalone-only", "--game-directory", folder.path])
        }
    }

    private func audit(_ arguments: [String]) {
        Task {
            if let report = await run(["audit-legacy", "--text"] + arguments) {
                auditReport = report
                showAudit = true
            }
        }
    }
}
