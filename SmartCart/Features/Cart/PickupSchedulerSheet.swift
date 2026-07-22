import SwiftUI

struct PantryCheckView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 3,
                    total: 6,
                    eyebrow: "Pantry check",
                    title: "What do you already have?",
                    message: "Skip items you have, flag low staples, or keep SmartCart asking every time."
                )

                pantrySummary
                quickActions

                VStack(spacing: 10) {
                    ForEach($appModel.activeRecipe.ingredients) { $ingredient in
                        if ingredient.includeInList {
                            PantryIngredientRow(ingredient: $ingredient)
                        }
                    }
                }

                InfoBanner(
                    symbol: "brain.head.profile.fill",
                    title: "Pantry memory",
                    message: "This prototype keeps choices on this device for the active recipe. A production version can learn recurring staples without sharing them with a retailer.",
                    color: SmartCartTheme.purple
                )
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .smartCartBackground()
        .navigationTitle("Pantry check")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.continueTo(.preferences)
                } label: {
                    HStack {
                        Text("Set shopping preferences")
                        Spacer()
                        Text("\(appModel.ingredientsToBuy.count) to buy")
                            .font(.caption.weight(.bold))
                            .opacity(0.82)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var pantrySummary: some View {
        HStack(spacing: 10) {
            summaryMetric(
                value: "\(appModel.ingredientsToBuy.count)",
                label: "To buy",
                symbol: "cart.badge.plus",
                color: SmartCartTheme.walmartBlue
            )
            summaryMetric(
                value: "\(appModel.pantrySkipCount)",
                label: "Skipped",
                symbol: "checkmark.seal.fill",
                color: SmartCartTheme.green
            )
            summaryMetric(
                value: "\(appModel.activeRecipe.ingredients.filter { $0.pantryState == .runningLow }.count)",
                label: "Running low",
                symbol: "clock.fill",
                color: SmartCartTheme.amber
            )
        }
    }

    private func summaryMetric(value: String, label: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(SmartCartTheme.navy)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SmartCartTheme.border, lineWidth: 1)
        }
    }

    private var quickActions: some View {
        ViewThatFits {
            HStack(spacing: 9) {
                Button("Buy everything") {
                    for index in appModel.activeRecipe.ingredients.indices where appModel.activeRecipe.ingredients[index].includeInList {
                        appModel.activeRecipe.ingredients[index].pantryState = .needToBuy
                        appModel.activeRecipe.ingredients[index].pantryDecision = .buyFull
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Skip common staples") {
                    for index in appModel.activeRecipe.ingredients.indices {
                        let value = appModel.activeRecipe.ingredients[index].name.lowercased()
                        if value.contains("salt") || value.contains("pepper") || value.contains("water") {
                            appModel.activeRecipe.ingredients[index].pantryState = .haveEnough
                            appModel.activeRecipe.ingredients[index].pantryDecision = .useAvailable
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 9) {
                Button("Buy everything") {
                    for index in appModel.activeRecipe.ingredients.indices where appModel.activeRecipe.ingredients[index].includeInList {
                        appModel.activeRecipe.ingredients[index].pantryState = .needToBuy
                        appModel.activeRecipe.ingredients[index].pantryDecision = .buyFull
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Skip common staples") {
                    for index in appModel.activeRecipe.ingredients.indices {
                        let value = appModel.activeRecipe.ingredients[index].name.lowercased()
                        if value.contains("salt") || value.contains("pepper") || value.contains("water") {
                            appModel.activeRecipe.ingredients[index].pantryState = .haveEnough
                            appModel.activeRecipe.ingredients[index].pantryDecision = .useAvailable
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// Pantry decisions are reviewed from Recipe Ready instead of repeating them
/// inside every ingredient editor and again on a mandatory route.
struct RecipeReadyPantrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InfoBanner(
                        symbol: "cabinet.fill",
                        title: "What should SmartCart buy?",
                        message: "Pantry matches never remove an ingredient automatically. If you do not choose a safe pantry option, SmartCart buys the full recipe amount.",
                        color: SmartCartTheme.purple
                    )

                    if appModel.isMealPrepShopping {
                        mealPrepPantryRows
                    } else {
                        singleRecipeQuickActions

                        ForEach($appModel.activeRecipe.ingredients) { $ingredient in
                            if ingredient.includeInList {
                                RecipeReadyPantryIngredientRow(ingredient: $ingredient)
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .smartCartBackground()
            .navigationTitle("Pantry Decisions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("recipe-ready-pantry-done")
                }
            }
        }
    }

    private var singleRecipeQuickActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) { pantryBulkActions }
            VStack(spacing: 9) { pantryBulkActions }
        }
    }

    @ViewBuilder private var pantryBulkActions: some View {
        Button("Use safe matches") {
            appModel.useSafePantrySuggestions()
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(appModel.recipeReadyPantrySuggestionCount == 0)
        .accessibilityHint("Uses only exact compatible pantry matches and buys any remainder")

        Button("Buy everything") {
            appModel.buyFullRecipeReadyIngredients()
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityHint("Ignores pantry suggestions and buys the full recipe amounts")
    }

    private var mealPrepPantryRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(
                appModel.currentShoppingMealPrepSnapshot?.lines.filter(\.participatesInCurrentTrip) ?? []
            ) { line in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(SmartCartTheme.navy)
                            Text(mealPrepPantryDetail(line))
                                .font(.caption)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Text("Buy \(Ingredient.quantityText(line.quantityToBuy, unit: line.unit.symbol == "count" ? "" : line.unit.symbol))")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SmartCartTheme.green)
                            .multilineTextAlignment(.trailing)
                    }

                    if line.hasPantryChoice {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { mealPrepPantryChoices(line) }
                            VStack(spacing: 8) { mealPrepPantryChoices(line) }
                        }
                    } else {
                        Label("No safe compatible pantry match", systemImage: "cart.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                }
                .smartCartCard(padding: 13)
            }
        }
    }

    @ViewBuilder
    private func mealPrepPantryChoices(_ line: CombinedIngredientLine) -> some View {
        pantryChoice("Use Pantry", selected: !line.isBuyingFullQuantity) {
            appModel.setMealPrepPantryOverride(lineID: line.id, buyFull: false)
        }
        pantryChoice("Buy Full", selected: line.isBuyingFullQuantity) {
            appModel.setMealPrepPantryOverride(lineID: line.id, buyFull: true)
        }
    }

    private func pantryChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? SmartCartTheme.onAccent : SmartCartTheme.green)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? SmartCartTheme.green : SmartCartTheme.herbLight)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .smartCartMinimumHitTarget()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func mealPrepPantryDetail(_ line: CombinedIngredientLine) -> String {
        let required = Ingredient.quantityText(line.quantity, unit: line.unit.symbol == "count" ? "" : line.unit.symbol)
        guard !line.pantryDeductions.isEmpty else { return "Need \(required) · buying full amount" }
        let applied = line.pantryDeductions.reduce(0) { $0 + $1.quantity }
        let pantry = Ingredient.quantityText(applied, unit: line.unit.symbol == "count" ? "" : line.unit.symbol)
        return "Need \(required) · compatible pantry amount \(pantry)"
    }
}

private struct RecipeReadyPantryIngredientRow: View {
    @Environment(AppModel.self) private var appModel
    @Binding var ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: ingredient.category.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(SmartCartTheme.purple)
                    .frame(width: 42, height: 42)
                    .background(SmartCartTheme.purple.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Need \(appModel.scaledQuantityText(for: ingredient)) · buy \(appModel.quantityToBuyText(for: ingredient))")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }

            if let suggestion = ingredient.pantrySuggestion {
                Label(suggestionTitle(suggestion), systemImage: suggestion.coverage == .possible ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(suggestion.coverage == .possible ? SmartCartTheme.amber : SmartCartTheme.purple)
                Text(suggestionMessage(suggestion))
                    .font(.caption2)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("No safe pantry match · buying full amount", systemImage: "cart.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { choiceButtons }
                VStack(spacing: 8) { choiceButtons }
            }
        }
        .smartCartCard(padding: 13)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var choiceButtons: some View {
        if let suggestion = ingredient.pantrySuggestion, suggestion.coverage != .possible {
            decisionButton(
                suggestion.coverage == .partial ? "Use + Buy Rest" : "Use Pantry",
                selected: ingredient.pantryDecision == .useAvailable && ingredient.pantryState != .haveEnough
            ) {
                appModel.setPantryDecision(.useAvailable, for: ingredient.id)
            }
        }

        decisionButton("Buy Full", selected: ingredient.pantryDecision == .buyFull || ingredient.pantryDecision == nil) {
            appModel.setPantryDecision(.buyFull, for: ingredient.id)
        }

        Menu {
            Button("Already have enough") {
                ingredient.pantryDecision = .useAvailable
                ingredient.pantryState = .haveEnough
            }
            .accessibilityIdentifier("recipe-ready-pantry-have-enough-\(ingredient.id.uuidString)")
            Button("Ask me later") {
                appModel.setPantryDecision(.review, for: ingredient.id)
            }
            .accessibilityIdentifier("recipe-ready-pantry-ask-later-\(ingredient.id.uuidString)")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("More pantry choices for \(ingredient.name)")
        .accessibilityIdentifier("recipe-ready-pantry-more-\(ingredient.id.uuidString)")
    }

    private func decisionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? SmartCartTheme.onAccent : SmartCartTheme.green)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? SmartCartTheme.green : SmartCartTheme.herbLight)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .smartCartMinimumHitTarget()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func suggestionTitle(_ suggestion: PantrySuggestion) -> String {
        switch suggestion.coverage {
        case .full: "Pantry may cover this"
        case .partial: "Pantry may cover part of this"
        case .possible: "Possible name match · units cannot be compared"
        }
    }

    private func suggestionMessage(_ suggestion: PantrySuggestion) -> String {
        switch suggestion.coverage {
        case .full:
            "\(suggestion.pantryItemName) appears to cover the scaled amount. It is used only if you choose Use Pantry."
        case .partial:
            "\(suggestion.pantryItemName) covers about \(Ingredient.quantityText(suggestion.availableQuantity, unit: suggestion.availableUnit)); SmartCart can buy the remainder."
        case .possible:
            "\(suggestion.pantryItemName) matches by name, but \(suggestion.availableUnit.isEmpty ? "its saved package unit" : suggestion.availableUnit) cannot be safely compared with \(ingredient.unit.isEmpty ? "this recipe count" : ingredient.unit). SmartCart will buy the full amount unless you explicitly say you already have enough."
        }
    }
}

/// Retailer, store, fulfillment, and matching preferences are durable defaults
/// edited together from the compact Recipe Ready summary.
struct RecipeReadyTripSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showRetailerSetupSafari = false
    let onConfirm: () -> Void

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(
                        title: "Retailer",
                        subtitle: "Saved settings become the default for future trips"
                    )

                    ForEach(ShoppingRetailer.allCases.filter { $0.configuration.isAvailable }) { retailer in
                        RetailerChoiceCard(
                            retailer: retailer,
                            selected: appModel.selectedRetailer == retailer
                        ) {
                            appModel.startRetailerGuide(retailer)
                        }
                    }

                    if appModel.selectedRetailer == .walmart {
                        storeChoices
                    } else {
                        InfoBanner(
                            symbol: "location.viewfinder",
                            title: "Choose your store in \(appModel.retailerConfiguration.displayName)",
                            message: "SmartCart matches the retailer catalog. The retailer-owned page confirms your local store, live availability, and fulfillment.",
                            color: .red
                        )
                    }

                    fulfillmentChoice(appModel: $appModel)

                    SectionHeader(
                        title: "Shopping preferences",
                        subtitle: "Hard dietary and organic rules still block unsuitable products"
                    )
                    ShoppingPreferenceControls()

                    retailerSetup
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .smartCartBackground()
            .navigationTitle("Trip Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onConfirm()
                        dismiss()
                    }
                        .disabled(appModel.selectedStores.isEmpty)
                        .accessibilityIdentifier("recipe-ready-settings-done")
                }
            }
            .sheet(isPresented: $showRetailerSetupSafari) {
                RetailerSafariSheet(
                    url: appModel.retailerSetupURL(),
                    configuration: appModel.retailerConfiguration
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var storeChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Store", subtitle: "Used as the matching context")
            ForEach(appModel.storesForSelectedRetailer) { store in
                Button {
                    appModel.selectStore(store)
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: appModel.selectedStoreIDs.contains(store.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(appModel.selectedStoreIDs.contains(store.id) ? SmartCartTheme.green : SmartCartTheme.secondaryInk)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(SmartCartTheme.navy)
                            Text("\(store.address) · \(store.distance, specifier: "%.1f") mi")
                                .font(.caption)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .smartCartCard(padding: 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("\(store.name), \(store.address), \(store.distance.formatted(.number.precision(.fractionLength(1)))) miles")
                .accessibilityValue(appModel.selectedStoreIDs.contains(store.id) ? "Selected" : "Not selected")
                .accessibilityAddTraits(appModel.selectedStoreIDs.contains(store.id) ? .isSelected : [])
            }
        }
    }

    private func fulfillmentChoice(appModel: Bindable<AppModel>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Fulfillment", subtitle: "The retailer confirms live availability and final options")
            if dynamicTypeSize.isAccessibilitySize {
                Picker("Fulfillment mode", selection: appModel.fulfillmentMode) {
                    ForEach(FulfillmentMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SmartCartTheme.minimumHitTargetDimension,
                    alignment: .leading
                )
                .accessibilityIdentifier("recipe-ready-fulfillment")
            } else {
                Picker("Fulfillment mode", selection: appModel.fulfillmentMode) {
                    ForEach(FulfillmentMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("recipe-ready-fulfillment")
            }
        }
        .smartCartCard()
    }

    private var retailerSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appModel.retailerSetupIsComplete {
                Label("\(appModel.retailerConfiguration.displayName) setup marked ready", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.green)
                    .accessibilityHint("This is your saved confirmation. SmartCart cannot verify retailer sign-in or list setup.")
            } else {
                SectionHeader(
                    title: "One-time retailer setup",
                    subtitle: "Sign-in and list setup stay on the retailer-owned page"
                )

                Button {
                    appModel.recordRetailerSetupStarted()
                    showRetailerSetupSafari = true
                } label: {
                    HStack {
                        Text("Open \(appModel.retailerConfiguration.displayName) setup")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(BlueButtonStyle())
                .accessibilityIdentifier("recipe-ready-retailer-setup-open")

                Button {
                    appModel.completeRetailerSetup()
                    onConfirm()
                    dismiss()
                } label: {
                    Label("I’m signed in and my list is ready", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("recipe-ready-retailer-setup-complete")
                .accessibilityHint("Records your confirmation on this device. SmartCart cannot verify retailer sign-in or list setup.")
            }

            Text("SmartCart cannot see retailer credentials, verify sign-in, create a list or cart, or know what happens on a retailer page.")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .smartCartCard()
    }
}

private struct PantryIngredientRow: View {
    @Binding var ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: ingredient.category.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(ingredient.pantryState.color)
                    .frame(width: 40, height: 40)
                    .background(ingredient.pantryState.color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient.preferredProductName ?? ingredient.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                        .lineLimit(2)
                    Text(
                        ingredient.preferredProductName == nil
                            ? ingredient.displayQuantity
                            : "\(ingredient.displayQuantity) · Recipe calls for \(ingredient.name)"
                    )
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }

                Spacer(minLength: 6)

                Menu {
                    ForEach(PantryState.allCases) { state in
                        Button {
                            ingredient.pantryState = state
                            ingredient.pantryDecision = state == .needToBuy ? .buyFull : (state == .haveEnough ? .useAvailable : .review)
                        } label: {
                            Label(state.rawValue, systemImage: state.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(ingredient.pantryState.shortLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ingredient.pantryState.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ingredient.pantryState.color.opacity(0.09))
                    .clipShape(Capsule())
                }
            }

            if let suggestion = ingredient.pantrySuggestion {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Found in pantry: \(suggestion.pantryItemName)", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.purple)
                    Text(suggestionText(suggestion))
                        .font(.caption2)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                    HStack(spacing: 8) {
                        Button(suggestion.coverage == .partial ? "Use + buy remainder" : "Use pantry") {
                            ingredient.pantryDecision = .useAvailable
                            ingredient.pantryState = .runningLow
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SmartCartTheme.green)
                        .foregroundStyle(SmartCartTheme.onAccent)
                        Button("Buy full") {
                            ingredient.pantryDecision = .buyFull
                            ingredient.pantryState = .needToBuy
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.bold))
                }
                .padding(10)
                .background(SmartCartTheme.purple.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(13)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SmartCartTheme.border, lineWidth: 1)
        }
    }

    private func suggestionText(_ suggestion: PantrySuggestion) -> String {
        switch suggestion.coverage {
        case .full:
            "Saved stock appears sufficient. SmartCart will skip it only after you choose Use pantry."
        case .partial:
            "Saved stock covers \(Ingredient.quantityText(suggestion.availableQuantity, unit: suggestion.availableUnit)); choose Use to buy only the remainder."
        case .possible:
            "The name matches, but package units are not comparable. You decide whether to use it or buy the full amount."
        }
    }
}

struct RetailerSelectionView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 5,
                    total: 6,
                    eyebrow: "Shopping Trip",
                    title: "Choose where to shop",
                    message: "Choose a retailer. SmartCart uses the same matching and pantry workflow for each trip."
                )

                retailerCards
                retailerContext
                handoffDisclosure
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .smartCartBackground()
        .navigationTitle("Choose retailer")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.prepareRetailerSafariWorkflow()
                    appModel.continueTo(.matching)
                } label: {
                    HStack {
                        Text("Match \(appModel.retailerConfiguration.displayName) products")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appModel.selectedStores.isEmpty)
            }
        }
        .onAppear {
            appModel.prepareRetailerSafariWorkflow()
        }
    }

    private var retailerCards: some View {
        VStack(spacing: 12) {
            ForEach(ShoppingRetailer.allCases) { retailer in
                RetailerChoiceCard(
                    retailer: retailer,
                    selected: appModel.selectedRetailer == retailer
                ) {
                    appModel.startRetailerGuide(retailer)
                }
            }

            MoreRetailersCard()
        }
    }

    @ViewBuilder
    private var retailerContext: some View {
        if appModel.selectedRetailer == .walmart {
            VStack(alignment: .leading, spacing: 10) {
                locationField
                SectionHeader(
                    title: "Walmart matching location",
                    subtitle: "One location keeps seeded product records clear"
                )
                ForEach(appModel.storesForSelectedRetailer) { store in
                    StoreContextCard(
                        store: store,
                        selected: appModel.selectedStoreIDs.contains(store.id)
                    ) {
                        appModel.selectStore(store)
                    }
                }
            }
        } else {
            InfoBanner(
                symbol: "location.viewfinder",
                title: "Choose your store in Target",
                message: "SmartCart matches Target catalog records now. Target confirms your local store, live availability, and fulfillment options after the Shopping Trip opens.",
                color: .red
            )
        }
    }

    private var locationField: some View {
        HStack(spacing: 11) {
            Image(systemName: "location.fill")
                .foregroundStyle(SmartCartTheme.green)
            TextField("ZIP code", text: Bindable(appModel).zipCode)
                .keyboardType(.numberPad)
                .textContentType(.postalCode)
            Text("Matching context")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .smartField()
    }

    private var handoffDisclosure: some View {
        InfoBanner(
            symbol: "safari.fill",
            title: "You finish at \(appModel.retailerConfiguration.displayName)",
            message: "SmartCart opens exact products or clearly labeled searches. \(appModel.retailerConfiguration.displayName) controls sign-in, live inventory, final prices, list or cart actions, fulfillment, payment, and checkout.",
            color: appModel.selectedRetailer == .walmart ? SmartCartTheme.walmartBlue : .red
        )
    }
}

private struct RetailerChoiceCard: View {
    let retailer: ShoppingRetailer
    let selected: Bool
    let action: () -> Void

    private var configuration: RetailerGuideConfiguration { retailer.configuration }

    private var brandColor: Color {
        switch retailer {
        case .walmart: SmartCartTheme.walmartBlue
        case .target: .red
        case .kroger: Color(red: 0.08, green: 0.34, blue: 0.67)
        }
    }

    private var brandMark: String {
        switch retailer {
        case .walmart: "sparkle"
        case .target: "circle.circle.fill"
        case .kroger: "K"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                brandIcon

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(configuration.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(SmartCartTheme.navy)
                        Spacer(minLength: 8)
                        Text(configuration.isAvailable ? configuration.guideLabel : "Coming Soon")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(configuration.isAvailable ? brandColor : SmartCartTheme.mutedInk)
                    }

                    ForEach(configuration.cardHighlights, id: \.self) { highlight in
                        Label(
                            highlight,
                            systemImage: configuration.isAvailable ? "checkmark" : "circle.fill"
                        )
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(SmartCartTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? brandColor : SmartCartTheme.border, lineWidth: selected ? 2 : 1)
            }
            .opacity(configuration.isAvailable ? 1 : 0.7)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!configuration.isAvailable)
        .accessibilityIdentifier("retailer-card-\(retailer.rawValue)")
        .accessibilityLabel(retailerAccessibilityLabel)
        .accessibilityValue(configuration.isAvailable ? (selected ? "Selected" : "Not selected") : "Unavailable")
        .accessibilityHint(configuration.isAvailable ? "Selects this retailer for the Shopping Trip. SmartCart does not connect to or inspect your retailer account." : "This retailer is coming soon.")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var retailerAccessibilityLabel: String {
        let status = configuration.isAvailable ? configuration.guideLabel : "Coming Soon"
        return ([configuration.displayName, status] + configuration.cardHighlights).joined(separator: ", ")
    }

    @ViewBuilder
    private var brandIcon: some View {
        if retailer == .kroger {
            Text(brandMark)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(brandColor)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else {
            Image(systemName: brandMark)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(brandColor)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

private struct StoreContextCard: View {
    let store: RetailerStore
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "storefront.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(selected ? SmartCartTheme.onAccent : SmartCartTheme.green)
                    .frame(width: 38, height: 38)
                    .background(selected ? SmartCartTheme.green : SmartCartTheme.herbLight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("\(store.distance.formatted(.number.precision(.fractionLength(1)))) mi · \(store.address)")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? SmartCartTheme.green : SmartCartTheme.borderStrong)
            }
            .padding(13)
            .background(SmartCartTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(selected ? SmartCartTheme.borderStrong : SmartCartTheme.border, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct MoreRetailersCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "ellipsis")
                .font(.title2.bold())
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .frame(width: 48, height: 48)
                .background(SmartCartTheme.canvasRaise)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("More retailers")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Coming Soon")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.mutedInk)
            }
            Spacer()
        }
        .padding(16)
        .background(SmartCartTheme.paper.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SmartCartTheme.border, lineWidth: 1)
        }
    }
}

struct PantryDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pantrySheet: PantrySheetDestination?
    @State private var manualPantryName = ""
    @State private var searchText = ""
    @State private var scannerExpanded =
        ProcessInfo.processInfo.environment["SMARTCART_PANTRY_DRAWER"] == "scanner"
    @State private var scannerDrag: CGFloat = 0

    private let collapsedDrawerHeight: CGFloat = 92

    var body: some View {
        GeometryReader { geometry in
            let drawerHeight = max(420, geometry.size.height - 88)
            let collapsedOffset = drawerHeight - collapsedDrawerHeight

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 18)

                    inventoryContents
                }

                scannerDrawer(height: drawerHeight, collapsedOffset: collapsedOffset)
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(
                                height: drawerHeight - scannerDrawerOffset(
                                    collapsedOffset: collapsedOffset
                                )
                            )
                    }
                    .offset(y: scannerDrawerOffset(collapsedOffset: collapsedOffset))
            }
        }
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: scannerExpanded)
        .sheet(item: $pantrySheet) { destination in
            switch destination {
            case .editor(let item):
                PantryInventoryEditor(item: item) { edited in
                    appModel.updatePantryItem(edited)
                }
            }
        }
        .domainUndoOverlay()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pantry")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(SmartCartTheme.navy)
            Text("Save favorite products and track what you have on hand.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func scannerDrawer(height: CGFloat, collapsedOffset: CGFloat) -> some View {
        let joinOverlap: CGFloat = scannerExpanded ? 2 : 0

        return VStack(spacing: 0) {
            scannerDrawerHandle(collapsedOffset: collapsedOffset)

            if scannerExpanded {
                BarcodeScannerSheet(
                    embedded: true,
                    onComplete: { scannerExpanded = false }
                )
                .transition(.opacity)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background {
            ZStack(alignment: .top) {
                SmartCartTheme.scannerSurface
                    .padding(.top, collapsedDrawerHeight - joinOverlap)
                SmartCartDrawerGlassSurface(
                    shape: PantryPullUpShape(),
                    darkness: 0.28
                )
                    .frame(height: collapsedDrawerHeight)
            }
        }
        .clipShape(PantryPullUpShape())
        .overlay(alignment: .top) {
            PantryPullUpShape()
                .stroke(SmartCartTheme.borderStrong.opacity(0.72), lineWidth: 1)
                .frame(height: collapsedDrawerHeight)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(height: collapsedDrawerHeight - joinOverlap)
                }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    private func scannerDrawerHandle(collapsedOffset: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: scannerExpanded ? "chevron.compact.down" : "chevron.compact.up")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(SmartCartTheme.green)
                .frame(height: 35)

            HStack(spacing: 9) {
                Label("Scan an item", systemImage: "barcode.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.ink)

                Spacer()

                Text(scannerExpanded ? "Swipe down to hide" : "Swipe up for camera or code")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .frame(height: collapsedDrawerHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            settleScannerDrawer(expanded: !scannerExpanded)
        }
        .gesture(scannerDragGesture(collapsedOffset: collapsedOffset))
        .accessibilityLabel("Barcode scanner drawer")
        .accessibilityValue(scannerExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(scannerExpanded ? "Swipe down to hide the scanner" : "Swipe up to show the scanner")
        .accessibilityAddTraits(.isButton)
    }

    private var inventoryContents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Pantry inventory",
                    subtitle: "Saved products can personalize new recipes"
                )

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                    TextField("Search your pantry", text: $searchText)
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .smartField()

                HStack(spacing: 9) {
                    TextField("Add an item manually", text: $manualPantryName)
                        .smartField()
                    Button {
                        appModel.addManualPantryItem(name: manualPantryName)
                        manualPantryName = ""
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.bold())
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(manualPantryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if appModel.pantryInventory.isEmpty {
                    InfoBanner(
                        symbol: "cabinet.fill",
                        title: "No saved pantry items",
                        message: "Scan a barcode or add an item. Unknown UPCs are retained locally for later catalog matching.",
                        color: SmartCartTheme.walmartBlue
                    )
                } else if filteredInventory.isEmpty {
                    InfoBanner(
                        symbol: "magnifyingglass",
                        title: "No matches for “\(searchText)”",
                        message: "Try a shorter search, or add it as a new item above.",
                        color: SmartCartTheme.amber
                    )
                } else {
                    ForEach(filteredInventory) { item in
                        PantryInlineRow(
                            item: item,
                            onUpdate: { appModel.updatePantryItem($0) },
                            onDelete: {
                                guard let index = appModel.pantryInventory.firstIndex(where: { $0.id == item.id }) else { return }
                                appModel.removePantryItems(at: IndexSet(integer: index))
                            },
                            onDetails: { pantrySheet = .editor(item) }
                        )
                    }

                    Text("Tap a name or amount to edit it in place · long-press a row for package details")
                        .font(.caption2)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, collapsedDrawerHeight + 34)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func scannerDrawerOffset(collapsedOffset: CGFloat) -> CGFloat {
        let restingOffset = scannerExpanded ? 0 : collapsedOffset
        return min(max(restingOffset + scannerDrag, 0), collapsedOffset)
    }

    private func scannerDragGesture(collapsedOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    scannerDrag = value.translation.height
                }
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.height
                let decisiveDistance = min(96, collapsedOffset * 0.22)
                let shouldExpand = scannerExpanded
                    ? projected <= decisiveDistance
                    : projected < -decisiveDistance
                settleScannerDrawer(expanded: shouldExpand)
            }
    }

    private func settleScannerDrawer(expanded: Bool) {
        let animation = Animation.spring(response: 0.42, dampingFraction: 0.86)
        withAnimation(reduceMotion ? nil : animation) {
            scannerExpanded = expanded
            scannerDrag = 0
        }
    }

    private var filteredInventory: [PantryInventoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return appModel.pantryInventory }
        return appModel.pantryInventory.filter {
            $0.name.lowercased().contains(query) || $0.brand.lowercased().contains(query)
        }
    }

}

/// A drawer with a centered half-circle rising above its top edge. The curved
/// handle makes the vertical scanner gesture visible without looking like a
/// second tab bar or a horizontal page control.
private struct PantryPullUpShape: Shape {
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
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: top + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: top),
            control: CGPoint(x: rect.minX, y: top)
        )
        path.closeSubpath()
        return path
    }
}

private enum PantrySheetDestination: Identifiable {
    case editor(PantryInventoryItem)

    var id: String {
        switch self {
        case .editor(let item): "editor-\(item.id.uuidString)"
        }
    }
}

/// One saved pantry item with the name and amount editable directly in the
/// row — no separate editor sheet for the common corrections.
private struct PantryInlineRow: View {
    let item: PantryInventoryItem
    let onUpdate: (PantryInventoryItem) -> Void
    let onDelete: () -> Void
    let onDetails: () -> Void

    @State private var name: String
    @State private var quantityText: String
    @FocusState private var nameFocused: Bool
    @FocusState private var quantityFocused: Bool

    init(
        item: PantryInventoryItem,
        onUpdate: @escaping (PantryInventoryItem) -> Void,
        onDelete: @escaping () -> Void,
        onDetails: @escaping () -> Void
    ) {
        self.item = item
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onDetails = onDetails
        _name = State(initialValue: item.name)
        _quantityText = State(initialValue: item.packageCount.formatted())
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.source == .barcode ? "barcode" : "cabinet.fill")
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 36, height: 36)
                .background(SmartCartTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                TextField("Item name", text: $name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                Text(item.brand.isEmpty ? item.source.label : item.brand)
                    .font(.caption2)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .lineLimit(1)
                if let ingredientName = PantryMatchingService.recipeIngredientName(for: item) {
                    Label("Preferred for \(ingredientName)", systemImage: "heart.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SmartCartTheme.green)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 7) {
                quantityButton("minus") {
                    var edited = item
                    edited.setPackageCount(max(0, edited.packageCount - 1))
                    onUpdate(edited)
                }
                VStack(spacing: 0) {
                    TextField("Amount", text: $quantityText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($quantityFocused)
                        .onSubmit(commitQuantity)
                        .onChange(of: quantityFocused) { _, focused in
                            if !focused { commitQuantity() }
                        }
                    Text("pkg")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .frame(minWidth: 34)
                quantityButton("plus") {
                    var edited = item
                    edited.addPackages(1)
                    onUpdate(edited)
                }
            }

        }
        .smartCartCard(padding: 12)
        .contextMenu {
            Button("Package details", systemImage: "shippingbox") { onDetails() }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
        .onChange(of: item.name) { _, newValue in
            if !nameFocused { name = newValue }
        }
        .onChange(of: item.packageCount) { _, newValue in
            if !quantityFocused { quantityText = newValue.formatted() }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: item.packageCount)
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else {
            name = item.name
            return
        }
        var edited = item
        edited.name = trimmed
        edited.requiresUserNaming = false
        onUpdate(edited)
    }

    private func commitQuantity() {
        let normalized = quantityText.replacingOccurrences(of: ",", with: "")
        guard let quantity = Double(normalized), quantity >= 0 else {
            quantityText = item.packageCount.formatted()
            return
        }
        guard quantity != item.packageCount else {
            quantityText = item.packageCount.formatted()
            return
        }
        var edited = item
        edited.setPackageCount(quantity)
        onUpdate(edited)
    }

    private func quantityButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 28, height: 28)
                .background(SmartCartTheme.herbLight)
                .clipShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(symbol == "plus" ? "Increase \(item.name) amount" : "Decrease \(item.name) amount")
    }
}

private struct PantryInventoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PantryInventoryItem
    let onSave: (PantryInventoryItem) -> Void

    init(item: PantryInventoryItem, onSave: @escaping (PantryInventoryItem) -> Void) {
        var initialDraft = item
        if initialDraft.preferredIngredientName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            initialDraft.preferredIngredientName = PantryMatchingService.recipeIngredientName(for: item)
        }
        if initialDraft.isRecipeFavorite == nil {
            initialDraft.isRecipeFavorite = initialDraft.preferredIngredientName != nil
        }
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Required product name", text: $draft.name)
                    TextField("Brand (optional)", text: $draft.brand)
                    if let upc = draft.upc {
                        LabeledContent("Barcode", value: upc)
                    }
                    if draft.requiresUserNaming == true {
                        Label("Name this product before pantry matching can use it", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.amber)
                    }
                }

                Section("Recipe favorite") {
                    Toggle("Use as a recipe favorite", isOn: Binding(
                        get: { draft.isRecipeFavorite == true },
                        set: { isFavorite in
                            draft.isRecipeFavorite = isFavorite
                            if !isFavorite { draft.preferredIngredientName = nil }
                        }
                    ))
                    if draft.isRecipeFavorite == true {
                        TextField(
                            "Ingredient recipes call this, such as coffee",
                            text: Binding(
                                get: { draft.preferredIngredientName ?? "" },
                                set: { value in
                                    draft.preferredIngredientName = value.isEmpty ? nil : value
                                }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        Text("When a new recipe uses this ingredient, SmartCart keeps the recipe measurement but prefers \(PantryMatchingService.preferredProductDisplayName(for: draft)).")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                }

                Section("Inventory") {
                    TextField(
                        "Packages on hand",
                        value: Binding(
                            get: { draft.packageCount },
                            set: { draft.setPackageCount($0) }
                        ),
                        format: .number
                    )
                        .keyboardType(.decimalPad)
                    TextField(
                        "Amount per package (optional)",
                        value: $draft.packageSize,
                        format: .number
                    )
                    .keyboardType(.decimalPad)
                    TextField(
                        "Unit, such as cup, oz, g",
                        text: Binding(
                            get: { draft.packageUnit ?? "" },
                            set: { draft.packageUnit = $0.isEmpty ? nil : $0 }
                        )
                    )
                    TextField("Remaining amount", value: $draft.remainingAmount, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Remaining unit", text: $draft.remainingUnit)
                }

                Section {
                    Text("When a recipe is imported, SmartCart compares this name and saved amount with each ingredient. A match is always shown for confirmation before anything is skipped.")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
            .navigationTitle("Edit pantry item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.preferredIngredientName = draft.preferredIngredientName?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if draft.preferredIngredientName?.isEmpty == true {
                            draft.preferredIngredientName = nil
                        }
                        draft.requiresUserNaming = draft.name.isEmpty || draft.name == "Unknown Product"
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(
                        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            (draft.isRecipeFavorite == true &&
                                draft.preferredIngredientName?
                                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    )
                }
            }
        }
    }
}

struct StoreDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showRetailerSafari = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Retailers")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Choose where SmartCart should match this trip")
                        .font(.subheadline)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(ShoppingRetailer.allCases) { retailer in
                        RetailerChoiceCard(
                            retailer: retailer,
                            selected: appModel.selectedRetailer == retailer
                        ) {
                            appModel.startRetailerGuide(retailer)
                        }
                    }
                    MoreRetailersCard()
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "storefront.fill")
                            .font(.title2.bold())
                            .foregroundStyle(SmartCartTheme.green)
                            .frame(width: 56, height: 56)
                            .background(SmartCartTheme.herbLight)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Selected retailer")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SmartCartTheme.green)
                                .textCase(.uppercase)
                            Text(appModel.retailerConfiguration.displayName)
                                .font(.headline)
                                .foregroundStyle(SmartCartTheme.navy)
                            Text(appModel.primaryStore.address)
                                .font(.caption)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                .lineLimit(2)
                        }
                    }

                    if appModel.selectedRetailer == .walmart {
                        ForEach(appModel.storesForSelectedRetailer) { store in
                            Button {
                                appModel.selectStore(store)
                            } label: {
                                HStack {
                                    Image(systemName: appModel.selectedStoreIDs.contains(store.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(appModel.selectedStoreIDs.contains(store.id) ? SmartCartTheme.green : SmartCartTheme.border)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(store.name)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(SmartCartTheme.navy)
                                        Text("\(store.distance, specifier: "%.1f") mi · \(store.format)")
                                            .font(.caption)
                                            .foregroundStyle(SmartCartTheme.secondaryInk)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Label(
                            "Target confirms your local store and fulfillment options after Safari opens.",
                            systemImage: "location.viewfinder"
                        )
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                }
                .smartCartCard()

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        title: "Open in Safari",
                        subtitle: "SmartCart does not connect to a retailer account"
                    )

                    Button {
                        showRetailerSafari = true
                    } label: {
                        HStack {
                            Label("Open \(appModel.retailerConfiguration.displayName) in Safari", systemImage: "safari.fill")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .buttonStyle(BlueButtonStyle())
                }
                .smartCartCard()

                InfoBanner(
                    symbol: "building.columns.fill",
                    title: "\(appModel.retailerConfiguration.displayName) owns the transaction",
                    message: "SmartCart opens exact product pages or clearly labeled searches. The retailer controls sign-in, live inventory, final price, list or cart actions, fulfillment, substitutions, payment, and checkout.",
                    color: appModel.selectedRetailer == .walmart ? SmartCartTheme.walmartBlue : .red
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            appModel.prepareRetailerSafariWorkflow()
        }
        .sheet(isPresented: $showRetailerSafari) {
            RetailerSafariSheet(
                url: appModel.retailerURL(),
                configuration: appModel.retailerConfiguration
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
