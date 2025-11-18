import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedBottle: Bottle?

    var body: some View {
        NavigationView {
            List(appState.bottles, selection: $selectedBottle) { bottle in
                BottleRow(bottle: bottle)
                    .contextMenu {
                        Button("launch executable") {
                            launchExecutable(for: bottle)
                        }
                        Button("delete bottle", role: .destructive) {
                            Task { await appState.deleteBottle(id: bottle.id) }
                        }
                    }
                    .tag(bottle)
            }
            .overlay {
                if appState.bottles.isEmpty {
                    ContentUnavailableView("no bottles yet", systemImage: "wineglass")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.showCreateBottle = true
                    } label: {
                        Label("new bottle", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.showRecipeBrowser = true
                    } label: {
                        Label("recipes", systemImage: "book.closed")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        if appState.isLoading {
                            ProgressView()
                        } else {
                            Label("refresh", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .disabled(appState.isLoading)
                }
            }
            .navigationTitle("silicon alloy")

            if let selectedBottle {
                BottleDetailView(bottle: selectedBottle)
            } else {
                Text("select a bottle to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $appState.showCreateBottle) {
            CreateBottleSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showRecipeBrowser) {
            RecipeBrowserView()
                .environmentObject(appState)
        }
        .alert(item: $appState.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("ok")))
        }
        .task {
            await appState.refresh()
        }
    }

    private func launchExecutable(for bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data, .item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "run"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await appState.runExecutable(id: bottle.id, executable: url)
            }
        }
    }
}

