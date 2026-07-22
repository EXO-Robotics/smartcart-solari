import SwiftUI

struct WeeklyMealDetailView: View {
    @Environment(AppModel.self) private var appModel
    @State private var servings: Int
    @State private var includedOptionalIngredientIDs: Set<String> = []

    let recipeID: CuratedRecipeID
    private let collectionID: String?
    private let meal: ResolvedWeeklyMeal?

    init(recipeID: CuratedRecipeID) {
        self.recipeID = recipeID
        let collection = try? BundledWeeklyMealRepository().activeCollection(
            on: Date(),
            calendar: Calendar.autoupdatingCurrent
        )
        collectionID = collection?.id
        meal = collection?.meals.first { $0.recipe.id == recipeID }
        _servings = State(initialValue: meal?.recipe.defaultServings ?? 1)
    }

    var body: some View {
        Group {
            if let meal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero(meal)
                        servingCard(meal.recipe)
                        nutritionCard(meal.recipe)
                        ingredientsCard(meal.recipe)
                        instructionsCard(meal.recipe)
                        costCard(meal.recipe)
                    }
                    .padding(18)
                    .padding(.bottom, 92)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) {
                    BottomActionBar {
                        Button("Shop This Meal") {
                            shop(meal.recipe)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("weekly-meal-detail-shop")
                        .accessibilityHint("Creates a frozen recipe and opens Recipe Ready")
                    }
                }
            } else {
                ContentUnavailableView(
                    "Meal unavailable",
                    systemImage: "fork.knife",
                    description: Text("This bundled meal could not be loaded.")
                )
            }
        }
        .smartCartBackground()
        .navigationTitle("Weekly Meal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ meal: ResolvedWeeklyMeal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(meal.entry.slot.displayName, systemImage: meal.entry.slot.symbolName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SmartCartTheme.green)
            Text(meal.recipe.title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.ink)
            Text(meal.recipe.shortDescription)
                .font(.body)
                .foregroundStyle(SmartCartTheme.secondaryInk)
            HStack(spacing: 12) {
                Label("\(meal.recipe.metadata.prepMinutes + meal.recipe.metadata.cookMinutes) min", systemImage: "clock")
                Label("Serves \(servings)", systemImage: "person.2")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .smartCartCard()
        .smartCartShadow()
    }

    private func servingCard(_ recipe: CuratedRecipeRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose servings")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.ink)
            HStack {
                Button { servings = max(1, servings - 1) } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(servings == 1)
                .accessibilityLabel("Decrease servings")

                Spacer()
                VStack(spacing: 2) {
                    Text(servings, format: .number)
                        .font(.title2.bold())
                    Text(recipe.servingDescription)
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                Spacer()

                Button { servings = min(48, servings + 1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(servings == 48)
                .accessibilityLabel("Increase servings")
            }
        }
        .smartCartCard()
    }

    @ViewBuilder
    private func nutritionCard(_ recipe: CuratedRecipeRecord) -> some View {
        if let nutrition = recipe.metadata.nutrition {
            VStack(alignment: .leading, spacing: 9) {
                Text("Estimated nutrition")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.ink)
                Text("Est. \(nutrition.caloriesPerServing) cal · Est. \(nutrition.proteinGramsPerServing.formatted()) g protein")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.green)
                Text("Per \(nutrition.servingDefinition). Changing servings changes total recipe nutrition, not the per-serving estimate.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                Text("Nutrition is estimated and may vary by ingredient brand, portioning, and substitutions.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.mutedInk)
            }
            .smartCartCard()
        }
    }

    private func ingredientsCard(_ recipe: CuratedRecipeRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.ink)
            ForEach(recipe.ingredients) { ingredient in
                if ingredient.optionalPolicy == .excludedByDefault {
                    Toggle(
                        scaledIngredientText(ingredient, recipe: recipe),
                        isOn: Binding(
                            get: { includedOptionalIngredientIDs.contains(ingredient.id) },
                            set: { included in
                                if included {
                                    includedOptionalIngredientIDs.insert(ingredient.id)
                                } else {
                                    includedOptionalIngredientIDs.remove(ingredient.id)
                                }
                            }
                        )
                    )
                    .tint(SmartCartTheme.green)
                    .accessibilityHint("Optional ingredient")
                } else {
                    Text("• \(scaledIngredientText(ingredient, recipe: recipe))")
                        .font(.subheadline)
                        .foregroundStyle(SmartCartTheme.ink)
                }
            }
        }
        .smartCartCard()
    }

    private func instructionsCard(_ recipe: CuratedRecipeRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Instructions")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.ink)
            ForEach(recipe.instructions) { instruction in
                HStack(alignment: .top, spacing: 11) {
                    Text(instruction.id, format: .number)
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(SmartCartTheme.green, in: Circle())
                    Text(instruction.text)
                        .font(.subheadline)
                        .foregroundStyle(SmartCartTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .smartCartCard()
    }

    @ViewBuilder
    private func costCard(_ recipe: CuratedRecipeRecord) -> some View {
        if let estimate = recipe.metadata.costEstimate,
           let cost = WeeklyMealCostFormatter.string(for: estimate) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Estimated recipe cost")
                    .font(.headline)
                Text(cost)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                Text("This is the proportional estimated value of ingredients used, not the packages you may need to purchase.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                Text("Cost is estimated from representative ingredient prices. Retailer, location, brand, package size, taxes, and substitutions may change the final amount.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.mutedInk)
            }
            .smartCartCard()
        }
#if DEBUG
        if recipe.metadata.costEstimate?.status == .requiresVerification {
            VStack(alignment: .leading, spacing: 6) {
                Text("Estimated recipe cost")
                    .font(.headline)
                Text("Cost estimate pending")
                    .foregroundStyle(SmartCartTheme.mutedInk)
                Text("Checkout cost remains separate and is calculated later from packages still needed after pantry allocation and retailer matching.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
            .smartCartCard()
        }
#endif
    }

    private func scaledIngredientText(
        _ ingredient: CuratedIngredient,
        recipe: CuratedRecipeRecord
    ) -> String {
        guard !ingredient.isQualitative, let quantity = ingredient.quantity else {
            return ingredient.rawText
        }
        let scaled = quantity * Decimal(servings) / Decimal(recipe.defaultServings)
        let quantityText = scaled.formatted(.number.precision(.fractionLength(0...2)))
        let unit = ingredient.unit.isEmpty ? "" : " \(ingredient.unit)"
        let preparation = ingredient.preparation.isEmpty ? "" : ", \(ingredient.preparation)"
        return "\(quantityText)\(unit) \(ingredient.name)\(preparation)"
    }

    private func shop(_ recipe: CuratedRecipeRecord) {
        guard let collectionID,
              let snapshot = try? WeeklyMealSnapshotFactory().makeSnapshot(
                collectionID: collectionID,
                recipe: recipe,
                targetServings: servings,
                includedOptionalIngredientIDs: includedOptionalIngredientIDs
              ) else {
            appModel.showToast("This meal could not be prepared")
            return
        }
        _ = appModel.beginRecipe(snapshot)
    }
}
