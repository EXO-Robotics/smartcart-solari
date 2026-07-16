import SwiftUI

struct IngredientReviewView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 1,
                    total: 5,
                    eyebrow: "Ingredient review",
                    title: "Check what SmartCart found",
                    message: "Correct names and quantities now. Nothing is matched to a product until you confirm this list."
                )

                recipeSummary
                confidenceLegend

                VStack(spacing: 11) {
                    ForEach($appModel.activeRecipe.ingredients) { $ingredient in
                        IngredientReviewRow(ingredient: $ingredient)
                    }
                }

                Button {
                    appModel.activeRecipe.ingredients.append(
                        Ingredient(name: "New ingredient", confidence: .review)
                    )
                } label: {
                    Label("Add an ingredient", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(GatherTheme.canvas)
        .navigationTitle("Review ingredients")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.continueTo(.servingAdjustment)
                } label: {
                    ViewThatFits {
                        HStack {
                            Text("Continue with \(appModel.includedIngredientCount) ingredients")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        HStack {
                            Text("Continue")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appModel.includedIngredientCount == 0)
            }
        }
    }

    private var recipeSummary: some View {
        HStack(spacing: 14) {
            Image(systemName: appModel.activeRecipe.heroSymbol)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(GatherTheme.green)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(appModel.activeRecipe.title)
                    .font(.headline)
                    .foregroundStyle(GatherTheme.navy)
                    .lineLimit(2)
                Text("\(appModel.activeRecipe.source.rawValue) · \(appModel.activeRecipe.ingredients.count) ingredients detected")
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }

            Spacer(minLength: 0)
        }
        .gatherCard(padding: 14)
    }

    private var confidenceLegend: some View {
        HStack(spacing: 8) {
            IngredientConfidenceBadge(confidence: .high)
            IngredientConfidenceBadge(confidence: .review)
            Spacer(minLength: 0)
        }
    }
}

private struct IngredientReviewRow: View {
    @Binding var ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Toggle("", isOn: $ingredient.includeInList)
                    .labelsHidden()
                    .tint(GatherTheme.green)

                Image(systemName: ingredient.category.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(ingredient.includeInList ? GatherTheme.green : GatherTheme.secondaryInk)
                    .frame(width: 37, height: 37)
                    .background(ingredient.includeInList ? GatherTheme.herbLight : GatherTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Ingredient name", text: $ingredient.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GatherTheme.navy)
                        .textInputAutocapitalization(.words)

                    Menu {
                        ForEach(IngredientConfidence.allCases) { confidence in
                            Button {
                                ingredient.confidence = confidence
                            } label: {
                                Label(confidence.rawValue, systemImage: confidence.symbol)
                            }
                        }
                    } label: {
                        IngredientConfidenceBadge(confidence: ingredient.confidence)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField("Qty", value: $ingredient.quantity, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .frame(width: 66)
                    .smartField()

                TextField("Unit", text: $ingredient.unit)
                    .textInputAutocapitalization(.never)
                    .frame(width: 88)
                    .smartField()

                TextField("Preparation (optional)", text: $ingredient.preparation)
                    .smartField()
            }
            .font(.caption)

            HStack {
                Menu {
                    ForEach(GroceryCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) {
                            ingredient.category = category
                        }
                    }
                } label: {
                    Label(ingredient.category.rawValue, systemImage: "square.grid.2x2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                }

                Spacer()

                Button {
                    ingredient.pantryState = ingredient.pantryState == .haveEnough ? .needToBuy : .haveEnough
                } label: {
                    Label(
                        ingredient.pantryState == .haveEnough ? "Already have" : "Need this",
                        systemImage: ingredient.pantryState == .haveEnough ? "checkmark.seal.fill" : "cart.badge.plus"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ingredient.pantryState == .haveEnough ? GatherTheme.green : GatherTheme.walmartBlue)
                }
            }
        }
        .padding(13)
        .background(ingredient.includeInList ? GatherTheme.paper : GatherTheme.canvas.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
        }
        .opacity(ingredient.includeInList ? 1 : 0.62)
    }
}

struct ServingAdjustmentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var preferLeftovers = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 2,
                    total: 5,
                    eyebrow: "Adjust servings",
                    title: "How many people are eating?",
                    message: "SmartCart scales the recipe first, then estimates the packages you may need to buy."
                )

