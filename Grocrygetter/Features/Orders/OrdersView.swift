import SwiftUI

struct ProductMatchingView: View {
    @Environment(AppModel.self) private var appModel

    private let stages = [
        ("Searching selected Walmart stores", "magnifyingglass"),
        ("Checking package sizes", "shippingbox.fill"),
        ("Comparing prices", "dollarsign.circle.fill"),
        ("Applying pantry preferences", "slider.horizontal.3"),
        ("Building your shopping list", "checklist")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WorkflowHeader(
                    step: 5,
                    total: 5,
                    eyebrow: "Product matching",
                    title: appModel.matchProgress == 1 ? "Your products are ready" : "Finding the best matches",
                    message: "SmartCart compares product type, package size, price, availability signals, and your pantry choices."
                )

                matchingCard
                stageList

                if appModel.matchProgress == 1 {
                    resultsSummary
                    productPreview
                }

                InfoBanner(
                    symbol: "waveform.path.ecg",
                    title: "Local prototype matching",
                    message: "Matches and prices in this build use a realistic on-device demo catalog. Live inventory requires an approved retailer catalog integration.",
                    color: GatherTheme.amber
                )
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(GatherTheme.canvas)
        .navigationTitle("Match products")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.continueTo(.shoppingList)
                } label: {
                    HStack {
                        Text(appModel.matchProgress == 1 ? "Review shopping list" : "Matching products…")
                        Spacer()
                        if appModel.isMatching {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appModel.matchProgress < 1)
            }
        }
        .task {
            await appModel.startMatching()
        }
    }

    private var matchingCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(GatherTheme.border, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: appModel.matchProgress)
                    .stroke(
                        GatherTheme.green,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: appModel.matchProgress)

                VStack(spacing: 2) {
                    Text("\(Int(appModel.matchProgress * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(GatherTheme.navy)
                    Text("matched")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
            }
            .frame(width: 122, height: 122)

            VStack(spacing: 4) {
                Text(appModel.matchStage)
                    .font(.headline)
                    .foregroundStyle(GatherTheme.navy)
                    .multilineTextAlignment(.center)
                Text("\(appModel.ingredientsToBuy.count) ingredients · \(appModel.selectedStores.count) selected \(appModel.selectedStores.count == 1 ? "store" : "stores")")
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity)
        .gatherCard()
        .gatherShadow()
    }

    private var stageList: some View {
        VStack(spacing: 12) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                let threshold = Double(index + 1) * 0.18
                let complete = appModel.matchProgress >= threshold

                HStack(spacing: 12) {
                    Image(systemName: complete ? "checkmark.circle.fill" : stage.1)
                        .font(.subheadline.bold())
                        .foregroundStyle(complete ? GatherTheme.green : GatherTheme.secondaryInk)
                        .frame(width: 32, height: 32)
                        .background(complete ? GatherTheme.herbLight : GatherTheme.canvas)
                        .clipShape(Circle())

                    Text(stage.0)
                        .font(.subheadline.weight(complete ? .semibold : .regular))
                        .foregroundStyle(complete ? GatherTheme.navy : GatherTheme.secondaryInk)

                    Spacer()

                    if !complete && appModel.isMatching && index == currentStageIndex {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .gatherCard()
    }

    private var currentStageIndex: Int {
        min(stages.count - 1, max(0, Int(appModel.matchProgress / 0.2)))
    }

    private var resultsSummary: some View {
        HStack(spacing: 10) {
            resultMetric("\(appModel.matchedItemCount)", "Best matches", "checkmark.seal.fill", GatherTheme.green)
            resultMetric("\(appModel.lowConfidenceItemCount)", "Review", "exclamationmark.circle.fill", GatherTheme.amber)
            resultMetric(appModel.estimatedTotal.formatted(.currency(code: "USD")), "Est. total", "cart.fill", GatherTheme.walmartBlue)
        }
    }

    private func resultMetric(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(GatherTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GatherTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
        }
    }

    private var productPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "A few top matches")
            HStack(spacing: 10) {
                ForEach(appModel.shoppingItems.prefix(4)) { item in
                    VStack(spacing: 6) {
                        ProductIcon(product: item.product, size: 54)
                        Text(item.ingredient.name)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(GatherTheme.navy)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .gatherCard()
    }
}

struct ShoppingListReviewView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                listHeader
                fulfillmentCard

                VStack(alignment: .leading, spacing: 11) {
                    SectionHeader(
                        title: "Matched products",
                        subtitle: "\(appModel.shoppingItems.count) items · change any match"
                    )

                    ForEach(appModel.shoppingItems) { item in
                        ShoppingProductRow(item: item)
                    }
                }

                totalsCard
                shareActions
                transparencyDisclosure
            }
            .padding(18)
            .padding(.bottom, 138)
        }
        .background(GatherTheme.canvas)
        .navigationTitle("Review shopping list")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                ViewThatFits {
                    HStack(spacing: 9) {
                        Button {
                            appModel.guidedIndex = 0
                            appModel.continueTo(.guidedShopping)
                        } label: {
                            Label("Guided shopping", systemImage: "list.number")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            openURL(appModel.retailerURL())
                        } label: {
                            Label("Open Walmart", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(BlueButtonStyle())
                    }

                    VStack(spacing: 9) {
                        Button {
                            appModel.guidedIndex = 0
                            appModel.continueTo(.guidedShopping)
                        } label: {
                            Label("Start guided shopping", systemImage: "list.number")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            openURL(appModel.retailerURL())
                        } label: {
                            Label("Open Walmart", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(BlueButtonStyle())
                    }
                }
            }
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: appModel.activeRecipe.heroSymbol)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(GatherTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.activeRecipe.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(GatherTheme.navy)
                    Text("\(appModel.desiredServings) servings · \(appModel.primaryStore.name)")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }

                Spacer(minLength: 0)
            }

            HStack {
                StatusPill(title: "\(appModel.matchedItemCount) matched", symbol: "checkmark.seal.fill")
                if appModel.lowConfidenceItemCount > 0 {
                    StatusPill(title: "\(appModel.lowConfidenceItemCount) review", symbol: "exclamationmark.circle.fill", color: GatherTheme.amber)
                }
                Spacer()
                Text(appModel.estimatedTotal, format: .currency(code: "USD"))
                    .font(.title2.bold())
                    .foregroundStyle(GatherTheme.navy)
            }
        }
        .gatherCard()
        .gatherShadow()
    }

    private var fulfillmentCard: some View {
        HStack(spacing: 13) {
            Image(systemName: appModel.fulfillmentMode == .pickup ? "car.fill" : "house.fill")
                .font(.headline)
                .foregroundStyle(GatherTheme.walmartBlue)
                .frame(width: 43, height: 43)
                .background(GatherTheme.walmartLight)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(appModel.fulfillmentMode == .pickup ? "Preferred pickup" : "Delivery handoff")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GatherTheme.navy)
                Text(
                    appModel.fulfillmentMode == .pickup
                        ? "\(appModel.primaryStore.name) · \(appModel.selectedPickupSummary)"
                        : (appModel.linkedDeliveryPartnerName ?? "Choose a partner from the Store tab")
                )
                .font(.caption)
                .foregroundStyle(GatherTheme.secondaryInk)
                .lineLimit(2)
            }

            Spacer()
        }
        .gatherCard(padding: 14)
    }

    private var totalsCard: some View {
        VStack(spacing: 11) {
            totalRow("Product subtotal", value: appModel.estimatedTotal.formatted(.currency(code: "USD")), emphasized: true)
            totalRow("Estimated tax", value: "Calculated by Walmart")
            totalRow("Pickup / delivery fees", value: "Calculated by Walmart")
            totalRow("Variable-weight changes", value: "Finalized at fulfillment")
        }
        .gatherCard()
    }

    private func totalRow(_ label: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .subheadline.weight(.bold) : .caption)
                .foregroundStyle(emphasized ? GatherTheme.navy : GatherTheme.secondaryInk)
            Spacer()
            Text(value)
                .font(emphasized ? .headline : .caption.weight(.semibold))
                .foregroundStyle(emphasized ? GatherTheme.navy : GatherTheme.secondaryInk)
                .multilineTextAlignment(.trailing)
        }
    }

    private var shareActions: some View {
        ViewThatFits {
            HStack(spacing: 9) {
                ShareLink(item: appModel.shareText) {
                    Label("Share list", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    appModel.saveCurrentList()
                } label: {
                    Label("Save list", systemImage: "bookmark.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 9) {
                ShareLink(item: appModel.shareText) {
                    Label("Share list", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    appModel.saveCurrentList()
                } label: {
                    Label("Save list", systemImage: "bookmark.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var transparencyDisclosure: some View {
        InfoBanner(
            symbol: "checkmark.shield.fill",
            title: "You shop and pay at Walmart",
            message: "SmartCart does not hold payment details, sign in to your Walmart account, or claim an item was added unless you mark it in guided shopping.",
            color: GatherTheme.green
        )
    }
}

private struct ShoppingProductRow: View {
    @Environment(AppModel.self) private var appModel
    let item: ShoppingListItem

    var body: some View {
        VStack(spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ProductIcon(product: item.product, size: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.product.brand)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                        .textCase(.uppercase)
                    Text(item.product.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GatherTheme.navy)
                        .lineLimit(2)
                    Text("\(item.product.package) · \(item.product.unitPrice)")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                    if appModel.storeStrategy == .multipleStops {
                        Text(appModel.store(for: item.storeID).name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GatherTheme.walmartBlue)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.lineTotal, format: .currency(code: "USD"))
                        .font(.headline)
                        .foregroundStyle(GatherTheme.navy)
                    if item.product.confidence == .high {
                        StatusPill(title: "Best match", symbol: "checkmark.circle.fill")
                    } else {
                        IngredientConfidenceBadge(confidence: item.product.confidence)
                    }
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipe needs \(item.requestedQuantity)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                    if item.product.variableWeight {
                        Text("Final weight may vary")
                            .font(.caption2)
                            .foregroundStyle(GatherTheme.amber)
                    }
                }

                Spacer()

                Menu {
                    ForEach(item.alternatives) { candidate in
                        Button {
                            appModel.selectAlternative(itemID: item.id, candidateID: candidate.id)
                        } label: {
                            Text("\(candidate.brand) \(candidate.name) · \(candidate.price.formatted(.currency(code: "USD")))")
                        }
                    }
                } label: {
                    Text("Change")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GatherTheme.walmartBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(GatherTheme.walmartLight)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    quantityButton("minus", delta: -1)
                    Text("\(item.purchaseQuantity)")
                        .font(.caption.bold())
                        .frame(minWidth: 12)
                    quantityButton("plus", delta: 1)
                }
            }
        }
        .padding(13)
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.product.confidence == .high ? GatherTheme.border : GatherTheme.amber.opacity(0.55), lineWidth: 1)
        }
    }

    private func quantityButton(_ symbol: String, delta: Int) -> some View {
        Button {
            appModel.updatePurchaseQuantity(for: item.id, delta: delta)
        } label: {
            Image(systemName: symbol)
                .font(.caption2.bold())
                .foregroundStyle(GatherTheme.navy)
                .frame(width: 25, height: 25)
                .background(GatherTheme.canvas)
                .clipShape(Circle())
        }
    }
}

struct GuidedShoppingView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if appModel.shoppingItems.isEmpty {
                    EmptyStateView(
                        symbol: "cart",
                        title: "Nothing to guide yet",
                        message: "Match products before starting guided shopping."
                    )
                } else if appModel.guidedCompletedCount == appModel.shoppingItems.count {
                    completionView
                } else if let item = appModel.currentGuidedItem {
                    guidedHeader
                    guidedProduct(item)
                    actionSteps
                    navigationControls
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .background(GatherTheme.canvas)
        .navigationTitle("Guided shopping")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var guidedHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Item \(appModel.guidedIndex + 1) of \(appModel.shoppingItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GatherTheme.green)
                Spacer()
                Text("\(appModel.guidedCompletedCount) completed")
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(GatherTheme.border)
                    Capsule()
                        .fill(GatherTheme.green)
                        .frame(width: proxy.size.width * CGFloat(appModel.guidedCompletedCount) / CGFloat(max(1, appModel.shoppingItems.count)))
                }
            }
            .frame(height: 6)
        }
    }

    private func guidedProduct(_ item: ShoppingListItem) -> some View {
        VStack(spacing: 18) {
            ProductIcon(product: item.product, size: 132)

            VStack(spacing: 5) {
                Text(item.ingredient.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GatherTheme.green)
                    .textCase(.uppercase)
                Text(item.product.brand)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GatherTheme.secondaryInk)
                Text(item.product.name)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(GatherTheme.navy)
                    .multilineTextAlignment(.center)
                Text("\(item.product.package) · \(item.product.unitPrice)")
                    .font(.subheadline)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }

            Text(item.product.price, format: .currency(code: "USD"))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(GatherTheme.navy)

            Button {
                openURL(appModel.productURL(for: item))
            } label: {
                HStack {
                    Text("Open product at Walmart")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(BlueButtonStyle())

            Text("Walmart opens outside SmartCart. Return here after adding or reviewing the product.")
                .font(.caption)
                .foregroundStyle(GatherTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .gatherCard()
        .gatherShadow()
    }

    private var actionSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "When you return")

            Button {
                appModel.markCurrentGuidedItem(.added)
                appModel.advanceGuidedItem()
            } label: {
                Label("Mark added & go to next", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            ViewThatFits {
                HStack(spacing: 9) {
                    replacementMenu

                    Button {
                        appModel.markCurrentGuidedItem(.skipped)
                        appModel.advanceGuidedItem()
                    } label: {
                        Label("Skip item", systemImage: "forward.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                VStack(spacing: 9) {
                    replacementMenu
                    Button {
                        appModel.markCurrentGuidedItem(.skipped)
                        appModel.advanceGuidedItem()
                    } label: {
                        Label("Skip item", systemImage: "forward.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var replacementMenu: some View {
        Menu {
            if let item = appModel.currentGuidedItem {
                ForEach(item.alternatives) { candidate in
                    Button {
                        appModel.selectAlternative(itemID: item.id, candidateID: candidate.id)
                    } label: {
                        Text("\(candidate.brand) \(candidate.name)")
                    }
                }
            }
        } label: {
            Label("Choose replacement", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(GatherTheme.navy)
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

    private var navigationControls: some View {
        HStack {
            Button {
                appModel.moveGuidedItem(by: -1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(appModel.guidedIndex == 0)

            Spacer()

            Button {
                appModel.moveGuidedItem(by: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(appModel.guidedIndex == appModel.shoppingItems.count - 1)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(GatherTheme.green)
        .padding(.horizontal, 4)
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58))
                .foregroundStyle(GatherTheme.green)
            Text("Shopping guide complete")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(GatherTheme.navy)
                .multilineTextAlignment(.center)
            Text("\(appModel.shoppingItems.filter { $0.status == .added }.count) products marked added · \(appModel.shoppingItems.filter { $0.status == .skipped }.count) skipped")
                .font(.subheadline)
                .foregroundStyle(GatherTheme.secondaryInk)

            Button {
                openURL(appModel.retailerURL())
            } label: {
                Label("Finish checkout at Walmart", systemImage: "arrow.up.right")
            }
            .buttonStyle(BlueButtonStyle())

            Button {
                appModel.saveCurrentList()
                appModel.resetFlow()
            } label: {
                Label("Save list & return home", systemImage: "house.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .gatherCard()
        .gatherShadow()
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var appModel
    @State private var rememberPantry = true
    @State private var priceAlerts = true
    @State private var creatorMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                accountHeader
                preferenceCard
                creatorCard
                privacyCard
                aboutCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .background(GatherTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var accountHeader: some View {
        HStack(spacing: 15) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(GatherTheme.navy)

            VStack(alignment: .leading, spacing: 4) {
                Text("SmartCart shopper")
                    .font(.title2.bold())
                    .foregroundStyle(GatherTheme.navy)
                Text("Local prototype profile")
                    .font(.subheadline)
                    .foregroundStyle(GatherTheme.secondaryInk)
                StatusPill(title: "Private on device", symbol: "lock.fill")
            }
        }
        .padding(.top, 8)
    }

    private var preferenceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Preferences")

            Toggle("Remember pantry choices", isOn: $rememberPantry)
            Divider()
            Toggle("Price-change alerts", isOn: $priceAlerts)
            Divider()

            HStack {
                Text("Preferred retailer")
                Spacer()
                Text("Walmart")
                    .fontWeight(.bold)
                    .foregroundStyle(GatherTheme.walmartBlue)
            }
        }
        .font(.subheadline.weight(.semibold))
        .tint(GatherTheme.green)
        .foregroundStyle(GatherTheme.navy)
        .gatherCard()
    }

    private var creatorCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle(isOn: $creatorMode) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Creator mode")
                        .font(.headline)
                        .foregroundStyle(GatherTheme.navy)
                    Text("Add a profile and share recipe-to-list pages with followers.")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
            }
            .tint(GatherTheme.green)

            if creatorMode {
                InfoBanner(
                    symbol: "person.2.fill",
                    title: "Creator tools preview",
                    message: "Shared pages can include recipe attribution, product links, and clear affiliate disclosures.",
                    color: GatherTheme.purple
                )
            }
        }
        .gatherCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "Trust & privacy")
            trustRow("No Walmart credentials", "key.slash.fill")
            trustRow("No payment data stored", "creditcard.trianglebadge.exclamationmark")
            trustRow("On-device photo text recognition", "text.viewfinder")
            trustRow("Retailer confirms final checkout", "checkmark.shield.fill")
        }
        .gatherCard()
    }

    private func trustRow(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(GatherTheme.green)
                .frame(width: 26)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GatherTheme.navy)
        }
    }

    private var aboutCard: some View {
        HStack {
            SmartCartLogo(compact: true)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Prototype 1.0")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GatherTheme.navy)
                Text("Upload. Confirm. Match. Shop.")
                    .font(.caption2)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }
        }
        .gatherCard(padding: 14)
    }
}
