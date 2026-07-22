import SwiftUI

struct MealPrepSelectionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introCard

                SectionHeader(
                    title: "Saved recipes",
                    subtitle: "Choose 1–5 reviewed recipes. Each keeps its own serving count."
                )

                ForEach(appModel.savedRecipes) { recipe in
                    recipeCard(recipe)
                }

                ForEach(appModel.mealPrepSelectedUnsavedRecipes) { recipe in
                    recipeCard(recipe)
                }

                continueButton
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .smartCartBackground()
        .navigationTitle("Weekly Meal Prep")
        .navigationBarTitleDisplayMode(.inline)
        .domainUndoOverlay()
    }

    private var selectionCount: Int { appModel.mealPrepDraft?.selections.count ?? 0 }

    private var introCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2.bold())
                        .foregroundStyle(SmartCartTheme.green)
                    introIdentity
                    Text("\(selectionCount) of 5 selected")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(selectionCount == 5 ? SmartCartTheme.amber : SmartCartTheme.green)
                }
            } else {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2.bold())
                        .foregroundStyle(SmartCartTheme.green)
                    introIdentity
                    Spacer()
                    Text("\(selectionCount)/5")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(selectionCount == 5 ? SmartCartTheme.amber : SmartCartTheme.green)
                }
            }
        }
        .smartCartCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meal Prep selection, \(selectionCount) of 5 recipes selected")
    }

    private var introIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Plan your week. Shop once.")
                .font(.title3.bold())
                .foregroundStyle(SmartCartTheme.navy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pantry stock is applied after ingredients are safely combined.")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recipeCard(_ recipe: Recipe) -> some View {
        let selected = appModel.isRecipeSelectedForMealPrep(recipe.id)
        let selection = appModel.mealPrepDraft?.selections.first { $0.recipeSnapshot.id == recipe.id }

        return VStack(spacing: 12) {
            Button {
                appModel.toggleMealPrepRecipe(recipe)
            } label: {
                recipeSelectionLabel(recipe, selected: selected)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!selected && selectionCount >= MealPrepDraft.selectionLimit)
            .accessibilityLabel("\(recipe.title), \(selected ? "selected" : "not selected")")
            .accessibilityHint(selected ? "Double tap to remove from Meal Prep" : "Double tap to add to Meal Prep")

            if let selection {
                Divider()
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target servings")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                        HStack {
                            servingControls(recipe: recipe, selection: selection)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack {
                        Text("Target servings")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                        Spacer()
                        servingControls(recipe: recipe, selection: selection)
                    }
                }
            }
        }
        .smartCartCard(padding: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selected ? SmartCartTheme.green : Color.clear, lineWidth: 2)
        }
    }

    @ViewBuilder
    private func servingControls(recipe: Recipe, selection: MealPrepSelection) -> some View {
        servingButton(symbol: "minus", recipeTitle: recipe.title, selectionID: selection.id, delta: -1)
        Text(Int(selection.targetServings), format: .number)
            .font(.headline.monospacedDigit())
            .foregroundStyle(SmartCartTheme.navy)
            .frame(minWidth: 36)
            .accessibilityLabel("\(Int(selection.targetServings)) servings")
        servingButton(symbol: "plus", recipeTitle: recipe.title, selectionID: selection.id, delta: 1)
    }

    @ViewBuilder
    private func recipeSelectionLabel(_ recipe: Recipe, selected: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    selectionMark(selected)
                    recipeIcon(recipe)
                    Spacer()
                }
                recipeIdentity(recipe)
            }
        } else {
            HStack(spacing: 12) {
                selectionMark(selected)
                recipeIcon(recipe)
                recipeIdentity(recipe)
                Spacer()
            }
        }
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3.bold())
            .foregroundStyle(selected ? SmartCartTheme.green : SmartCartTheme.secondaryInk)
    }

    private func recipeIcon(_ recipe: Recipe) -> some View {
        Image(systemName: recipe.heroSymbol)
            .foregroundStyle(SmartCartTheme.green)
            .frame(width: 44, height: 44)
            .background(SmartCartTheme.herbLight)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func recipeIdentity(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recipe.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SmartCartTheme.navy)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(recipe.ingredients.count) ingredients · makes \(recipe.servings)")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func servingButton(symbol: String, recipeTitle: String, selectionID: UUID, delta: Double) -> some View {
        Button {
            appModel.updateMealPrepServings(selectionID: selectionID, delta: delta)
        } label: {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 44, height: 44)
                .background(SmartCartTheme.herbLight)
                .clipShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(delta > 0 ? "Increase servings for \(recipeTitle)" : "Decrease servings for \(recipeTitle)")
    }

    private var continueButton: some View {
        Button {
            _ = appModel.buildMealPrepPlan()
        } label: {
            Label("Combine ingredients", systemImage: "arrow.triangle.merge")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(SmartCartTheme.green)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(selectionCount == 0)
        .opacity(selectionCount == 0 ? 0.45 : 1)
        .accessibilityHint("Builds one pantry-aware ingredient plan")
    }
}