                servingControl
                packageExplanation
                quantityPreview
                leftoversToggle
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(GatherTheme.canvas)
        .navigationTitle("Adjust servings")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.continueTo(.pantryCheck)
                } label: {
                    HStack {
                        Text("Check my pantry")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var servingControl: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Desired servings")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GatherTheme.navy)
                    Text("Original recipe: \(appModel.activeRecipe.servings)")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }

                Spacer()

                HStack(spacing: 16) {
                    servingButton(symbol: "minus", delta: -1)
                    Text("\(appModel.desiredServings)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(GatherTheme.navy)
                        .frame(minWidth: 42)
                    servingButton(symbol: "plus", delta: 1)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(GatherTheme.border)
                    Capsule()
                        .fill(GatherTheme.green)
                        .frame(width: proxy.size.width * min(CGFloat(appModel.desiredServings) / 12, 1))
                }
            }
            .frame(height: 6)
        }
        .gatherCard()
    }

    private func servingButton(symbol: String, delta: Int) -> some View {
        Button {
            appModel.updateServings(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(GatherTheme.green)
                .frame(width: 42, height: 42)
                .background(GatherTheme.herbLight)
                .clipShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(delta > 0 ? "Increase servings" : "Decrease servings")
    }

    private var packageExplanation: some View {
        InfoBanner(
            symbol: "shippingbox.fill",
            title: "Recipe amount ≠ package amount",
            message: "If the recipe needs 1.5 lb of chicken and the best product is a 3 lb pack, SmartCart shows the extra so you can choose.",
            color: GatherTheme.walmartBlue
        )
    }

    private var quantityPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ingredient")
                Spacer()
                Text("Recipe")
                    .frame(width: 74, alignment: .trailing)
                Text("Buy")
                    .frame(width: 62, alignment: .trailing)
            }
            .font(.caption2.weight(.heavy))
            .foregroundStyle(GatherTheme.secondaryInk)
            .padding(.bottom, 10)

            ForEach(appModel.activeRecipe.ingredients.filter(\.includeInList).prefix(7)) { ingredient in
                HStack(spacing: 8) {
                    Text(ingredient.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GatherTheme.navy)
                        .lineLimit(1)
                    Spacer()
                    Text(appModel.scaledQuantityText(for: ingredient))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                        .frame(width: 74, alignment: .trailing)
                    Text("1 pkg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GatherTheme.green)
                        .frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, 10)

                if ingredient.id != appModel.activeRecipe.ingredients.filter(\.includeInList).prefix(7).last?.id {
                    Divider()
                }
            }
        }
        .gatherCard()
    }

    private var leftoversToggle: some View {
        Toggle(isOn: $preferLeftovers) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Prefer useful leftovers")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GatherTheme.navy)
                Text("Favor the next package size up when the price difference is small.")
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }
        }
        .tint(GatherTheme.green)
        .gatherCard()
    }
}

struct ListsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shopping lists")
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .foregroundStyle(GatherTheme.navy)
                        Text("Ready to share, open, or shop")
                            .font(.subheadline)
                            .foregroundStyle(GatherTheme.secondaryInk)
                    }
                    Spacer()
                    SmartCartLogo(compact: true)
                        .accessibilityHidden(true)
                }
                .padding(.top, 8)

                if appModel.shoppingItems.isEmpty {
                    EmptyStateView(
                        symbol: "checklist",
                        title: "No list yet",
                        message: "Import a recipe and SmartCart will build your first product-matched list.",
                        actionTitle: "Import recipe"
                    ) {
                        appModel.selectedTab = .home
                        appModel.openImporter(.sample)
                    }
                } else {
                    currentListCard
                }

                savedSection
                transparencyCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .background(GatherTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var currentListCard: some View {
        Button {
            appModel.selectedTab = .home
            appModel.homePath = [.shoppingList]
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    StatusPill(title: "Current list", symbol: "checkmark.circle.fill")
                    Spacer()
                    Text(appModel.estimatedTotal, format: .currency(code: "USD"))
                        .font(.title3.bold())
                        .foregroundStyle(GatherTheme.navy)
                }

                HStack(spacing: 14) {
                    Image(systemName: appModel.activeRecipe.heroSymbol)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(GatherTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appModel.activeRecipe.title)
                            .font(.title3.bold())
                            .foregroundStyle(GatherTheme.navy)
                            .lineLimit(2)
                        Text("\(appModel.shoppingItems.count) products · \(appModel.primaryStore.name)")
                            .font(.caption)
                            .foregroundStyle(GatherTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack {
                    Label("\(appModel.matchedItemCount) best matches", systemImage: "tag.fill")
                    Spacer()
                    Label("Open list", systemImage: "arrow.right")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(GatherTheme.green)
            }
            .gatherCard()
            .gatherShadow()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Saved lists", subtitle: "Lists you can revisit")

            if appModel.savedLists.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(GatherTheme.walmartBlue)
                        .frame(width: 40, height: 40)
                        .background(GatherTheme.walmartLight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Save the current list to keep its products, quantities, and estimated total here.")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
                .gatherCard(padding: 14)
            } else {
                ForEach(appModel.savedLists) { list in
                    HStack(spacing: 12) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(GatherTheme.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(list.recipeTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(GatherTheme.navy)
                            Text("\(list.itemCount) items · \(list.storeName)")
                                .font(.caption)
                                .foregroundStyle(GatherTheme.secondaryInk)
                        }
                        Spacer()
                        Text(list.total, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GatherTheme.navy)
                    }
                    .gatherCard(padding: 14)
                }
            }
        }
    }

    private var transparencyCard: some View {
        InfoBanner(
            symbol: "clock.badge.exclamationmark.fill",
            title: "Estimated totals stay transparent",
            message: "Retailer prices and availability can change. Walmart confirms taxes, fees, substitutions, tips, and final variable-weight prices.",
            color: GatherTheme.amber
        )
    }
}
