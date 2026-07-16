import SwiftUI

struct PantryCheckView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 3,
                    total: 5,
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
                    color: GatherTheme.purple
                )
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(GatherTheme.canvas)
        .navigationTitle("Pantry check")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.continueTo(.storeSelection)
                } label: {
                    HStack {
                        Text("Choose Walmart store")
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
                color: GatherTheme.walmartBlue
            )
            summaryMetric(
                value: "\(appModel.pantrySkipCount)",
                label: "Skipped",
                symbol: "checkmark.seal.fill",
                color: GatherTheme.green
            )
            summaryMetric(
                value: "\(appModel.activeRecipe.ingredients.filter { $0.pantryState == .runningLow }.count)",
                label: "Running low",
                symbol: "clock.fill",
                color: GatherTheme.amber
            )
        }
    }

    private func summaryMetric(value: String, label: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(GatherTheme.navy)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GatherTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
        }
    }

    private var quickActions: some View {
        ViewThatFits {
            HStack(spacing: 9) {
                Button("Buy everything") {
                    for index in appModel.activeRecipe.ingredients.indices where appModel.activeRecipe.ingredients[index].includeInList {
                        appModel.activeRecipe.ingredients[index].pantryState = .needToBuy
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Skip common staples") {
                    for index in appModel.activeRecipe.ingredients.indices {
                        let value = appModel.activeRecipe.ingredients[index].name.lowercased()
                        if value.contains("salt") || value.contains("pepper") || value.contains("water") {
                            appModel.activeRecipe.ingredients[index].pantryState = .haveEnough
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 9) {
                Button("Buy everything") {
                    for index in appModel.activeRecipe.ingredients.indices where appModel.activeRecipe.ingredients[index].includeInList {
                        appModel.activeRecipe.ingredients[index].pantryState = .needToBuy
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Skip common staples") {
                    for index in appModel.activeRecipe.ingredients.indices {
                        let value = appModel.activeRecipe.ingredients[index].name.lowercased()
                        if value.contains("salt") || value.contains("pepper") || value.contains("water") {
                            appModel.activeRecipe.ingredients[index].pantryState = .haveEnough
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
                    .foregroundStyle(GatherTheme.navy)
                    .lineLimit(1)
                Text(ingredient.displayQuantity)
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }

            Spacer(minLength: 6)

            Menu {
                ForEach(PantryState.allCases) { state in
                    Button {
                        ingredient.pantryState = state
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
        .padding(13)
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
        }
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
                    step: 4,
                    total: 5,
                    eyebrow: "Select store",
                    title: "Where do you want to shop?",
                    message: "Choose one Walmart stop or split the prototype list across multiple nearby Walmart locations."
                )

                locationField
                strategyPicker
                storeCards
                fulfillmentSection

                InfoBanner(
                    symbol: "info.circle.fill",
                    title: "Pickup is pre-planned, not secretly booked",
                    message: "SmartCart remembers your preferred window and hands you to Walmart to confirm inventory, substitutions, payment, and the actual reservation.",
                    color: GatherTheme.walmartBlue
                )
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(GatherTheme.canvas)
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
                        Text(appModel.storeStrategy == .oneStore ? "1 stop" : "\(appModel.selectedStores.count) stops")
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
                .foregroundStyle(GatherTheme.walmartBlue)
            TextField("ZIP code", text: Bindable(appModel).zipCode)
                .keyboardType(.numberPad)
            Button("Use location") {
                appModel.showToast("Using nearby demo stores for \(appModel.zipCode)")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(GatherTheme.walmartBlue)
        }
        .smartField()
    }

    private var strategyPicker: some View {
        @Bindable var appModel = appModel

        return VStack(alignment: .leading, spacing: 9) {
            Text("SHOPPING PLAN")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(GatherTheme.secondaryInk)
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
                                    .foregroundStyle(GatherTheme.navy)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected ? GatherTheme.green : GatherTheme.border)
                            }
                            Text("\(store.distance, specifier: "%.1f") mi · \(store.address)")
                                .font(.caption)
                                .foregroundStyle(GatherTheme.secondaryInk)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                if store.supportsPickup {
                                    StatusPill(title: "Pickup", symbol: "car.fill", color: GatherTheme.green)
                                }
                                if store.supportsDelivery {
                                    StatusPill(title: "Delivery", symbol: "house.fill", color: GatherTheme.walmartBlue)
                                }
                            }
                            .padding(.top, 3)
                        }
                    }
                    .padding(13)
                    .background(GatherTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selected ? GatherTheme.walmartBlue : GatherTheme.border, lineWidth: selected ? 1.6 : 1)
                    }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var fulfillmentSection: some View {
        @Bindable var appModel = appModel

        return VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "Fulfillment", subtitle: "Pre-pick a plan before retailer checkout")

            Picker("Fulfillment", selection: $appModel.fulfillmentMode) {
                ForEach(FulfillmentMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

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
                    .foregroundStyle(GatherTheme.secondaryInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GatherTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .gatherCard()
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
                .foregroundStyle(selected ? .white : GatherTheme.navy)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(selected ? GatherTheme.green : GatherTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Color.clear : GatherTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PantryDashboardView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pantry")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(GatherTheme.navy)
                    Text("What SmartCart will skip or ask about")
                        .font(.subheadline)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    pantryMetric("Have", count: appModel.activeRecipe.ingredients.filter { $0.pantryState == .haveEnough }.count, color: GatherTheme.green)
                    pantryMetric("Low", count: appModel.activeRecipe.ingredients.filter { $0.pantryState == .runningLow }.count, color: GatherTheme.amber)
                    pantryMetric("Buy", count: appModel.ingredientsToBuy.count, color: GatherTheme.walmartBlue)
                }

                SectionHeader(title: appModel.activeRecipe.title, subtitle: "Current recipe pantry decisions")

                ForEach($appModel.activeRecipe.ingredients) { $ingredient in
                    PantryIngredientRow(ingredient: $ingredient)
                }

                InfoBanner(
                    symbol: "lock.fill",
                    title: "Private by default",
                    message: "Pantry choices stay inside this prototype and are never sent to Walmart.",
                    color: GatherTheme.green
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .background(GatherTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func pantryMetric(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 5) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(GatherTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
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
                        .foregroundStyle(GatherTheme.navy)
                    Text("Choose stops, pickup, or a delivery partner")
                        .font(.subheadline)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        StoreMark(size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Preferred Walmart")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(GatherTheme.green)
                                .textCase(.uppercase)
                            Text(appModel.primaryStore.name)
                                .font(.headline)
                                .foregroundStyle(GatherTheme.navy)
                            Text("\(appModel.primaryStore.distance, specifier: "%.1f") mi · \(appModel.selectedPickupSummary)")
                                .font(.caption)
                                .foregroundStyle(GatherTheme.secondaryInk)
                                .lineLimit(1)
                        }
                    }

                    Picker("Shopping plan", selection: $appModel.storeStrategy) {
                        ForEach(StoreStrategy.allCases) { strategy in
                            Text(strategy.rawValue).tag(strategy)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appModel.storeStrategy) { _, newValue in
                        appModel.setStoreStrategy(newValue)
                    }

                    ForEach(appModel.stores) { store in
                        Button {
                            appModel.selectStore(store)
                        } label: {
                            HStack {
                                Image(systemName: appModel.selectedStoreIDs.contains(store.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(appModel.selectedStoreIDs.contains(store.id) ? GatherTheme.green : GatherTheme.border)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(GatherTheme.navy)
                                    Text("\(store.distance, specifier: "%.1f") mi · \(store.format)")
                                        .font(.caption)
                                        .foregroundStyle(GatherTheme.secondaryInk)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .gatherCard()

                VStack(alignment: .leading, spacing: 13) {
                    SectionHeader(title: "Delivery apps", subtitle: "Open an approved partner to finish there")

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
                                        .foregroundStyle(GatherTheme.navy)
                                    Text(appModel.linkedDeliveryPartnerName == partner.name ? "Selected for handoff" : "Link or open app")
                                        .font(.caption)
                                        .foregroundStyle(appModel.linkedDeliveryPartnerName == partner.name ? GatherTheme.green : GatherTheme.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: appModel.linkedDeliveryPartnerName == partner.name ? "checkmark.circle.fill" : "arrow.up.right")
                                    .foregroundStyle(appModel.linkedDeliveryPartnerName == partner.name ? GatherTheme.green : GatherTheme.secondaryInk)
                            }
                            .gatherCard(padding: 13)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }

                InfoBanner(
                    symbol: "building.columns.fill",
                    title: "Retailer adapter boundary",
                    message: "Walmart product links work today. Other retailer matching and true multi-retailer optimization require approved catalog and checkout integrations.",
                    color: GatherTheme.walmartBlue
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .background(GatherTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }
}
