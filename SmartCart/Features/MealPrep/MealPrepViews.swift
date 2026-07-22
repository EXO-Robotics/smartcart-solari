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

struct MealPrepDashboardView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                metrics
                pantrySummary
                sourceRecipes
                actions
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .smartCartBackground()
        .navigationTitle("Recipe Ready")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var plan: MealPrepPlanSnapshot? { appModel.currentMealPrepPlan }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SHOPPING SCOPE", systemImage: "calendar.badge.checkmark")
                .font(.caption2.weight(.black))
                .foregroundStyle(SmartCartTheme.green)
            Text(plan?.title ?? "Weekly Meal Prep")
                .font(.title.bold())
                .foregroundStyle(SmartCartTheme.navy)
            Text("One pantry-aware trip built from reviewed saved recipes.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .smartCartCard()
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { metricItems }
            VStack(spacing: 10) { metricItems }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metricItems: some View {
        metric(plan?.recipeCount ?? 0, "recipes")
        metric(plan?.ingredientCount ?? 0, "combined")
        metric(plan?.purchaseCount ?? 0, "to buy")
    }

    private func metric(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value, format: .number).font(.title3.bold()).foregroundStyle(SmartCartTheme.navy)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .smartCartCard(padding: 12)
    }

    private var pantrySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            InfoBanner(
                symbol: "cabinet.fill",
                title: "Pantry applied once",
                message: "\(plan?.pantryCoveredCount ?? 0) combined ingredient lines are fully or partially covered. You always control whether to use pantry stock or buy the full amount.",
                color: SmartCartTheme.green
            )
            ForEach(plan?.lines.filter(\.hasPantryChoice) ?? []) { line in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name).font(.subheadline.weight(.bold)).foregroundStyle(SmartCartTheme.navy)
                            Text(pantryCoverageText(for: line))
                                .font(.caption2).foregroundStyle(SmartCartTheme.secondaryInk)
                        }
                        Spacer()
                        Text("Buy \(quantity(line.quantityToBuy, unit: line.unit.symbol))")
                            .font(.caption.weight(.bold)).foregroundStyle(SmartCartTheme.green)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            pantryChoice("Use Pantry", selected: !line.isBuyingFullQuantity) {
                                appModel.setMealPrepPantryOverride(lineID: line.id, buyFull: false)
                            }
                            pantryChoice("Buy Full", selected: line.isBuyingFullQuantity) {
                                appModel.setMealPrepPantryOverride(lineID: line.id, buyFull: true)
                            }
                        }
                        VStack(spacing: 8) {
                            pantryChoice("Use Pantry", selected: !line.isBuyingFullQuantity) {
                                appModel.setMealPrepPantryOverride(lineID: line.id, buyFull: false)
                            }
                            pantryChoice("Buy Full", selected: line.isBuyingFullQuantity) {
                                appModel.setMealPrepPantryOverride(lineID: line.id, buyFull: true)
                            }
                        }
                    }
                }
                .smartCartCard(padding: 13)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func pantryCoverageText(for line: CombinedIngredientLine) -> String {
        let needed = quantity(line.quantity, unit: line.unit.symbol)
        guard !line.pantryDeductions.isEmpty else {
            return "Need \(needed) · Pantry match available"
        }
        let applied = line.pantryDeductions.reduce(0) { $0 + $1.quantity }
        return "Need \(needed) · Pantry \(quantity(applied, unit: line.unit.symbol))"
    }

    private func pantryChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? SmartCartTheme.onAccent : SmartCartTheme.green)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SmartCartTheme.minimumHitTargetDimension
                )
                .background(selected ? SmartCartTheme.green : SmartCartTheme.herbLight)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .smartCartMinimumHitTarget()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private var sourceRecipes: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recipes in this trip", subtitle: "Frozen snapshots protect active and historical trips")
            ForEach(plan?.selections ?? []) { selection in
                HStack {
                    Image(systemName: "book.closed.fill").foregroundStyle(SmartCartTheme.green)
                    Text(selection.recipeSnapshot.title).font(.subheadline.weight(.semibold)).foregroundStyle(SmartCartTheme.navy)
                    Spacer()
                    Text("\(Int(selection.targetServings)) servings").font(.caption.weight(.bold)).foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .smartCartCard(padding: 13)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                appModel.homePath.removeLast()
            } label: {
                Label("Edit recipes and servings", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SmartCartTheme.herbLight)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                appModel.beginMealPrepShopping()
            } label: {
                Label("Choose where to shop", systemImage: "storefront.fill")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled((plan?.purchaseCount ?? 0) == 0)
            .opacity((plan?.purchaseCount ?? 0) == 0 ? 0.45 : 1)
            .accessibilityHint("Continues to the existing retailer selection and Retailer Assistant")
        }
    }

    private func quantity(_ value: Double, unit: String) -> String {
        Ingredient.quantityText(value, unit: unit == "count" ? "" : unit)
    }
}
