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
                    Text(ingredient.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                        .lineLimit(1)
                    Text(ingredient.displayQuantity)
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

struct CommerceRouteSelectionView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 5,
                    total: 6,
                    eyebrow: "Shopping route",
                    title: "How should SmartCart hand off your list?",
                    message: "Choose the commerce route first. Stores, live products, fulfillment, and checkout remain with the selected retailer service."
                )

                locationField
                shoppingRouteCards

                switch appModel.shoppingRoute {
                case .instacart:
                    instacartPreferences
                    capabilityDisclosure
                case .walmartDirect:
                    walmartStoreCards
                    walmartFulfillment
                case .otherRetailerLinks:
                    InfoBanner(
                        symbol: "link.circle.fill",
                        title: "Links only",
                        message: "Other retailer destinations do not receive a SmartCart manifest in this build. No cart, live price, availability, or checkout connection is implied.",
                        color: SmartCartTheme.amber
                    )
                }
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .smartCartBackground()
        .navigationTitle("Shopping route")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    if appModel.shoppingRoute == .otherRetailerLinks {
                        appModel.continueTo(.shoppingList)
                    } else {
                        appModel.continueTo(.matching)
                    }
                } label: {
                    HStack {
                        Text(primaryButtonTitle)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appModel.shoppingRoute == .walmartDirect && appModel.selectedStores.isEmpty)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch appModel.shoppingRoute {
        case .instacart: "Build shopping list"
        case .walmartDirect: "Match Walmart products"
        case .otherRetailerLinks: "Review link options"
        }
    }

    private var locationField: some View {
        HStack(spacing: 11) {
            Image(systemName: "location.fill")
                .foregroundStyle(SmartCartTheme.green)
            TextField("ZIP code", text: Bindable(appModel).zipCode)
                .keyboardType(.numberPad)
                .textContentType(.postalCode)
            Text("Used for nearby retailers")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .smartField()
    }

    private var shoppingRouteCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Shopping route", subtitle: "Instacart is a service route, not a grocery store")
            ForEach(ShoppingRoutePreference.allCases) { route in
                selectionCard(
                    title: route.title,
                    subtitle: route.subtitle,
                    symbol: route.symbol,
                    selected: appModel.shoppingRoute == route
                ) {
                    appModel.shoppingRoute = route
                }
            }
        }
    }

    private var instacartPreferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Instacart preferences",
                subtitle: "Advisory until Instacart confirms nearby options"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("PREFERRED RETAILER")
                    .smartEyebrow(SmartCartTheme.mutedInk)
                ForEach(InstacartRetailerPreference.allCases) { retailer in
                    selectionCard(
                        title: retailer.label,
                        subtitle: retailer == .bestAvailable
                            ? "Let Instacart choose from nearby availability."
                            : "Requested where the retailer is available near \(appModel.zipCode).",
                        symbol: "storefront",
                        selected: appModel.instacartRetailerPreference == retailer
                    ) {
                        appModel.instacartRetailerPreference = retailer
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("FULFILLMENT PREFERENCE")
                    .smartEyebrow(SmartCartTheme.mutedInk)
                ForEach(CommerceFulfillmentPreference.allCases) { preference in
                    selectionCard(
                        title: preference.label,
                        subtitle: "Instacart confirms available pickup or delivery options.",
                        symbol: preference == .pickup ? "car.fill" : preference == .delivery ? "house.fill" : "slider.horizontal.3",
                        selected: appModel.commerceFulfillmentPreference == preference
                    ) {
                        appModel.commerceFulfillmentPreference = preference
                    }
                }
            }
        }
        .smartCartCard()
    }

    private var capabilityDisclosure: some View {
        let capabilities = appModel.activeCommerceCapabilities
        return InfoBanner(
            symbol: "checkmark.shield.fill",
            title: "Clear ownership",
            message: capabilities.embeddedCheckout
                ? "SmartCart prepares the list and the approved provider can complete checkout in-app."
                : "SmartCart prepares the list. Instacart confirms live products, prices, availability, substitutions, store, pickup or delivery, sign-in, payment, checkout, and order tracking.",
            color: SmartCartTheme.green
        )
    }

    private var walmartStoreCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Walmart location", subtitle: "Choose one store for the guided-link route")
            ForEach(appModel.stores) { store in
                selectionCard(
                    title: store.name,
                    subtitle: "\(store.distance.formatted(.number.precision(.fractionLength(1)))) mi · \(store.address)",
                    symbol: "storefront.fill",
                    selected: appModel.selectedStoreIDs.contains(store.id)
                ) {
                    appModel.selectStore(store)
                }
            }
        }
    }

    private var walmartFulfillment: some View {
        InfoBanner(
            symbol: "car.fill",
            title: "Pickup preference",
            message: "SmartCart remembers the preference. Walmart confirms inventory, substitutions, payment, and the actual pickup reservation.",
            color: SmartCartTheme.walmartBlue
        )
    }

    private func selectionCard(
        title: String,
        subtitle: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(selected ? SmartCartTheme.onAccent : SmartCartTheme.green)
                    .frame(width: 38, height: 38)
                    .background(selected ? SmartCartTheme.green : SmartCartTheme.herbLight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(subtitle)
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

struct StoreSelectionView: View {
    @Environment(AppModel.self) private var appModel

    private let pickupDays = ["Today", "Tomorrow", "Saturday"]
    private let pickupTimes = ["4:30–5:30 PM", "5:00–6:00 PM", "6:30–7:30 PM", "9:00–10:00 AM"]

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 5,
                    total: 6,
                    eyebrow: "Select store",
                    title: "Where do you want to shop?",
                    message: appModel.featureFlags.advancedToolsEnabled
                        ? "Choose a Walmart store. Multiple-stop planning is visible only as an experimental tool."
                        : "Choose one Walmart store for this public-beta shopping manifest."
                )

                locationField
                if appModel.featureFlags.advancedToolsEnabled {
                    strategyPicker
                } else {
                    StatusPill(
                        title: "Single-store beta",
                        symbol: "storefront.fill",
                        color: SmartCartTheme.walmartBlue
                    )
                }
                storeCards
                fulfillmentSection

                InfoBanner(
                    symbol: "info.circle.fill",
                    title: "Pickup is pre-planned, not secretly booked",
                    message: "SmartCart remembers your preferred window and hands you to Walmart to confirm inventory, substitutions, payment, and the actual reservation.",
                    color: SmartCartTheme.walmartBlue
                )
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .smartCartBackground()
        .navigationTitle("Select store")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.continueTo(.matching)
                } label: {
                    HStack {
                        Text("Match products")
                        Spacer()
                        Text(appModel.storeStrategy == .oneStore ? "1 store" : "\(appModel.selectedStores.count) stores")
                            .font(.caption.weight(.bold))
                            .opacity(0.82)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appModel.selectedStores.isEmpty)
            }
        }
        .onChange(of: appModel.storeStrategy) { _, newValue in
            appModel.setStoreStrategy(newValue)
        }
    }

    private var locationField: some View {
        HStack(spacing: 11) {
            Image(systemName: "location.fill")
                .foregroundStyle(SmartCartTheme.walmartBlue)
            TextField("ZIP code", text: Bindable(appModel).zipCode)
                .keyboardType(.numberPad)
            Button("Use location") {
                appModel.showToast("Using nearby demo stores for \(appModel.zipCode)")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(SmartCartTheme.walmartBlue)
        }
        .smartField()
    }

    private var strategyPicker: some View {
        @Bindable var appModel = appModel

        return VStack(alignment: .leading, spacing: 9) {
            Text("SHOPPING PLAN")
                .smartEyebrow(SmartCartTheme.mutedInk)
            Picker("Shopping plan", selection: $appModel.storeStrategy) {
                ForEach(StoreStrategy.allCases) { strategy in
                    Text(strategy.rawValue).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var storeCards: some View {
        VStack(spacing: 11) {
            ForEach(appModel.stores) { store in
                let selected = appModel.selectedStoreIDs.contains(store.id)
                Button {
                    appModel.selectStore(store)
                } label: {
                    HStack(alignment: .top, spacing: 13) {
                        StoreMark(size: 48)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(store.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SmartCartTheme.navy)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected ? SmartCartTheme.green : SmartCartTheme.border)
                            }
                            Text("\(store.distance, specifier: "%.1f") mi · \(store.address)")
                                .font(.caption)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                if store.supportsPickup {
                                    StatusPill(title: "Pickup", symbol: "car.fill", color: SmartCartTheme.green)
                                }
                                if appModel.featureFlags.advancedToolsEnabled, store.supportsDelivery {
                                    StatusPill(title: "Delivery", symbol: "house.fill", color: SmartCartTheme.walmartBlue)
                                }
                            }
                            .padding(.top, 3)
                        }
                    }
                    .padding(13)
                    .background(SmartCartTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selected ? SmartCartTheme.borderStrong : SmartCartTheme.border, lineWidth: selected ? 1.6 : 1)
                    }
                    .shadow(color: selected ? SmartCartTheme.mintGlow : .clear, radius: 14)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var fulfillmentSection: some View {
        @Bindable var appModel = appModel

        return VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "Fulfillment", subtitle: "Pre-pick a plan before retailer checkout")

            if appModel.featureFlags.advancedToolsEnabled {
                Picker("Fulfillment", selection: $appModel.fulfillmentMode) {
                    ForEach(FulfillmentMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                HStack {
                    Label("Pickup preference", systemImage: "car.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                    Spacer()
                    Text("Retailer confirms")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.walmartBlue)
                }
            }

            if appModel.fulfillmentMode == .pickup {
                VStack(alignment: .leading, spacing: 11) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(pickupDays, id: \.self) { day in
                                ChoiceChip(title: day, selected: appModel.pickupDay == day) {
                                    appModel.pickupDay = day
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(pickupTimes, id: \.self) { time in
                            ChoiceChip(title: time, selected: appModel.pickupTime == time) {
                                appModel.pickupTime = time
                            }
                        }
                    }
                }
            } else {
                Text("Choose or link a delivery partner from the Store tab. SmartCart prepares the list; the partner confirms availability and checkout.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SmartCartTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .smartCartCard()
    }
}

private struct ChoiceChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? SmartCartTheme.onAccent : SmartCartTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(selected ? SmartCartTheme.green : SmartCartTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Color.clear : SmartCartTheme.border, lineWidth: 1)
                }
                .shadow(color: selected ? SmartCartTheme.mintGlow : .clear, radius: 8)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PantryDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pantrySheet: PantrySheetDestination?
    @State private var manualPantryName = ""
    @State private var searchText = ""
    @State private var scannerExpanded =
        ProcessInfo.processInfo.environment["SMARTCART_PANTRY_DRAWER"] == "scanner"
    @GestureState private var scannerDrag: CGFloat = 0

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
                    .offset(y: scannerDrawerOffset(collapsedOffset: collapsedOffset))
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.86),
                        value: scannerExpanded
                    )
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pantry")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(SmartCartTheme.navy)
            Text("Search, rename, and adjust everything you have on hand.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func scannerDrawer(height: CGFloat, collapsedOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            scannerDrawerHandle(collapsedOffset: collapsedOffset)

            Divider()
                .overlay(SmartCartTheme.border)

            if scannerExpanded {
                BarcodeScannerSheet(embedded: true) {
                    scannerExpanded = false
                }
                .transition(.opacity)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(SmartCartTheme.scannerSurface)
        .clipShape(PantryPullUpShape())
        .overlay {
            PantryPullUpShape()
                .stroke(SmartCartTheme.borderStrong.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: -8)
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
            scannerExpanded.toggle()
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
                    subtitle: "Search and edit without leaving this screen"
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
        DragGesture(minimumDistance: 6)
            .updating($scannerDrag) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.height
                let decisiveDistance = min(96, collapsedOffset * 0.22)

                if scannerExpanded {
                    if projected > decisiveDistance {
                        scannerExpanded = false
                    }
                } else if projected < -decisiveDistance {
                    scannerExpanded = true
                }
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
        _quantityText = State(initialValue: item.quantity.formatted())
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
            }

            Spacer(minLength: 6)

            HStack(spacing: 7) {
                quantityButton("minus") {
                    var edited = item
                    edited.quantity = max(0, edited.quantity - 1)
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
                    Text(item.unit)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .frame(minWidth: 34)
                quantityButton("plus") {
                    var edited = item
                    edited.quantity += 1
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
        .onChange(of: item.quantity) { _, newValue in
            if !quantityFocused { quantityText = newValue.formatted() }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: item.quantity)
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
            quantityText = item.quantity.formatted()
            return
        }
        guard quantity != item.quantity else {
            quantityText = item.quantity.formatted()
            return
        }
        var edited = item
        edited.quantity = quantity
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
        _draft = State(initialValue: item)
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

                Section("Inventory") {
                    TextField("Packages on hand", value: $draft.quantity, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Package label", text: $draft.unit)
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
                        draft.requiresUserNaming = draft.name.isEmpty || draft.name == "Unknown Product"
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct StoreDashboardView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Store & handoff")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Choose stops, pickup, or a delivery partner")
                        .font(.subheadline)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        StoreMark(size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Preferred Walmart")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SmartCartTheme.green)
                                .textCase(.uppercase)
                            Text(appModel.primaryStore.name)
                                .font(.headline)
                                .foregroundStyle(SmartCartTheme.navy)
                            Text("\(appModel.primaryStore.distance, specifier: "%.1f") mi · \(appModel.selectedPickupSummary)")
                                .font(.caption)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                .lineLimit(1)
                        }
                    }

                    if appModel.featureFlags.advancedToolsEnabled {
                        Picker("Shopping plan", selection: $appModel.storeStrategy) {
                            ForEach(StoreStrategy.allCases) { strategy in
                                Text(strategy.rawValue).tag(strategy)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: appModel.storeStrategy) { _, newValue in
                            appModel.setStoreStrategy(newValue)
                        }
                    }

                    ForEach(appModel.stores) { store in
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
                }
                .smartCartCard()

                if appModel.featureFlags.advancedToolsEnabled {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionHeader(title: "Delivery providers", subtitle: "Experimental links; no basket is transferred")

                        ForEach(appModel.deliveryPartners) { partner in
                            Button {
                                appModel.linkDeliveryPartner(partner)
                                openURL(partner.url)
                            } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: partner.symbol)
                                        .font(.headline.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .background(partner.color)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(partner.name)
                                            .font(.headline)
                                            .foregroundStyle(SmartCartTheme.navy)
                                        Text(
                                            appModel.linkedDeliveryPartnerName == partner.name
                                                ? "Preferred provider"
                                                : "Visit delivery provider"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            appModel.linkedDeliveryPartnerName == partner.name
                                                ? SmartCartTheme.green
                                                : SmartCartTheme.secondaryInk
                                        )
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(SmartCartTheme.secondaryInk)
                                }
                                .smartCartCard(padding: 13)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }

                InfoBanner(
                    symbol: "building.columns.fill",
                    title: "Retailer adapter boundary",
                    message: "This build supports exact Walmart product links and guided handoff. It does not create carts, save wishlists, transfer delivery baskets, or reserve pickup.",
                    color: SmartCartTheme.walmartBlue
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}
