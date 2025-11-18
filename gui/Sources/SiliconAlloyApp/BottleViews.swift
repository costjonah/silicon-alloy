import SwiftUI

struct BottleRow: View {
    let bottle: Bottle

    var body: some View {
        HStack {
            Image(systemName: "wineglass.fill")
                .foregroundStyle(.purple)
            VStack(alignment: .leading) {
                Text(bottle.name)
                    .font(.headline)
                Text("created \(bottle.createdAtFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(bottle.wineRuntime.label)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct BottleDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showShortcutSheet = false

    let bottle: Bottle

    var body: some View {
        Form {
            Section("runtime") {
                LabeledContent("label", value: bottle.wineRuntime.label)
                LabeledContent("version", value: bottle.wineRuntime.version)
                LabeledContent("wine64", value: bottle.wineRuntime.wine64Path.path)
                if let channel = bottle.wineRuntime.channel {
                    LabeledContent("channel", value: channel)
                }
            }

            Section("environment") {
                if bottle.environment.isEmpty {
                    Text("no overrides set")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bottle.environment, id: \.key) { pair in
                        LabeledContent(pair.key, value: pair.value)
                    }
                }
            }

            Section("actions") {
                Button("create mac shortcut") {
                    showShortcutSheet = true
                }
            }
        }
        .padding()
        .sheet(isPresented: $showShortcutSheet) {
            CreateShortcutSheet(bottle: bottle)
                .environmentObject(appState)
        }
    }
}

