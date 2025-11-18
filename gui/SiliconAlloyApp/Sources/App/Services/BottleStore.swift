import AppKit
import Foundation
import SwiftUI

@MainActor
final class BottleStore: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var presentingCreateSheet = false

    func refresh() {
        perform(
            work: { client in try client.listBottles() },
            success: { [weak self] bottles in
                self?.bottles = bottles
                self?.statusMessage = "updated bottle list"
            }
        )
    }

    func createBottle(named name: String) {
        perform(
            work: { client in try client.createBottle(named: name) },
            success: { [weak self] _ in
                self?.statusMessage = "created bottle \(name)"
                self?.refresh()
            }
        )
    }

    func destroyBottle(named name: String) {
        perform(
            work: { client in try client.destroyBottle(named: name) },
            success: { [weak self] (_: Void) in
                self?.statusMessage = "removed bottle \(name)"
                self?.refresh()
            }
        )
    }

    func runExecutable(for name: String) {
        guard let url = pickExecutable() else { return }
        perform(
            work: { client in try client.runExecutable(in: name, executable: url.path, args: []) },
            success: { [weak self] exitCode in
                self?.statusMessage = "process exited with code \(exitCode)"
            }
        )
    }

    func ensureDaemonReachable() {
        perform(
            work: { client in try client.ping() },
            success: { [weak self] (_: Void) in
                self?.statusMessage = "daemon is reachable"
            }
        )
    }

    private func pickExecutable() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "choose a windows executable"
        panel.allowedFileTypes = ["exe", "msi", "bat", "com"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let result = panel.runModal()
        return result == .OK ? panel.url : nil
    }

    private func perform<T>(
        work: @escaping (DaemonClient) throws -> T,
        success: @escaping (T) -> Void
    ) {
        isBusy = true
        errorMessage = nil
        statusMessage = nil

        Task.detached { [weak self] in
            do {
                let client = try DaemonClient()
                let value = try work(client)
                await MainActor.run {
                    success(value)
                    self?.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                    self?.isBusy = false
                }
            }
        }
    }
}

