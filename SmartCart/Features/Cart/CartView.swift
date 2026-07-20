import SwiftUI
import UIKit

/// The adaptive confirmation surface shared by single recipes and reviewed
/// Meal Prep plans. Internal pipeline stages stay available to legacy routes,
/// but the normal funnel no longer asks the user to visit them one by one.
struct RecipeReadyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedIngredientIDs: Set<UUID> = []
    @State private var activeSheet: RecipeReadySheet?
    @State private var continueAfterRetailerSetup = false
    @State private var tripSettingsConfirmed = false
    @State private var issueCursor = 0
    @State private var isPreparingProducts = false
    @State private var pendingIngredientDeletion: PendingIngredientDeletion?
    @AccessibilityFocusState private var focusedIssueID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if appModel.isMealPrepShopping {
                        mealPrepHeader
                        mealPrepRecipeSummary
                        mealPrepIngredientSummary
                    } else {
                        recipeHeader
                        ingredientSection(proxy: proxy)
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
                        } else if dynamicTypeSize.isAccessibilitySize {
                            HStack {
                                Text("Start\nShopping")
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                Image(systemName: "arrow.right")
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
        .confirmationDialog(
            pendingIngredientDeletion.map {
                "Remove “\($0.name)” from this recipe?"
            } ?? "Remove ingredient?",
            isPresented: Binding(
                get: { pendingIngredientDeletion != nil },
                set: { isPresented in
                    if !isPresented { pendingIngredientDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: confirmIngredientDeletion)
            Button("Cancel", role: .cancel) { pendingIngredientDeletion = nil }
        }
        .overlay {
            if isPreparingProducts {
                ShoppingLaunchOverlay(
                    stage: appModel.matchStage,
                    progress: appModel.matchProgress
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? nil : SmartCartMotion.signature,
            value: isPreparingProducts
        )
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

            if !appModel.isRecipeSaved(appModel.activeRecipe.id) {
                Button {
                    appModel.saveRecipeToLibrary(appModel.activeRecipe.id)
                } label: {
                    Label("Save Recipe", systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("recipe-ready-save-recipe")
                .accessibilityHint("Adds this recipe to Saved Recipes")
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
    private func ingredientSection(proxy: ScrollViewProxy) -> some View {
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
                ForEach(appModel.activeRecipe.ingredients) { ingredient in
                    RecipeReadyIngredientRow(
                        ingredient: ingredient,
                        isExpanded: expansionBinding(for: ingredient.id),
                        onUpdate: { updatedIngredient in
                            self.appModel.updateIngredient(
                                id: ingredient.id,
                                with: updatedIngredient
                            )
                        },
                        onDelete: {
                            pendingIngredientDeletion = PendingIngredientDeletion(
                                id: ingredient.id,
                                name: ingredient.name
                            )
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

    private func confirmIngredientDeletion() {
        guard let deletion = pendingIngredientDeletion else { return }
        pendingIngredientDeletion = nil
        guard appModel.removeIngredient(id: deletion.id) else { return }

        expandedIngredientIDs.remove(deletion.id)
        if focusedIssueID == deletion.id {
            focusedIssueID = nil
        }
        issueCursor = 0
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
            guard appModel.activeRecipe.ingredients.contains(where: { $0.id == issueID }) else {
                return
            }
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

private struct ShoppingLaunchOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cartPulse = false

    let stage: String
    let progress: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.32))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "cart.fill.badge.plus")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .shadow(color: SmartCartTheme.mintGlow, radius: 18)
                    .scaleEffect(cartPulse ? 1.06 : 0.96)

                VStack(spacing: 6) {
                    Text("Launching Shopping Trip")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(stage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .contentTransition(.numericText())
                }

                ProgressView(value: max(0.06, progress))
                    .tint(SmartCartTheme.green)
                    .frame(maxWidth: 240)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 34)
            .background(Color.black.opacity(0.50))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                cartPulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Launching Shopping Trip, \(stage)")
        .accessibilityIdentifier("shopping-launch-transition")
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

private struct PendingIngredientDeletion: Identifiable {
    let id: UUID
    let name: String
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
    let ingredient: Ingredient
    @Binding var isExpanded: Bool
    let onUpdate: (Ingredient) -> Void
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
            Toggle(
                "Include in this shopping trip",
                isOn: binding(for: \.includeInList)
            )
                .tint(SmartCartTheme.green)
                .accessibilityValue(ingredient.includeInList ? "Included" : "Excluded")

            TextField("Ingredient name", text: binding(for: \.name))
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
        TextField(
            "Quantity",
            value: binding(for: \.quantity),
            format: .number.precision(.fractionLength(0...2))
        )
            .keyboardType(.decimalPad)
            .smartField()
        TextField("Unit", text: binding(for: \.unit))
            .textInputAutocapitalization(.never)
            .smartField()
        TextField("Preparation (optional)", text: binding(for: \.preparation))
            .smartField()
    }

    @ViewBuilder private var correctionMenus: some View {
        Menu {
            ForEach(IngredientConfidence.allCases) { confidence in
                Button {
                    updateIngredient { $0.confidence = confidence }
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
                    updateIngredient { $0.category = category }
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
                            updateIngredient {
                                $0.quantity = candidate
                                $0.quantityReviewRequired = false
                            }
                        }
                    }
                } label: {
                    Label("Choose quantity", systemImage: "list.bullet")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                Button("Confirm \(ingredient.displayQuantity)") {
                    updateIngredient { $0.quantityReviewRequired = false }
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

    private func binding<Value>(
        for keyPath: WritableKeyPath<Ingredient, Value>
    ) -> Binding<Value> {
        Binding(
            get: { ingredient[keyPath: keyPath] },
            set: { newValue in
                updateIngredient { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func updateIngredient(_ update: (inout Ingredient) -> Void) {
        var updatedIngredient = ingredient
        update(&updatedIngredient)
        onUpdate(updatedIngredient)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var pendingRecipeRemoval: Recipe?
    @State private var recentDrawerExpanded = {
        let environment = ProcessInfo.processInfo.environment
        return environment["SMARTCART_RECIPES_DRAWER"] == "recent" ||
            environment["SMARTCART_RECIPES_PAGE"] == "recent"
    }()
    @GestureState private var recentDrawerDrag: CGFloat = 0

    private let collapsedDrawerHeight: CGFloat = 92

    var body: some View {
        GeometryReader { geometry in
            let drawerHeight = max(420, geometry.size.height - 88)
            let collapsedOffset = drawerHeight - collapsedDrawerHeight

            ZStack(alignment: .bottom) {
                recipeLibrary

                recentRecipesDrawer(height: drawerHeight, collapsedOffset: collapsedOffset)
                    .offset(y: recentDrawerOffset(collapsedOffset: collapsedOffset))
                    .animation(
                        reduceMotion ? nil : SmartCartMotion.signature,
                        value: recentDrawerExpanded
                    )
            }
        }
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: recentDrawerExpanded)
        .confirmationDialog(
            pendingRecipeRemoval.map {
                "Remove “\($0.title)” from Saved Recipes?"
            } ?? "Remove recipe from Saved Recipes?",
            isPresented: Binding(
                get: { pendingRecipeRemoval != nil },
                set: { isPresented in
                    if !isPresented { pendingRecipeRemoval = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from Saved Recipes", role: .destructive) {
                guard let recipe = pendingRecipeRemoval else { return }
                pendingRecipeRemoval = nil
                appModel.removeRecipeFromLibrary(recipe.id)
            }
            Button("Cancel", role: .cancel) { pendingRecipeRemoval = nil }
        } message: {
            Text("Existing Shopping Trips and pantry history will remain available.")
        }
    }

    private var recipeLibrary: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                libraryHeader
                recipeSearch

                if filteredRecipes.isEmpty {
                    EmptyStateView(
                        symbol: "book.closed.fill",
                        title: searchText.isEmpty ? "No saved recipes" : "No matching recipes",
                        message: searchText.isEmpty
                            ? "Import a recipe from Home to build your library."
                            : "Try another recipe title or ingredient."
                    )
                } else {
                    ForEach(filteredRecipes) { recipe in
                        recipeLibraryCard(recipe)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, collapsedDrawerHeight + 34)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var libraryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
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
        .padding(.top, 8)
    }

    private var recipesTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Saved Recipes")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.navy)
            Text("View, edit, or reuse a saved recipe")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
    }

    private var recipeSearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SmartCartTheme.secondaryInk)
            TextField("Search saved recipes", text: $searchText)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("recipes-search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .accessibilityLabel("Clear recipe search")
            }
        }
        .smartField()
    }

    private func recipeLibraryCard(_ recipe: Recipe) -> some View {
        HStack(spacing: 8) {
            Button {
                openRecipe(recipe)
            } label: {
                HStack(spacing: 13) {
                    recipeIdentity(recipe, lastOpenedAt: nil)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(SmartCartTheme.green)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("Opens this recipe for review and shopping")

            Menu {
                Button {
                    openRecipe(recipe)
                } label: {
                    Label("Open Recipe", systemImage: "book.fill")
                }
                Button(role: .destructive) {
                    pendingRecipeRemoval = recipe
                } label: {
                    Label("Remove from Saved Recipes", systemImage: "bookmark.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More actions for \(recipe.title)")
            .accessibilityIdentifier("saved-recipe-menu-\(recipe.id.uuidString)")
        }
        .smartCartCard(padding: 13)
        .accessibilityIdentifier("saved-recipe-\(recipe.id.uuidString)")
    }

    private func recentRecipesDrawer(height: CGFloat, collapsedOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            recentDrawerHandle(collapsedOffset: collapsedOffset)

            Divider()
                .overlay(SmartCartTheme.border)

            if recentDrawerExpanded {
                recentRecipeContents
                    .transition(.opacity)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background {
            WoodGrainBackground()
        }
        .clipShape(RecipesPullUpShape())
        .overlay {
            RecipesPullUpShape()
                .stroke(SmartCartTheme.borderStrong.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: -8)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    private func recentDrawerHandle(collapsedOffset: CGFloat) -> some View {
        Button {
            recentDrawerExpanded.toggle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: recentDrawerExpanded ? "chevron.compact.down" : "chevron.compact.up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(height: 35)

                HStack(spacing: 9) {
                    Label("Recent Recipes", systemImage: "clock.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.ink)

                    Spacer()

                    Text(recentDrawerExpanded ? "Swipe down to hide" : "Swipe up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: collapsedDrawerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .simultaneousGesture(recentDragGesture(collapsedOffset: collapsedOffset))
        .accessibilityIdentifier("recipes-recent-drawer")
        .accessibilityLabel("Recent Recipes drawer")
        .accessibilityValue(recentDrawerExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(recentDrawerExpanded ? "Swipe down or tap to hide recent recipes" : "Swipe up or tap to show recent recipes")
    }

    private var recentRecipeContents: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Recent Recipes",
                    subtitle: recentRecipesSubtitle
                )

                if appModel.recentRecipeRecords.isEmpty {
                    EmptyStateView(
                        symbol: "clock.fill",
                        title: "Nothing recent yet",
                        message: "Recipes you import or intentionally open will appear here."
                    )
                } else {
                    ForEach(appModel.recentRecipeRecords.prefix(5)) { record in
                        if let recipe = appModel.recipes.first(where: { $0.id == record.recipeID }) {
                            recentRecipeCard(recipe, record: record)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func recentRecipeCard(_ recipe: Recipe, record: RecentRecipeRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            recipeIdentity(recipe, lastOpenedAt: record.lastOpenedAt)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    openRecipeButton(recipe)
                    if canShopAgain(recipe) {
                        shopAgainButton(recipe)
                    }
                }
                VStack(spacing: 9) {
                    openRecipeButton(recipe)
                    if canShopAgain(recipe) {
                        shopAgainButton(recipe)
                    }
                }
            }
        }
        .smartCartCard(padding: 13)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent-recipe-\(recipe.id.uuidString)")
    }

    private func recipeIdentity(_ recipe: Recipe, lastOpenedAt: Date?) -> some View {
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
                Text("\(recipe.ingredients.count) ingredients · \(recipe.servings) servings")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                if let lastOpenedAt {
                    Text("Opened \(lastOpenedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func openRecipeButton(_ recipe: Recipe) -> some View {
        Button {
            openRecipe(recipe)
        } label: {
            Label("Open Recipe", systemImage: "book.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("recent-recipe-open-\(recipe.id.uuidString)")
    }

    private func shopAgainButton(_ recipe: Recipe) -> some View {
        Button {
            openRecipe(recipe)
        } label: {
            Label("Shop Again", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("recent-recipe-shop-again-\(recipe.id.uuidString)")
    }

    private var filteredRecipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return appModel.savedRecipes }
        return appModel.savedRecipes.filter { recipe in
            recipe.title.lowercased().contains(query) ||
                recipe.ingredients.contains { $0.name.lowercased().contains(query) }
        }
    }

    private var recentRecipesSubtitle: String {
        let count = min(5, appModel.recentRecipeRecords.count)
        return count == 0
            ? "Whole recipes you open will appear here"
            : "\(count) most recently opened recipe\(count == 1 ? "" : "s"), newest first"
    }

    private func canShopAgain(_ recipe: Recipe) -> Bool {
        appModel.shoppingSessions.contains { session in
            session.recipeID == recipe.id && (session.isGuideComplete || session.isCommitted)
        }
    }

    private func openRecipe(_ recipe: Recipe) {
        recentDrawerExpanded = false
        appModel.beginRecipe(recipe)
    }

    private func recentDrawerOffset(collapsedOffset: CGFloat) -> CGFloat {
        let restingOffset = recentDrawerExpanded ? 0 : collapsedOffset
        return min(max(restingOffset + recentDrawerDrag, 0), collapsedOffset)
    }

    private func recentDragGesture(collapsedOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($recentDrawerDrag) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.height
                let decisiveDistance = min(96, collapsedOffset * 0.22)

                if recentDrawerExpanded {
                    if projected > decisiveDistance {
                        recentDrawerExpanded = false
                    }
                } else if projected < -decisiveDistance {
                    recentDrawerExpanded = true
                }
            }
    }
}

private struct RecipesPullUpShape: Shape {
    func path(in rect: CGRect) -> Path {
        let top: CGFloat = 34
        let cornerRadius: CGFloat = 26
        let handleRadius: CGFloat = 36
        let centerX = rect.midX

        var path = Path()
        path.move(to: CGPoint(x: cornerRadius, y: top))
        path.addLine(to: CGPoint(x: centerX - handleRadius, y: top))
        path.addCurve(
            to: CGPoint(x: centerX, y: 0),
            control1: CGPoint(x: centerX - 23, y: top),
            control2: CGPoint(x: centerX - 28, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: centerX + handleRadius, y: top),
            control1: CGPoint(x: centerX + 28, y: 0),
            control2: CGPoint(x: centerX + 23, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: top + cornerRadius),
            control: CGPoint(x: rect.maxX, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: top + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: top),
            control: CGPoint(x: rect.minX, y: top)
        )
        path.closeSubpath()
        return path
    }
}
