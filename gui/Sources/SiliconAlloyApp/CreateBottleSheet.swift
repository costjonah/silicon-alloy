import SwiftUI

struct CreateBottleSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var wineVersion: String = "9.0"
    @State private var wineLabel: String = ""
    @State private var winePath: URL?
    @State private var showFileImporter = false
    @State private var selectedChannel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("new bottle")
                .font(.title2)
            TextField("display name", text: $name)
            TextField("wine version", text: $wineVersion)
            TextField("runtime label (optional)", text: $wineLabel)
            HStack {
                Text(winePath?.lastPathComponent ?? "use bundled runtime")
                    .foregroundStyle(winePath == nil ? .secondary : .primary)
                Spacer()
                Button("choose runtime…") {
                    showFileImporter = true
                }
            }
            if !availableChannels.isEmpty {
                Picker("runtime channel", selection: $selectedChannel) {
                    ForEach(availableChannels, id: \.self) { channel in
                        Text(channel).tag(channel)
                    }
                }
            }
            HStack {
                Spacer()
                Button("cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("create") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || wineVersion.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.executable]
        ) { result in
            switch result {
            case .success(let url):
                winePath = url
            case .failure:
                winePath = nil
            }
        }
        .onAppear {
            if selectedChannel.isEmpty,
               let defaultChannel = availableChannels.first {
                selectedChannel = defaultChannel
            }
        }
    }

    private func submit() {
        Task {
            await appState.createBottle(
                name: name,
                wineVersion: wineVersion,
                wineLabel: wineLabel.isEmpty ? nil : wineLabel,
                winePath: winePath,
                channel: selectedChannel.isEmpty ? nil : selectedChannel
            )
        }
    }

    private var availableChannels: [String] {
        guard let info = appState.serviceInfo else { return [] }
        let channels = info.runtimes.map(\.channel)
        return Array(Set(channels)).sorted()
    }
}

