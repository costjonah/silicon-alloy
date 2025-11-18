import SwiftUI

struct RecipeBrowserView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRecipe: RecipeSummary?
    @State private var selectedBottleID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("recipes")
                .font(.title2)

            if appState.recipes.isEmpty {
                ContentUnavailableView("no recipes found", systemImage: "book.closed")
            } else {
                List(selection: $selectedRecipe) {
                    ForEach(appState.recipes) { recipe in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.headline)
                            if let description = recipe.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(recipe as RecipeSummary?)
                    }
                }
                .frame(height: 240)

                Picker("target bottle", selection: $selectedBottleID) {
                    ForEach(appState.bottles) { bottle in
                        Text(bottle.name).tag(Optional.some(bottle.id))
                    }
                }

                HStack {
                    Spacer()
                    Button("close") {
                        dismiss()
                    }
                    Button("apply recipe") {
                        applySelection()
                    }
                    .disabled(selectedRecipe == nil || selectedBottleID == nil)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 520)
        .task {
            if selectedBottleID == nil {
                selectedBottleID = appState.bottles.first?.id
            }
            if selectedRecipe == nil {
                selectedRecipe = appState.recipes.first
            }
        }
    }

    private func applySelection() {
        guard let recipe = selectedRecipe,
              let bottleID = selectedBottleID,
              let bottle = appState.bottles.first(where: { $0.id == bottleID }) else {
            return
        }
        Task {
            await appState.applyRecipe(recipe, to: bottle)
            dismiss()
        }
    }
}

