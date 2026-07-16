import SwiftUI

struct CartView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                cartHeader
                strategyPicker
                selectedStoresRow

                if appModel.cartItems.isEmpty {
                    EmptyStateView(
                        symbol: "basket",
                        title: "Your cart is waiting",
                        message: "Add a recipe and Gather will turn its ingredients into a shopping plan."
                    )
                } else {
                    storeGroups
                    checkoutSummary
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .background(GatherTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Smart cart")
                    .font(.headline)
                    .foregroundStyle(GatherTheme.ink)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appModel.presentedSheet = .storePicker
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Cart settings")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !appModel.cartItems.isEmpty {
                checkoutBar
            }
        }
        .onChange(of: appModel.storeStrategy) {
            appModel.applyStoreStrategy()
        }
    }

    private var cartHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appModel.activeCartItemCount) ingredients")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(GatherTheme.ink)
                Text("For \(Set(appModel.cartItems.map(\.recipeName)).count) delicious meals")
                    .font(.subheadline)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }

            Spacer()

            if appModel.storeStrategy == .smartSplit {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("You save")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                    Text("$\(appModel.estimatedSavings, specifier: "%.2f")")
                        .font(.title3.bold())
                        .foregroundStyle(GatherTheme.herb)
                }
            }
        }
        .padding(.top, 8)
    }

    private var strategyPicker: some View {
        @Bindable var appModel = appModel

        return Picker("Store strategy", selection: $appModel.storeStrategy) {
            ForEach(StoreStrategy.allCases) { strategy in
                Text(strategy.rawValue).tag(strategy)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Store strategy")
    }

    private var selectedStoresRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(appModel.stores) { store in
                    let selected = appModel.selectedStoreIDs.contains(store.id)
                    Button {
                        if appModel.storeStrategy == .oneStore {
                            appModel.useOnlyStore(store)
                        } else {
                            appModel.toggleStore(store)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(store.color)
                                .frame(width: 9, height: 9)
                            Text(store.shortName)
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .white : GatherTheme.secondaryInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(selected ? GatherTheme.ink : GatherTheme.paper)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }

                Button {
                    appModel.presentedSheet = .storePicker
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(GatherTheme.herb)
                        .frame(width: 39, height: 39)
                        .background(GatherTheme.paper)
                        .clipShape(Circle())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var storeGroups: some View {
        VStack(spacing: 20) {
            ForEach(appModel.selectedStores) { store in
                let items = appModel.cartItems.filter { $0.storeID == store.id }
                if !items.isEmpty {
                    StoreCartSection(store: store, items: items)
                }
            }
        }
    }

    private var checkoutSummary: some View {
        VStack(spacing: 12) {
            summaryRow("Items", value: appModel.cartSubtotal.formatted(.currency(code: "USD")))
            summaryRow("Pickup fees", value: appModel.selectedStores.allSatisfy { $0.pickupFee == 0 } ? "Free" : "$1.99")
            if appModel.storeStrategy == .smartSplit {
                summaryRow(
                    "Smart Split savings",
                    value: "−\(appModel.estimatedSavings.formatted(.currency(code: "USD")))",
                    valueColor: GatherTheme.herb
                )
            }

            Divider()

            HStack {
                Text("Estimated total")
                    .font(.headline)
                Spacer()
                Text("$\(max(0, appModel.cartSubtotal - appModel.estimatedSavings), specifier: "%.2f")")
                    .font(.title3.bold())
            }
            .foregroundStyle(GatherTheme.ink)
        }
        .gatherCard()
    }

    private func summaryRow(_ label: String, value: String, valueColor: Color = GatherTheme.secondaryInk) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(GatherTheme.secondaryInk)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
        .font(.subheadline)
    }

    private var checkoutBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                appModel.presentedSheet = .pickupScheduler
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan checkout")
                        Text("Pickup or delivery")
                            .font(.caption.weight(.medium))
                            .opacity(0.75)
                    }
                    Spacer()
                    Text("$\(max(0, appModel.cartSubtotal - appModel.estimatedSavings), specifier: "%.2f")")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(16)
            .background(.ultraThinMaterial)
        }
    }
}

private struct StoreCartSection: View {
    @Environment(AppModel.self) private var appModel
    let store: GroceryStore
    let items: [CartItem]

    private var subtotal: Double {
        items.reduce(0) { $0 + $1.lineTotal }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StoreMark(store: store, size: 45)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.name)
                        .font(.headline)
                        .foregroundStyle(GatherTheme.ink)
                    Text("\(items.count) items • \(store.distance, specifier: "%.1f") mi away")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }

                Spacer()

                Text("$\(subtotal, specifier: "%.2f")")
                    .font(.headline)
                    .foregroundStyle(GatherTheme.ink)
            }
            .padding(16)

            Divider()
                .padding(.leading, 16)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                CartItemRow(item: item)
                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 70)
                }
            }
        }
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: GatherTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GatherTheme.cardRadius, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
        }
    }
}

private struct CartItemRow: View {
    @Environment(AppModel.self) private var appModel
    let item: CartItem

    var body: some View {
        HStack(spacing: 12) {
            Button {
                appModel.toggleChecked(item.id)
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? GatherTheme.herb : Color.gray.opacity(0.45))
            }
            .accessibilityLabel(item.isChecked ? "Mark \(item.ingredient.name) needed" : "Mark \(item.ingredient.name) complete")

            Image(systemName: item.ingredient.category.symbol)
                .font(.subheadline.bold())
                .foregroundStyle(GatherTheme.herb)
                .frame(width: 38, height: 38)
                .background(GatherTheme.herbLight.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.ingredient.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GatherTheme.ink)
                    .strikethrough(item.isChecked)
                    .opacity(item.isChecked ? 0.5 : 1)
                Text("\(item.ingredient.displayQuantity) • \(item.recipeName)")
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 7) {
                Text("$\(item.lineTotal, specifier: "%.2f")")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GatherTheme.ink)

                HStack(spacing: 8) {
                    quantityButton(symbol: "minus", delta: -1)
                    Text("\(item.quantity)")
                        .font(.caption.bold())
                        .frame(minWidth: 12)
                    quantityButton(symbol: "plus", delta: 1)
                }
            }
        }
        .padding(14)
        .contextMenu {
            ForEach(appModel.stores) { store in
                Button {
                    appModel.moveItem(item.id, to: store)
                } label: {
                    Label("Move to \(store.name)", systemImage: store.symbol)
                }
            }
        }
    }

    private func quantityButton(symbol: String, delta: Int) -> some View {
        Button {
            appModel.updateQuantity(for: item.id, delta: delta)
        } label: {
            Image(systemName: symbol)
                .font(.caption2.bold())
                .foregroundStyle(GatherTheme.ink)
                .frame(width: 24, height: 24)
                .background(GatherTheme.canvas)
                .clipShape(Circle())
        }
        .accessibilityLabel(delta > 0 ? "Increase quantity" : "Decrease quantity")
    }
}
