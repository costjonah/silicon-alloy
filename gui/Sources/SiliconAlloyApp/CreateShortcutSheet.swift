import AppKit
import SwiftUI

struct CreateShortcutSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle

    @State private var shortcutName: String
    @State private var executablePath: String = ""
    @State private var destination: URL?

    init(bottle: Bottle) {
        self.bottle = bottle
        _shortcutName = State(initialValue: bottle.name)
        _destination = State(initialValue: CreateShortcutSheet.defaultDestination())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("create shortcut")
                .font(.title2)

            TextField("shortcut name", text: $shortcutName)
            TextField("windows executable path (e.g. C:\\\\Program Files\\\\app.exe)", text: $executablePath)

            HStack {
                Text(destination?.path ?? "~")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("choose folder…") {
                    chooseDestination()
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
                .disabled(shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executablePath.isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }

    private func submit() {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !executablePath.isEmpty else {
            return
        }
        Task {
            await appState.createShortcut(
                for: bottle,
                name: name,
                executable: executablePath,
                destination: destination
            )
            dismiss()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.prompt = "select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let destination {
            panel.directoryURL = destination
        }
        if panel.runModal() == .OK {
            destination = panel.url
        }
    }

    private static func defaultDestination() -> URL? {
        let fileManager = FileManager.default
        if let apps = fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first {
            let candidate = apps.appendingPathComponent("Silicon Alloy", isDirectory: true)
            return candidate
        }
        return nil
    }
}

