import SwiftUI
import UIKit

struct IngredientReviewView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 1,
                    total: 6,
                    eyebrow: "Ingredient review",
                    title: "Check what SmartCart found",
                    message: "Correct names and quantities now. Nothing is matched to a product until you confirm this list."
                )

                recipeSummary
                confidenceLegend

                LazyVStack(spacing: 11) {
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
        .smartCartBackground()
        .navigationTitle("Review ingredients")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.commitIngredientReview()
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
                .disabled(appModel.includedIngredientCount == 0 || appModel.unresolvedQuantityReviewCount > 0)
            }
        }
    }

    private var recipeSummary: some View {
        HStack(spacing: 14) {
            Image(systemName: appModel.activeRecipe.heroSymbol)
                .font(.title2.bold())
                .foregroundStyle(SmartCartTheme.onAccent)
                .frame(width: 56, height: 56)
                .background(SmartCartTheme.green)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: SmartCartTheme.mintGlow, radius: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(appModel.activeRecipe.title)
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                    .lineLimit(2)
                Text("\(appModel.activeRecipe.source.rawValue) · \(appModel.activeRecipe.ingredients.count) ingredients detected")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            Spacer(minLength: 0)
        }
        .smartCartCard(padding: 14)
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
    @State private var showSourceEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Toggle("Include \(ingredient.name)", isOn: $ingredient.includeInList)
                    .labelsHidden()
                    .tint(SmartCartTheme.green)
                    .accessibilityLabel("Include \(ingredient.name) in this shopping trip")
                    .accessibilityValue(ingredient.includeInList ? "Included" : "Excluded")

                Image(systemName: ingredient.category.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(ingredient.includeInList ? SmartCartTheme.green : SmartCartTheme.secondaryInk)
                    .frame(width: 37, height: 37)
                    .background(ingredient.includeInList ? SmartCartTheme.herbLight : SmartCartTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Ingredient name", text: $ingredient.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
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

            if let suggestion = ingredient.pantrySuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Label(pantrySuggestionTitle(suggestion), systemImage: "cabinet.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.purple)
                    Text(pantrySuggestionMessage(suggestion))
                        .font(.caption2)
                        .foregroundStyle(SmartCartTheme.secondaryInk)

                    HStack(spacing: 8) {
                        Button(suggestion.coverage == .partial ? "Use it + buy rest" : "Use pantry") {
                            ingredient.pantryDecision = .useAvailable
                            ingredient.pantryState = .runningLow
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SmartCartTheme.green)
                        .foregroundStyle(SmartCartTheme.onAccent)

                        Button("Buy full amount") {
                            ingredient.pantryDecision = .buyFull
                            ingredient.pantryState = .needToBuy
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.bold))
                }
                .padding(11)
                .background(SmartCartTheme.purple.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(SmartCartTheme.purple.opacity(0.22), lineWidth: 1)
                }
            }

            if ingredient.quantityReviewRequired == true {
                HStack {
                    Label("Quantity is uncertain. Confirm it before product matching.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.coral)
                    Spacer()
                    Button("Confirm \(ingredient.displayQuantity)") {
                        ingredient.quantityReviewRequired = false
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                }
            }

            if let evidence = ingredient.sourceEvidence {
                DisclosureGroup(isExpanded: $showSourceEvidence) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let cropData = evidence.sourceCropJPEGData,
                           let crop = UIImage(data: cropData) {
                            Image(uiImage: crop)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 120)
                                .background(SmartCartTheme.canvasRaise)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(SmartCartTheme.border, lineWidth: 1)
                                }
                                .accessibilityLabel("Source crop for \(ingredient.name)")
                        }
                        Text(evidence.rawText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Text("\(evidence.extractionStrategy.rawValue) · parser \(evidence.parserConfidence.formatted(.percent.precision(.fractionLength(0)))) · normalization \(evidence.normalizationConfidence.formatted(.percent.precision(.fractionLength(0))))")
                            .font(.caption2)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                        if let layout = evidence.layoutConfidence {
                            Text("Layout confidence: \(layout.formatted(.percent.precision(.fractionLength(0))))")
                                .font(.caption2)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                        }
                        if let pageIndex = evidence.pageIndex,
                           let box = evidence.boundingBox {
                            Text(
                                "Page \(pageIndex + 1) · source box x \(box.x.formatted(.percent.precision(.fractionLength(0)))), y \(box.y.formatted(.percent.precision(.fractionLength(0))))"
                            )
                            .font(.caption2)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                        }
                        if let alternatives = evidence.alternateSourceTexts,
                           !alternatives.isEmpty {
                            Text("OCR alternatives")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(SmartCartTheme.amber)
                            ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alternative in
                                Text(alternative)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(SmartCartTheme.secondaryInk)
                            }
                        }
                        if evidence.alternateQuantityCandidates.count > 1 {
                            Text(
                                "Quantity candidates: \(evidence.alternateQuantityCandidates.map { $0.formatted(.number.precision(.fractionLength(0...2))) }.joined(separator: " · "))"
                            )
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(SmartCartTheme.coral)
                        }
                    }
                    .padding(.top, 7)
                } label: {
                    Label("Source evidence", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.walmartBlue)
                }
            }

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
                        .foregroundStyle(SmartCartTheme.secondaryInk)
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
                    .foregroundStyle(ingredient.pantryState == .haveEnough ? SmartCartTheme.green : SmartCartTheme.walmartBlue)
                }
            }
        }
        .padding(13)
        .background(ingredient.includeInList ? SmartCartTheme.paper : SmartCartTheme.canvas.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(SmartCartTheme.border, lineWidth: 1)
        }
        .opacity(ingredient.includeInList ? 1 : 0.62)
    }

    private func pantrySuggestionTitle(_ suggestion: PantrySuggestion) -> String {
        switch suggestion.coverage {
        case .full: "Pantry may cover this"
        case .partial: "Pantry may cover part of this"
        case .possible: "Possible pantry match"
        }
    }

    private func pantrySuggestionMessage(_ suggestion: PantrySuggestion) -> String {
        switch suggestion.coverage {
        case .full:
            "\(suggestion.pantryItemName) appears to cover \(ingredient.displayQuantity). Confirm before SmartCart skips it."
        case .partial:
            "\(suggestion.pantryItemName) covers about \(Ingredient.quantityText(suggestion.availableQuantity, unit: suggestion.availableUnit)); SmartCart can buy the remainder."
        case .possible:
            "\(suggestion.pantryItemName) matches by name, but its saved package unit cannot be compared with \(ingredient.unit.isEmpty ? "this recipe amount" : ingredient.unit)."
        }
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
                    total: 6,
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
        .smartCartBackground()
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
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Original recipe: \(appModel.activeRecipe.servings)")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }

                Spacer()

                HStack(spacing: 16) {
                    servingButton(symbol: "minus", delta: -1)
                    Text("\(appModel.desiredServings)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                        .frame(minWidth: 42)
                    servingButton(symbol: "plus", delta: 1)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SmartCartTheme.border)
                    Capsule()
                        .fill(SmartCartTheme.green)
                        .frame(width: proxy.size.width * min(CGFloat(appModel.desiredServings) / 12, 1))
                }
            }
            .frame(height: 6)
        }
        .smartCartCard()
    }

    private func servingButton(symbol: String, delta: Int) -> some View {
        Button {
            appModel.updateServings(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 42, height: 42)
                .background(SmartCartTheme.herbLight)
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
            color: SmartCartTheme.walmartBlue
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
            .foregroundStyle(SmartCartTheme.secondaryInk)
            .padding(.bottom, 10)

            ForEach(appModel.activeRecipe.ingredients.filter(\.includeInList).prefix(7)) { ingredient in
                HStack(spacing: 8) {
                    Text(ingredient.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.navy)
                        .lineLimit(1)
                    Spacer()
                    Text(appModel.scaledQuantityText(for: ingredient))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .frame(width: 74, alignment: .trailing)
                    Text("1 pkg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.green)
                        .frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, 10)

                if ingredient.id != appModel.activeRecipe.ingredients.filter(\.includeInList).prefix(7).last?.id {
                    Divider()
                }
            }
        }
        .smartCartCard()
    }

    private var leftoversToggle: some View {
        Toggle(isOn: $preferLeftovers) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Prefer useful leftovers")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Favor the next package size up when the price difference is small.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .tint(SmartCartTheme.green)
        .smartCartCard()
    }
}

