import SwiftUI

@main
struct SiliconAlloyApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("new bottle") {
                    appState.showCreateBottle.toggle()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

