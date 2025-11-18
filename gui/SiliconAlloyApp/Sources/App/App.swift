import SwiftUI

@main
struct SiliconAlloyApp: App {
    @StateObject private var store = BottleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

