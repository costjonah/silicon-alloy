import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var isLoading = false
    @Published var showCreateBottle = false
    @Published var showRecipeBrowser = false
    @Published var alert: AppAlert?
    @Published var serviceInfo: ServiceInfo?
    @Published var recipes: [RecipeSummary] = []

    private let bridge = DaemonBridge()

    init() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            serviceInfo = try await bridge.fetchServiceInfo()
            bottles = try await bridge.listBottles()
            recipes = try await bridge.listRecipes()
        } catch {
            alert = AppAlert(title: "failed to talk to daemon", message: error.localizedDescription)
        }
    }

    func createBottle(name: String, wineVersion: String, wineLabel: String?, winePath: URL?, channel: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await bridge.createBottle(
                name: name,
                wineVersion: wineVersion,
                wineLabel: wineLabel,
                winePath: winePath,
                channel: channel
            )
            showCreateBottle = false
            bottles = try await bridge.listBottles()
        } catch {
            alert = AppAlert(title: "could not create bottle", message: error.localizedDescription)
        }
    }

    func deleteBottle(id: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await bridge.deleteBottle(id: id)
            bottles.removeAll { $0.id == id }
        } catch {
            alert = AppAlert(title: "delete failed", message: error.localizedDescription)
        }
    }

    func runExecutable(id: UUID, executable: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await bridge.runExecutable(id: id, executable: executable)
        } catch {
            alert = AppAlert(
                title: "launch failed",
                message: "\(error.localizedDescription)\ncheck log for details."
            )
        }
    }

    func applyRecipe(_ recipe: RecipeSummary, to bottle: Bottle) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await bridge.applyRecipe(recipeId: recipe.id, bottleId: bottle.id)
            alert = AppAlert(
                title: "recipe applied",
                message: "\(recipe.name) finished for \(bottle.name)."
            )
            bottles = try await bridge.listBottles()
        } catch {
            alert = AppAlert(
                title: "recipe failed",
                message: error.localizedDescription
            )
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

