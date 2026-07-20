import SwiftUI
import UIKit

/// The adaptive confirmation surface shared by single recipes and reviewed
/// Meal Prep plans. Internal pipeline stages stay available to legacy routes,
/// but the normal funnel no longer asks the user to visit them one by one.
struct RecipeReadyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expandedIngredientIDs: Set<UUID> = []
    @State private var activeSheet: RecipeReadySheet?
    @State private var continueAfterRetailerSetup = false
    @State private var tripSettingsConfirmed = false
    @State private var issueCursor = 0
    @State private var isPreparingProducts = false
    @AccessibilityFocusState private var focusedIssueID: UUID?

    var body: some View {
        @Bindable var appModel = appModel

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if appModel.isMealPrepShopping {
                        mealPrepHeader
                        mealPrepRecipeSummary
                        mealPrepIngredientSummary
                    } else {
                        recipeHeader
                        ingredientSection(proxy: proxy, appModel: $appModel)
                    }

                    pantrySummary
                    shoppingSettingsSummary
                    purchaseSummary
                }
                .padding(18)
                .padding(.bottom, 104)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onAppear(perform: expandAttentionRows)
            .onChange(of: attentionIngredientIDs) { _, _ in
                expandAttentionRows()
            }
        }
        .smartCartBackground()
        .navigationTitle("Recipe Ready")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                VStack(alignment: .leading, spacing: 7) {
                    if let explanation = appModel.recipeReadyDisabledExplanation {
                        Label(explanation, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SmartCartTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("recipe-ready-disabled-reason")
                    }

                    Button {
                        Task { await startShopping() }
                    } label: {
                        if isPreparingProducts {
                            HStack {
                                Text("Preparing Products…")
                                Spacer()
                                ProgressView()
                                    .tint(SmartCartTheme.onAccent)
                                    .accessibilityIdentifier("recipe-ready-preparing-products")
                            }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text("Start Shopping · \(appModel.recipeReadyExpectedPurchaseCount) items")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                HStack {
                                    Text("Start Shopping")
                                    Spacer()
                                    Text(appModel.recipeReadyExpectedPurchaseCount, format: .number)
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!appModel.recipeReadyCanStartShopping || isPreparingProducts)
                    .accessibilityIdentifier("recipe-ready-start-shopping")
                    .accessibilityLabel(
                        isPreparingProducts
                            ? "Preparing Products"
                            : "Start Shopping, \(appModel.recipeReadyExpectedPurchaseCount) items"
                    )
                    .accessibilityHint(appModel.recipeReadyDisabledExplanation ?? "Matches products and opens the shopping trip")
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: sheetDidDismiss) { sheet in
            switch sheet {
            case .pantry:
                RecipeReadyPantrySheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .shoppingSettings:
                RecipeReadyTripSettingsSheet {
                    tripSettingsConfirmed = true
                }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .productExceptions:
                ProductExceptionReviewSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            case .sourceText:
                NavigationStack {
                    ScrollView {
                        Text(appModel.activeRecipe.rawSourceText ?? "")
                            .font(.body.monospaced())
                            .foregroundStyle(SmartCartTheme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    }
                    .smartCartBackground()
                    .navigationTitle("Source Text")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var recipeHeader: some View {
        @Bindable var appModel = appModel

        return VStack(alignment: .leading, spacing: 16) {
            Label("RECIPE READY", systemImage: "checkmark.seal.fill")
                .smartEyebrow()

            TextField("Recipe title", text: $appModel.activeRecipe.title, axis: .vertical)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.navy)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("recipe-ready-title")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    servingIdentity
                    Spacer(minLength: 8)
                    servingControls
                }
                VStack(alignment: .leading, spacing: 12) {
                    servingIdentity
                    servingControls
                }
            }

            if hasRawSourceText {
                Button {
                    activeSheet = .sourceText
                } label: {
                    Label("View Source Text", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("recipe-ready-view-source-text")
                .accessibilityHint("Opens the original recognized recipe text")
            }
        }
        .smartCartCard()
        .smartCartShadow()
    }

    private var hasRawSourceText: Bool {
        guard let rawSourceText = appModel.activeRecipe.rawSourceText else { return false }
        return !rawSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var servingIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Servings")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SmartCartTheme.navy)
            Text("Original recipe: \(appModel.activeRecipe.servings)")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
    }

    private var servingControls: some View {
        HStack(spacing: 12) {
            servingButton(symbol: "minus", delta: -1)
            Text(appModel.desiredServings, format: .number)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(SmartCartTheme.navy)
                .frame(minWidth: 38)
                .accessibilityLabel("\(appModel.desiredServings) servings")
            servingButton(symbol: "plus", delta: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func servingButton(symbol: String, delta: Int) -> some View {
        Button {
            appModel.updateServings(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 44, height: 44)
                .background(SmartCartTheme.herbLight)
                .clipShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(delta > 0 ? "Increase servings" : "Decrease servings")
        .accessibilityIdentifier(delta > 0 ? "recipe-ready-servings-increase" : "recipe-ready-servings-decrease")
    }

    @ViewBuilder
    private func ingredientSection(proxy: ScrollViewProxy, appModel: Bindable<AppModel>) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    ingredientHeading
                    Spacer(minLength: 8)
                    issueControl(proxy: proxy)
                }
                VStack(alignment: .leading, spacing: 9) {
                    ingredientHeading
                    issueControl(proxy: proxy)
                }
            }

            LazyVStack(spacing: 10) {
                ForEach(appModel.activeRecipe.ingredients) { $ingredient in
                    RecipeReadyIngredientRow(
                        ingredient: $ingredient,
                        isExpanded: expansionBinding(for: ingredient.id),
                        onDelete: {
                            self.appModel.activeRecipe.ingredients.removeAll { $0.id == ingredient.id }
                            expandedIngredientIDs.remove(ingredient.id)
                        }
                    )
                    .id(ingredient.id)
                    .accessibilityFocused($focusedIssueID, equals: ingredient.id)
                }
            }

            Button {
                let ingredient = Ingredient(name: "New ingredient", confidence: .review)
                self.appModel.activeRecipe.ingredients.append(ingredient)
                expandedIngredientIDs.insert(ingredient.id)
            } label: {
                Label("Add an ingredient", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("recipe-ready-add-ingredient")
        }
    }

    private var ingredientHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ingredients")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.navy)
            Text("\(appModel.includedIngredientCount) included · tap any row to edit")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private func issueControl(proxy: ScrollViewProxy) -> some View {
        if !blockingIngredientIDs.isEmpty {
            Button {
                focusNextIssue(proxy: proxy)
            } label: {
                Label(
                    "\(blockingIngredientIDs.count) need attention",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartCartTheme.coral)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background(SmartCartTheme.coral.opacity(0.09))
                .clipShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("recipe-ready-review-issues")
            .accessibilityHint("Moves to the next ingredient that must be resolved")
        } else if attentionIngredientIDs.count > 0 {
            Label("\(attentionIngredientIDs.count) review suggested", systemImage: "info.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartCartTheme.amber)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Ingredients look good", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartCartTheme.green)
        }
    }

    private var mealPrepHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("MEAL PREP READY", systemImage: "calendar.badge.checkmark")
                .smartEyebrow()
            Text(appModel.currentShoppingMealPrepSnapshot?.title ?? appModel.mealPrepDraft?.title ?? "Weekly Meal Prep")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.navy)
            Text("\(appModel.currentShoppingMealPrepSnapshot?.recipeCount ?? 0) recipes · \(appModel.includedIngredientCount) combined ingredients")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .smartCartCard()
        .smartCartShadow()
    }

    private var mealPrepRecipeSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recipes and servings", subtitle: "Each recipe keeps its own scale")
            ForEach(appModel.currentShoppingMealPrepSnapshot?.selections ?? []) { selection in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        mealPrepRecipeIdentity(selection)
                        Spacer(minLength: 8)
                        mealPrepServingControls(selection)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        mealPrepRecipeIdentity(selection)
                        mealPrepServingControls(selection)
                    }
                }
                .smartCartCard(padding: 13)
            }
        }
    }

    private func mealPrepRecipeIdentity(_ selection: MealPrepSelection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selection.recipeSnapshot.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SmartCartTheme.navy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Originally \(selection.recipeSnapshot.originalServings) servings")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
    }

    private func mealPrepServingControls(_ selection: MealPrepSelection) -> some View {
        HStack(spacing: 9) {
            mealPrepServingButton(selection: selection, symbol: "minus", delta: -1)
            Text(Int(selection.targetServings), format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(SmartCartTheme.navy)
                .frame(minWidth: 34)
            mealPrepServingButton(selection: selection, symbol: "plus", delta: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func mealPrepServingButton(
        selection: MealPrepSelection,
        symbol: String,
        delta: Double
    ) -> some View {
        Button {
            appModel.updateMealPrepServings(selectionID: selection.id, delta: delta)
        } label: {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 44, height: 44)
                .background(SmartCartTheme.herbLight)
                .clipShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(
            delta > 0
                ? "Increase servings for \(selection.recipeSnapshot.title)"
                : "Decrease servings for \(selection.recipeSnapshot.title)"
        )
    }

    private var mealPrepIngredientSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Combined ingredients",
                subtitle: appModel.recipeReadyBlockingIssueCount == 0
                    ? "Reviewed and ready for pantry decisions"
                    : "\(appModel.recipeReadyBlockingIssueCount) still need review"
            )

            ForEach(Array(mealPrepParticipatingLines.prefix(10))) { line in
                HStack(spacing: 10) {
                    Image(systemName: line.needsReview ? "exclamationmark.triangle.fill" : line.category.symbol)
                        .foregroundStyle(line.needsReview ? SmartCartTheme.coral : SmartCartTheme.green)
                        .frame(width: 34, height: 34)
                        .background((line.needsReview ? SmartCartTheme.coral : SmartCartTheme.green).opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SmartCartTheme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Ingredient.quantityText(line.quantity, unit: line.unit.symbol == "count" ? "" : line.unit.symbol))
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                    Spacer(minLength: 6)
                    if line.needsReview {
                        Text("Needs review")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(SmartCartTheme.coral)
                    }
                }
                .smartCartCard(padding: 12)
            }

            if mealPrepParticipatingLines.count > 10 {
                Text("Plus \(mealPrepParticipatingLines.count - 10) more combined ingredients")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var pantrySummary: some View {
        Button {
            activeSheet = .pantry
        } label: {
            RecipeReadySummaryRow(
                symbol: "cabinet.fill",
                color: SmartCartTheme.purple,
                title: "Pantry",
                primaryDetail: pantryPrimaryDetail,
                secondaryDetail: "\(appModel.recipeReadyExpectedPurchaseCount) ingredients currently need buying",
                actionTitle: "Review"
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("recipe-ready-pantry-summary")
        .accessibilityLabel("Pantry. \(pantryPrimaryDetail). \(appModel.recipeReadyExpectedPurchaseCount) ingredients currently need buying")
        .accessibilityHint("Review what SmartCart should buy")
    }

    private var pantryPrimaryDetail: String {
        let count = appModel.recipeReadyPantrySuggestionCount
        if count == 0 { return "No safe matches need review" }
        return "Can reduce \(count) item\(count == 1 ? "" : "s")"
    }

    private var shoppingSettingsSummary: some View {
        Button {
            continueAfterRetailerSetup = false
            tripSettingsConfirmed = false
            activeSheet = .shoppingSettings
        } label: {
            RecipeReadySummaryRow(
                symbol: "storefront.fill",
                color: appModel.selectedRetailer == .walmart ? SmartCartTheme.walmartBlue : .red,
                title: retailerLocationSummary,
                primaryDetail: "\(appModel.fulfillmentMode.rawValue) · \(appModel.preferences.summary)",
                secondaryDetail: appModel.retailerSetupIsComplete
                    ? "Retailer setup ready"
                    : "Retailer setup needed before the first product",
                actionTitle: "Change"
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("recipe-ready-retailer-summary")
        .accessibilityLabel("\(retailerLocationSummary), \(appModel.fulfillmentMode.rawValue), \(appModel.preferences.summary)")
        .accessibilityHint("Change retailer, store, fulfillment, or shopping preferences")
    }

    private var purchaseSummary: some View {
        InfoBanner(
            symbol: "basket.fill",
            title: "\(appModel.recipeReadyExpectedPurchaseCount) items to buy",
            message: "SmartCart will match products now. Exact high-confidence matches continue automatically; only product exceptions need another decision.",
            color: SmartCartTheme.green
        )
        .accessibilityIdentifier("recipe-ready-purchase-summary")
    }

    private var retailerLocationSummary: String {
        if appModel.selectedRetailer == .walmart {
            return "\(appModel.retailerConfiguration.displayName) · \(appModel.primaryStore.name)"
        }
        return "\(appModel.retailerConfiguration.displayName) · Store chosen on retailer page"
    }

    private var attentionIngredientIDs: [UUID] {
        appModel.activeRecipe.ingredients.compactMap { ingredient in
            guard ingredient.includeInList,
                  ingredient.confidence != .high
                    || ingredient.quantityReviewRequired == true
                    || hasUnresolvedAlternative(ingredient) else { return nil }
            return ingredient.id
        }
    }

    private var mealPrepParticipatingLines: [CombinedIngredientLine] {
        (appModel.currentShoppingMealPrepSnapshot?.lines ?? []).filter(\.participatesInCurrentTrip)
    }

    private var blockingIngredientIDs: [UUID] {
        appModel.activeRecipe.ingredients.compactMap { ingredient in
            guard ingredient.includeInList,
                  ingredient.quantityReviewRequired == true || hasUnresolvedAlternative(ingredient) else { return nil }
            return ingredient.id
        }
    }

    private func hasUnresolvedAlternative(_ ingredient: Ingredient) -> Bool {
        ingredient.alternativeGroup != nil && ingredient.name.range(
            of: #"\s+or\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func expansionBinding(for ingredientID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedIngredientIDs.contains(ingredientID) },
            set: { expanded in
                if expanded {
                    expandedIngredientIDs.insert(ingredientID)
                } else {
                    expandedIngredientIDs.remove(ingredientID)
                }
            }
        )
    }

    private func expandAttentionRows() {
        expandedIngredientIDs.formUnion(attentionIngredientIDs)
    }

    private func focusNextIssue(proxy: ScrollViewProxy) {
        let issues = blockingIngredientIDs
        guard !issues.isEmpty else { return }
        let issueID = issues[issueCursor % issues.count]
        issueCursor = (issueCursor + 1) % issues.count
        expandedIngredientIDs.insert(issueID)
        withAnimation(.easeInOut) {
            proxy.scrollTo(issueID, anchor: .center)
        }
        DispatchQueue.main.async {
            focusedIssueID = issueID
        }
    }

    private func startShopping() async {
        guard appModel.recipeReadyCanStartShopping, !isPreparingProducts else { return }
        if appModel.retailerSetupIsComplete {
            await prepareProducts()
        } else {
            continueAfterRetailerSetup = true
            tripSettingsConfirmed = false
            activeSheet = .shoppingSettings
        }
    }

    private func sheetDidDismiss() {
        let shouldContinue = continueAfterRetailerSetup && tripSettingsConfirmed
        continueAfterRetailerSetup = false
        tripSettingsConfirmed = false
        guard shouldContinue else { return }
        guard appModel.retailerSetupIsComplete else { return }
        Task { await prepareProducts() }
    }

    private func prepareProducts() async {
        guard !isPreparingProducts else { return }
        isPreparingProducts = true
        defer { isPreparingProducts = false }

        guard appModel.beginShoppingFromRecipeReady() else { return }
        await appModel.startMatching()
        guard !Task.isCancelled else { return }

        if appModel.unresolvedMatchingExceptionItems.isEmpty {
            _ = appModel.continueToShoppingTrip()
        } else {
            activeSheet = .productExceptions
        }
    }
}

/// Kept so schema-era navigation values and older tests can still construct
/// the legacy destination while the live funnel enters Recipe Ready directly.
struct IngredientReviewView: View {
    var body: some View { RecipeReadyView() }
}

/// Compatibility destination only. Serving controls now live in Recipe Ready.
struct ServingAdjustmentView: View {
    var body: some View { RecipeReadyView() }
}

private enum RecipeReadySheet: String, Identifiable {
    case pantry
    case shoppingSettings
    case productExceptions
    case sourceText

    var id: String { rawValue }
}

private struct RecipeReadySummaryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let symbol: String
    let color: Color
    let title: String
    let primaryDetail: String
    let secondaryDetail: String
    let actionTitle: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 11) {
                    identity
                    HStack {
                        Text(actionTitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SmartCartTheme.green)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(SmartCartTheme.green)
                    }
                }
            } else {
                HStack(spacing: 13) {
                    identity
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(actionTitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SmartCartTheme.green)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(SmartCartTheme.green)
                    }
                }
            }
        }
        .smartCartCard(padding: 14)
        .contentShape(Rectangle())
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(primaryDetail)
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(secondaryDetail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RecipeReadyIngredientRow: View {
    @Environment(AppModel.self) private var appModel
    @Binding var ingredient: Ingredient
    @Binding var isExpanded: Bool
    let onDelete: () -> Void
    @State private var showSourceEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                compactSummary
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryAccessibilityLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse ingredient editor" : "Open ingredient editor")
            .accessibilityIdentifier("recipe-ready-ingredient-\(ingredient.id.uuidString)")

            if isExpanded {
                Divider()
                editor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(13)
        .background(ingredient.includeInList ? SmartCartTheme.paper : SmartCartTheme.canvas.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(needsAttention ? SmartCartTheme.amber.opacity(0.72) : SmartCartTheme.border, lineWidth: needsAttention ? 1.5 : 1)
        }
        .opacity(ingredient.includeInList ? 1 : 0.68)
    }

    private var compactSummary: some View {
        HStack(spacing: 11) {
            Image(systemName: ingredient.category.symbol)
                .font(.subheadline.bold())
                .foregroundStyle(ingredient.includeInList ? SmartCartTheme.green : SmartCartTheme.secondaryInk)
                .frame(width: 40, height: 40)
                .background(ingredient.includeInList ? SmartCartTheme.herbLight : SmartCartTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(compactDetail)
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if ingredient.quantityReviewRequired == true {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SmartCartTheme.coral)
                    .accessibilityHidden(true)
            } else if ingredient.confidence != .high {
                Image(systemName: ingredient.confidence.symbol)
                    .foregroundStyle(ingredient.confidence.color)
                    .accessibilityHidden(true)
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .accessibilityHidden(true)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Include in this shopping trip", isOn: $ingredient.includeInList)
                .tint(SmartCartTheme.green)
                .accessibilityValue(ingredient.includeInList ? "Included" : "Excluded")

            TextField("Ingredient name", text: $ingredient.name)
                .font(.subheadline.weight(.bold))
                .textInputAutocapitalization(.words)
                .smartField()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { measurementFields }
                VStack(spacing: 8) { measurementFields }
            }
            .font(.caption)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { correctionMenus }
                VStack(alignment: .leading, spacing: 10) { correctionMenus }
            }

            if ingredient.quantityReviewRequired == true {
                quantityResolution
            }

            if let evidence = ingredient.sourceEvidence {
                sourceEvidence(evidence)
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete ingredient", systemImage: "trash")
                    .font(.caption.weight(.bold))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Delete \(ingredient.name)")
        }
        .onChange(of: ingredient.name) { _, _ in appModel.refreshPantrySuggestions() }
        .onChange(of: ingredient.quantity) { _, _ in appModel.refreshPantrySuggestions() }
        .onChange(of: ingredient.unit) { _, _ in appModel.refreshPantrySuggestions() }
        .onChange(of: ingredient.includeInList) { _, _ in appModel.refreshPantrySuggestions() }
    }

    @ViewBuilder private var measurementFields: some View {
        TextField("Quantity", value: $ingredient.quantity, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .smartField()
        TextField("Unit", text: $ingredient.unit)
            .textInputAutocapitalization(.never)
            .smartField()
        TextField("Preparation (optional)", text: $ingredient.preparation)
            .smartField()
    }

    @ViewBuilder private var correctionMenus: some View {
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
                .frame(minHeight: 44)
        }

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
                .frame(minHeight: 44)
        }
    }

    private var quantityResolution: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Quantity is uncertain. Confirm it before shopping.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartCartTheme.coral)
                .fixedSize(horizontal: false, vertical: true)

            if let candidates = ingredient.sourceEvidence?.alternateQuantityCandidates,
               candidates.count > 1 {
                Menu {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                        Button(Ingredient.quantityText(candidate, unit: ingredient.unit)) {
                            ingredient.quantity = candidate
                            ingredient.quantityReviewRequired = false
                        }
                    }
                } label: {
                    Label("Choose quantity", systemImage: "list.bullet")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                Button("Confirm \(ingredient.displayQuantity)") {
                    ingredient.quantityReviewRequired = false
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
        }
        .padding(11)
        .background(SmartCartTheme.coral.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityIdentifier("recipe-ready-quantity-review-\(ingredient.id.uuidString)")
    }

    private func sourceEvidence(_ evidence: IngredientSourceEvidence) -> some View {
        DisclosureGroup(isExpanded: $showSourceEvidence) {
            VStack(alignment: .leading, spacing: 6) {
                if let cropData = evidence.sourceCropJPEGData,
                   let crop = UIImage(data: cropData) {
                    Image(uiImage: crop)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 150)
                        .background(SmartCartTheme.canvasRaise)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                if let alternatives = evidence.alternateSourceTexts, !alternatives.isEmpty {
                    Text("OCR alternatives")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SmartCartTheme.amber)
                    ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alternative in
                        Text(alternative)
                            .font(.caption2.monospaced())
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                }
            }
            .padding(.top, 7)
        } label: {
            Label("Source evidence", systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartCartTheme.walmartBlue)
                .frame(minHeight: 44)
        }
    }

    private var needsAttention: Bool {
        ingredient.quantityReviewRequired == true || ingredient.confidence != .high
    }

    private var compactDetail: String {
        var parts = [appModel.scaledQuantityText(for: ingredient)]
        if !ingredient.preparation.isEmpty { parts.append(ingredient.preparation) }
        if !ingredient.includeInList { parts.append("Excluded") }
        return parts.joined(separator: " · ")
    }

    private var summaryAccessibilityLabel: String {
        var value = "\(ingredient.name), \(compactDetail)"
        if ingredient.quantityReviewRequired == true { value += ", quantity must be confirmed" }
        else if ingredient.confidence != .high { value += ", \(ingredient.confidence.label)" }
        return value
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
            case .recent: "Opened"
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
            ViewThatFits(in: .horizontal) {
                HStack {
                    recipesTitle
                    Spacer()
                    SmartCartLogo(compact: true)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    recipesTitle
                    SmartCartLogo(compact: true)
                        .accessibilityHidden(true)
                }
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
                    .accessibilityAddTraits(page == candidate ? .isSelected : [])
                    .accessibilityIdentifier(candidate == .saved ? "recipes-page-saved" : "recipes-page-opened")
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

    private var recipesTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Recipes")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.navy)
            Text("Saved lists and recently opened recipes")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
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
                    title: "Recently opened",
                    subtitle: recentlyOpenedSubtitle
                )

                if appModel.recentRecipes.isEmpty {
                    EmptyStateView(
                        symbol: "clock.fill",
                        title: "Nothing recent yet",
                        message: "Recipes you import or open will appear here."
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
        let canShopAgain = appModel.hasCompletedShoppingTrip &&
            appModel.mostRecentShoppedRecipe?.id == recipe.id
        let actionTitle = canShopAgain ? "Shop Again" : "Open"

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 13) {
                recentRecipeIdentity(recipe)
                Spacer(minLength: 6)
                recentRecipeAction(recipe, title: actionTitle, fillsWidth: false)
            }
            VStack(alignment: .leading, spacing: 12) {
                recentRecipeIdentity(recipe)
                recentRecipeAction(recipe, title: actionTitle, fillsWidth: true)
            }
        }
        .smartCartCard(padding: 13)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recently-opened-recipe-\(recipe.id.uuidString)")
    }

    private func recentRecipeIdentity(_ recipe: Recipe) -> some View {
        HStack(spacing: 13) {
            Image(systemName: recipe.heroSymbol)
                .font(.title3.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 48, height: 48)
                .background(SmartCartTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                    .lineLimit(2)
                Text("\(recipe.ingredients.count) ingredients · \(recipe.servings) servings · \(recipe.source.rawValue)")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func recentRecipeAction(
        _ recipe: Recipe,
        title: String,
        fillsWidth: Bool
    ) -> some View {
        Button {
            appModel.beginRecipe(recipe)
        } label: {
            Label(title, systemImage: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartCartTheme.onAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background(SmartCartTheme.green)
                .clipShape(fillsWidth ? AnyShape(RoundedRectangle(cornerRadius: 13, style: .continuous)) : AnyShape(Capsule()))
        }
        .buttonStyle(PressableButtonStyle())
        .smartCartMinimumHitTarget()
        .accessibilityLabel(title == "Shop Again" ? "Shop \(recipe.title) again" : "Open \(recipe.title)")
        .accessibilityIdentifier(title == "Shop Again" ? "recipe-shop-again" : "recipe-open")
    }

    private var recentlyOpenedSubtitle: String {
        let count = min(5, appModel.recentRecipes.count)
        return count == 0
            ? "Recipes you open will appear here"
            : "\(count) most recently opened recipe\(count == 1 ? "" : "s"), newest first"
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
                    Text("Save the current shopping list to keep its products, quantities, observed-price subtotal, and Shopping Trip progress here.")
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
