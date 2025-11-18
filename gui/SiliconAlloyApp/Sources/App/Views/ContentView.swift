import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BottleStore
    @State private var newBottleName: String = ""

    var body: some View {
        NavigationView {
            List(selection: .constant(nil)) {
                if store.bottles.isEmpty {
                    Text("no bottles yet. create one to get started.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(store.bottles) { bottle in
                        BottleRow(bottle: bottle)
                            .environmentObject(store)
                    }
                }
            }
            .listStyle(.inset)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        store.refresh()
                    } label: {
                        Label("refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        newBottleName = ""
                        store.presentingCreateSheet = true
                    } label: {
                        Label("new bottle", systemImage: "plus")
                    }
                    Button {
                        store.ensureDaemonReachable()
                    } label: {
                        Label("ping daemon", systemImage: "waveform.path.ecg")
                    }
                }
            }
            .navigationTitle("silicon alloy")

            VStack {
                Image(systemName: "wineglass")
                    .font(.system(size: 64))
                    .padding(.bottom, 16)
                Text("select a bottle to manage it")
                    .font(.headline)
                Spacer()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(isPresented: $store.presentingCreateSheet) {
            NewBottleSheet(isPresented: $store.presentingCreateSheet, name: $newBottleName) { name in
                store.createBottle(named: name)
            }
        }
        .overlay(alignment: .bottom) {
            StatusBanner(message: store.statusMessage, error: store.errorMessage, isBusy: store.isBusy)
                .padding()
        }
        .onAppear {
            store.refresh()
        }
    }
}

struct BottleRow: View {
    @EnvironmentObject var store: BottleStore
    let bottle: Bottle

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.name)
                    .font(.headline)
                Text("\(bottle.runtime.version) · \(bottle.runtime.arch)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let path = bottle.pathURL {
                    Text(path.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                store.runExecutable(for: bottle.name)
            } label: {
                Label("run", systemImage: "play.fill")
            }
            Button(role: .destructive) {
                store.destroyBottle(named: bottle.name)
            } label: {
                Label("delete", systemImage: "trash")
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatusBanner: View {
    let message: String?
    let error: String?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isBusy {
                ProgressView()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
            } else if let message {
                Label(message, systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else if isBusy {
                Text("working...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .animation(.easeInOut, value: message)
        .animation(.easeInOut, value: error)
    }
}

struct NewBottleSheet: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("create new bottle")
                .font(.title2)
            TextField("steam", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("cancel") {
                    isPresented = false
                }
                Button("create") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        name = ""
        isPresented = false
    }
}