struct RecipesView: View {
    @Environment(AppModel.self) private var appModel
    @State private var page: RecipesPage =
        ProcessInfo.processInfo.environment["SMARTCART_RECIPES_PAGE"] == "recent" ? .recent : .saved

    private enum RecipesPage: Int, CaseIterable {
        case saved
        case recent

        var title: String {
            switch self {
            case .saved: "Saved"
            case .recent: "Recent"
            }
        }

        var symbol: String {
            switch self {
            case .saved: "bookmark.fill"
            case .recent: "clock.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)

            TabView(selection: $page) {
                savedPage
                    .tag(RecipesPage.saved)
                recentPage
                    .tag(RecipesPage.recent)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recipes")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Saved lists and recent imports")
                        .font(.subheadline)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                Spacer()
                SmartCartLogo(compact: true)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 4) {
                ForEach(RecipesPage.allCases, id: \.rawValue) { candidate in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            page = candidate
                        }
                    } label: {
                        Label(candidate.title, systemImage: candidate.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(page == candidate ? SmartCartTheme.onAccent : SmartCartTheme.secondaryInk)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background {
                                if page == candidate {
                                    Capsule().fill(SmartCartTheme.green)
                                }
                            }
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(4)
            .background(SmartCartTheme.paper)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(SmartCartTheme.border, lineWidth: 1) }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var savedPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                mealPrepLaunchCard

                if appModel.shoppingItems.isEmpty {
                    EmptyStateView(
                        symbol: "book.fill",
                        title: "No recipe in progress",
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
        .scrollIndicators(.hidden)
    }

    private var mealPrepLaunchCard: some View {
        Button {
            appModel.startMealPrepDraft()
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 54, height: 54)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Meal Prep Mode")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Select up to five saved recipes and build one pantry-aware shopping trip.")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(SmartCartTheme.green)
            }
            .smartCartCard()
            .smartCartShadow()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Meal Prep Mode")
        .accessibilityHint("Select up to five saved recipes and shop once")
    }

    private var recentPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Recently shopped",
                    subtitle: "Your last \(min(5, max(1, appModel.recentRecipes.count))) recipes, newest first"
                )

