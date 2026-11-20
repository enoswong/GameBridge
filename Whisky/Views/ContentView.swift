//
//  ContentView.swift
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
import UniformTypeIdentifiers
import WhiskyKit
import SemanticVersion

struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool

    @State private var selected: URL?
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var showBottleSelection: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)

    @State private var bottleFilter = ""
    @State private var managedEnvironments: [RuntimeEnvironment] = []
    @State private var managedError = ""
    @State private var navigationColumns: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $navigationColumns) {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            if navigationColumns != .detailOnly {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSetup = true
                    } label: {
                        Image(systemName: "plus")
                            .help("button.createBottle")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bottleVM.loadBottles()
                    Task { await refreshManagedEnvironments() }
                    if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
                        bottle.updateInstalledPrograms()
                    }
                    triggerRefresh.toggle()
                    withAnimation(.default) {
                        refreshAnimation = .degrees(360)
                    } completion: {
                        refreshAnimation = .degrees(0)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .help("button.refresh")
                        .rotationEffect(refreshAnimation)
                }
            }
        }
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showSetup) {
            ScrollView {
                SetupView(showSetup: $showSetup, firstTime: false)
            }
            .frame(width: 680, height: 420)
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: selected,
                         bottles: bottleVM.bottles)
        }
        .onChange(of: selected) {
            selectedBottleURL = selected
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            guard WhiskyWineInstaller.isWhiskyWineInstalled() else {
                showSetup = true
                return
            }
            openedFileURL = url
        }
        .task {
            bottleVM.loadBottles()
            selected = selectedBottleURL
            await refreshManagedEnvironments()
            if managedEnvironments.count > 1 || !bottleVM.bottles.isEmpty {
                navigationColumns = .all
            }
            bottlesLoaded = true

            if selected == nil { selected = bottleVM.bottles.first(where: { $0.isAvailable })?.url }
            if !managedEnvironments.isEmpty || bottleVM.bottles.isEmpty { return }
            if !WhiskyWineInstaller.isWhiskyWineInstalled() {
                showSetup = true
            }
            let task = Task.detached {
                return await WhiskyWineInstaller.shouldUpdateWhiskyWine()
            }
            let updateInfo = await task.value
            if updateInfo.0 {
                let alert = NSAlert()
                alert.messageText = String(localized: "update.whiskywine.title")
                alert.informativeText = String(format: String(localized: "update.whiskywine.description"),
                                               String(WhiskyWineInstaller.whiskyWineVersion()
                                                      ?? SemanticVersion(0, 0, 0)),
                                               String(updateInfo.1))
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.whiskywine.update"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    WhiskyWineInstaller.uninstall()
                    showSetup = true
                }
            }
        }
        .task(id: bottlesLoaded) {
            guard bottlesLoaded else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
                await refreshManagedEnvironments()
            }
        }
    }

    var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                Section("Windows 環境") {
                    ForEach(managedEnvironments.filter { bottleFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(bottleFilter) }) { environment in
                        Label {
                            VStack(alignment: .leading) {
                                Text(environment.name)
                                Text(environment.status == .running ? "執行中" : environment.status == .needsAttention ? "需要恢復" : "已建立")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "desktopcomputer") }
                            .tag(environment.prefix)
                    }
                    if managedEnvironments.isEmpty { Text("尚未建立 Windows 環境").foregroundStyle(.secondary) }
                    if !managedError.isEmpty { Text(managedError).font(.caption).foregroundStyle(.red) }
                }
                Section("舊版容器") {
                    ForEach(filteredBottles) { bottle in
                        Group {
                            if bottle.inFlight {
                                HStack {
                                    Text(bottle.settings.name)
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                                .opacity(0.5)
                            } else {
                                BottleListEntry(bottle: bottle, selected: $selected, refresh: $triggerRefresh)
                                    .selectionDisabled(!bottle.isAvailable)
                            }
                        }
                        .id(bottle.url)
                    }
                }
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: bottleFilter)
            .listStyle(.sidebar)
            .searchable(text: $bottleFilter, placement: .sidebar)
            .onChange(of: newlyCreatedBottleURL) { _, url in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    selected = url
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
            BottleView(bottle: bottle)
                .disabled(bottle.inFlight)
                .id(bottle.url)
        } else if bottlesLoaded {
            ScrollView {
                SetupView(showSetup: $showSetup, firstTime: false,
                          initialEnvironment: managedEnvironments.first(where: { $0.prefix == selected })?.id,
                          embedded: true)
            }
        }
    }

    @MainActor private func refreshManagedEnvironments() async {
        do {
            let coordinator = try EnvironmentCoordinator(root: GameBridgePaths.dataRoot)
            managedEnvironments = try await coordinator.environments().sorted { $0.createdAt < $1.createdAt }
            managedError = ""
            if let selected, !managedEnvironments.contains(where: { $0.prefix == selected }),
               !bottleVM.bottles.contains(where: { $0.url == selected && $0.isAvailable }) { self.selected = nil }
            if selected == nil {
                selected = managedEnvironments.first(where: { $0.steamRelativePath != nil })?.prefix
                    ?? managedEnvironments.first?.prefix
            }
        } catch { managedError = error.localizedDescription }
    }

    var filteredBottles: [Bottle] {
        if bottleFilter.isEmpty {
            bottleVM.bottles
                .sorted()
        } else {
            bottleVM.bottles
                .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
                .sorted()
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