                if appModel.recentRecipes.isEmpty {
                    EmptyStateView(
                        symbol: "clock.fill",
                        title: "Nothing recent yet",
                        message: "Recipes you import or shop show up here so you can run them again in one tap."
                    )
                } else {
                    ForEach(appModel.recentRecipes.prefix(5)) { recipe in
                        recentRecipeCard(recipe)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
    }

    private func recentRecipeCard(_ recipe: Recipe) -> some View {
        HStack(spacing: 13) {
            Image(systemName: recipe.heroSymbol)
                .font(.title3.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 48, height: 48)
                .background(SmartCartTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                    .lineLimit(2)
                Text("\(recipe.ingredients.count) ingredients · \(recipe.servings) servings · \(recipe.source.rawValue)")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                appModel.beginRecipe(recipe)
            } label: {
                Label("Shop", systemImage: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(SmartCartTheme.green)
                    .clipShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Shop \(recipe.title) again")
        }
        .smartCartCard(padding: 13)
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(appModel.estimatedTotal, format: .currency(code: "USD"))
                            .font(.title3.bold())
                            .foregroundStyle(SmartCartTheme.navy)
                        Text("Demo subtotal · not live")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SmartCartTheme.amber)
                    }
                }

                HStack(spacing: 14) {
                    Image(systemName: appModel.isMealPrepShopping ? "calendar.badge.checkmark" : appModel.activeRecipe.heroSymbol)
                        .font(.title.bold())
                        .foregroundStyle(SmartCartTheme.onAccent)
                        .frame(width: 62, height: 62)
                        .background(SmartCartTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .shadow(color: SmartCartTheme.mintGlow, radius: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appModel.currentShoppingTitle)
                            .font(.title3.bold())
                            .foregroundStyle(SmartCartTheme.navy)
                            .lineLimit(2)
                        Text("\(appModel.shoppingItems.count) products · \(appModel.primaryStore.name)")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
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
                .foregroundStyle(SmartCartTheme.green)
            }
            .smartCartCard()
            .smartCartShadow()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Saved lists", subtitle: "Lists you can revisit")

            if appModel.savedLists.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(SmartCartTheme.walmartBlue)
                        .frame(width: 40, height: 40)
                        .background(SmartCartTheme.walmartLight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Save the current manifest to keep its products, quantities, observed-price subtotal, and handoff progress here.")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .smartCartCard(padding: 14)
            } else {
                ForEach(appModel.savedLists) { list in
                    Button {
                        appModel.openSavedList(list.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(SmartCartTheme.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(list.recipeTitle)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SmartCartTheme.navy)
                                Text("\(list.itemCount) items · \(list.storeName)")
                                    .font(.caption)
                                    .foregroundStyle(SmartCartTheme.secondaryInk)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(list.total, format: .currency(code: "USD"))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SmartCartTheme.navy)
                                Text("Demo · not live")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(SmartCartTheme.amber)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(SmartCartTheme.green)
                        }
                        .smartCartCard(padding: 14)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("saved-list-\(list.id.uuidString)")
                }
            }
        }
    }

    private var transparencyCard: some View {
        InfoBanner(
            symbol: "clock.badge.exclamationmark.fill",
            title: "Estimated totals stay transparent",
            message: "Retailer prices and availability can change. \(appModel.retailerConfiguration.displayName) confirms taxes, fees, substitutions, tips, and final variable-weight prices.",
            color: SmartCartTheme.amber
        )
    }
}
