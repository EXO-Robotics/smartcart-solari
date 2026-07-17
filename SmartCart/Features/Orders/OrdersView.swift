import SafariServices
import SwiftUI

struct ProductMatchingView: View {
    @Environment(AppModel.self) private var appModel

    private var stages: [(String, String)] {
        if appModel.shoppingRoute == .instacart {
            return [
                ("Reviewing pantry exclusions", "cabinet.fill"),
                ("Converting ingredient quantities", "scalemass.fill"),
                ("Applying dietary and organic rules", "checkmark.shield.fill"),
                ("Checking unresolved ingredients", "exclamationmark.magnifyingglass"),
                ("Building the normalized manifest", "checklist")
            ]
        }
        return [
            ("Reading saved shopping preferences", "slider.horizontal.3"),
            ("Searching the selected Walmart store", "magnifyingglass"),
            ("Checking package sizes", "shippingbox.fill"),
            ("Applying dietary and organic rules", "checkmark.shield.fill"),
            ("Ranking eligible products", "arrow.up.arrow.down"),
            ("Building the shopping manifest", "checklist")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WorkflowHeader(
                    step: 6,
                    total: 6,
                    eyebrow: appModel.shoppingRoute == .instacart ? "Manifest preparation" : "Product matching",
                    title: appModel.matchProgress == 1
                        ? (appModel.shoppingRoute == .instacart ? "Your list is ready to review" : "Your products are ready")
                        : (appModel.shoppingRoute == .instacart ? "Preparing a safe handoff" : "Finding the best matches"),
                    message: appModel.shoppingRoute == .instacart
                        ? "SmartCart removes pantry items, normalizes quantities, and applies supported preferences before Instacart performs live matching."
                        : "SmartCart applies \(appModel.preferences.summary), then resolves exact retailer products or clearly labeled searches."
                )

                matchingCard
                stageList

                if appModel.matchProgress == 1 {
                    resultsSummary
                    if appModel.shoppingRoute != .instacart {
                        productPreview
                    }
                }

                InfoBanner(
                    symbol: "waveform.path.ecg",
                    title: appModel.shoppingRoute == .instacart ? "No products selected yet" : "Seeded retailer records",
                    message: appModel.shoppingRoute == .instacart
                        ? "Instacart will confirm live products, store, prices, availability, substitutions, pickup or delivery, and checkout after you approve this manifest."
                        : "Exact Walmart item IDs and observed demo prices are stored on-device. Availability is not live, and search fallbacks are never presented as exact products.",
                    color: appModel.shoppingRoute == .instacart ? SmartCartTheme.green : SmartCartTheme.amber
                )
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .smartCartBackground()
        .navigationTitle(appModel.shoppingRoute == .instacart ? "Prepare manifest" : "Match products")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    appModel.continueTo(.shoppingList)
                } label: {
                    HStack {
                        Text(appModel.matchProgress == 1 ? "Review shopping list" : "Preparing list…")
                        Spacer()
                        if appModel.isMatching {
                            ProgressView()
                                .tint(SmartCartTheme.onAccent)
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
                    .stroke(SmartCartTheme.border, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: appModel.matchProgress)
                    .stroke(
                        SmartCartTheme.green,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: SmartCartTheme.mintGlow, radius: 12)
                    .animation(.easeInOut(duration: 0.35), value: appModel.matchProgress)

                VStack(spacing: 2) {
                    Text("\(Int(appModel.matchProgress * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(appModel.shoppingRoute == .instacart ? "prepared" : "matched")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
            .frame(width: 122, height: 122)

            VStack(spacing: 4) {
                Text(appModel.matchStage)
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.center)
                Text(appModel.shoppingRoute == .instacart
                    ? "\(appModel.ingredientsToBuy.count) ingredients · \(appModel.pantrySkipCount) pantry item(s) removed"
                    : "\(appModel.ingredientsToBuy.count) ingredients · \(appModel.selectedStores.count) selected \(appModel.selectedStores.count == 1 ? "store" : "stores")")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity)
        .smartCartCard()
        .smartCartShadow()
    }

    private var stageList: some View {
        VStack(spacing: 12) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                let threshold = Double(index + 1) / Double(stages.count)
                let complete = appModel.matchProgress >= threshold

                HStack(spacing: 12) {
                    Image(systemName: complete ? "checkmark.circle.fill" : stage.1)
                        .font(.subheadline.bold())
                        .foregroundStyle(complete ? SmartCartTheme.green : SmartCartTheme.secondaryInk)
                        .frame(width: 32, height: 32)
                        .background(complete ? SmartCartTheme.herbLight : SmartCartTheme.canvas)
                        .clipShape(Circle())

                    Text(stage.0)
                        .font(.subheadline.weight(complete ? .semibold : .regular))
                        .foregroundStyle(complete ? SmartCartTheme.navy : SmartCartTheme.secondaryInk)

                    Spacer()

                    if !complete && appModel.isMatching && index == currentStageIndex {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .smartCartCard()
    }

    private var currentStageIndex: Int {
        min(
            stages.count - 1,
            max(0, Int(appModel.matchProgress * Double(stages.count)))
        )
    }

    private var resultsSummary: some View {
        HStack(spacing: 10) {
            if appModel.shoppingRoute == .instacart {
                resultMetric("\(appModel.ingredientsToBuy.count)", "To shop", "basket.fill", SmartCartTheme.green)
                resultMetric("\(appModel.pantrySkipCount)", "Removed", "cabinet.fill", SmartCartTheme.purple)
                resultMetric("\(appModel.commerceBlockingIssues.count)", "Need review", "exclamationmark.triangle.fill", SmartCartTheme.amber)
            } else {
                resultMetric("\(appModel.matchedItemCount)", "Exact links", "checkmark.seal.fill", SmartCartTheme.green)
                resultMetric("\(appModel.searchFallbackCount)", "Searches", "magnifyingglass.circle.fill", SmartCartTheme.amber)
                resultMetric(appModel.estimatedTotal.formatted(.currency(code: "USD")), "Observed", "cart.fill", SmartCartTheme.walmartBlue)
            }
        }
    }

    private func resultMetric(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(SmartCartTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(SmartCartTheme.border, lineWidth: 1)
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
                            .foregroundStyle(SmartCartTheme.navy)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .smartCartCard()
    }
}

struct ShoppingListReviewView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var appModel
    @State private var commerceSheet: CommerceSheetDestination?
    @State private var safariWasPresented = false

    @ViewBuilder
    var body: some View {
        switch appModel.shoppingRoute {
        case .instacart:
            instacartReview
        case .walmartDirect:
            walmartReview
        case .otherRetailerLinks:
            otherRetailerReview
        }
    }

    private var walmartReview: some View {
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
        .smartCartBackground()
        .navigationTitle("Review shopping list")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                ViewThatFits {
                    HStack(spacing: 9) {
                        Button {
                            appModel.beginGuidedShopping()
                        } label: {
                            Label("Guided shopping", systemImage: "list.number")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            Task {
                                if let handoff = await appModel.prepareRetailerHandoff() {
                                    openURL(handoff.url)
                                }
                            }
                        } label: {
                            Label("Visit Walmart", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(BlueButtonStyle())
                    }

                    VStack(spacing: 9) {
                        Button {
                            appModel.beginGuidedShopping()
                        } label: {
                            Label("Start guided shopping", systemImage: "list.number")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            Task {
                                if let handoff = await appModel.prepareRetailerHandoff() {
                                    openURL(handoff.url)
                                }
                            }
                        } label: {
                            Label("Visit Walmart", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(BlueButtonStyle())
                    }
                }
            }
        }
    }

    private var instacartReview: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    instacartHeader
                    instacartSummary

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(
                            title: "Ingredients Instacart will receive",
                            subtitle: "\(appModel.ingredientsToBuy.count) normalized line items · no products selected yet"
                        )
                        ForEach(appModel.ingredientsToBuy) { ingredient in
                            InstacartIngredientRow(
                                ingredient: ingredient,
                                quantityText: appModel.quantityToBuyText(for: ingredient)
                            )
                        }
                    }

                    if !appModel.commerceBlockingIssues.isEmpty {
                        InfoBanner(
                            symbol: "exclamationmark.triangle.fill",
                            title: "Review required before handoff",
                            message: appModel.commerceBlockingIssues.joined(separator: " "),
                            color: SmartCartTheme.amber
                        )
                    }

                    InfoBanner(
                        symbol: "checkmark.shield.fill",
                        title: "SmartCart prepares; Instacart confirms",
                        message: "Instacart will confirm products, prices, availability, substitutions, store, pickup or delivery, sign-in, payment, checkout, and order tracking.",
                        color: SmartCartTheme.green
                    )
                    ShareLink(item: appModel.shareText) {
                        Label("Share ingredient list", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(18)
                .padding(.bottom, 142)
            }
            .smartCartBackground()

            if appModel.isPreparingCommerceHandoff {
                CommerceHandoffLoadingView(stage: appModel.commerceHandoffStage)
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appModel.isPreparingCommerceHandoff)
        .navigationTitle("Final list review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                VStack(spacing: 8) {
                    Button {
                        Task { await prepareInstacartHandoff() }
                    } label: {
                        HStack {
                            Text("Shop ingredients")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(
                        !appModel.activeCommerceCapabilities.preparesShoppingList ||
                        !appModel.commerceBlockingIssues.isEmpty ||
                        appModel.isPreparingCommerceHandoff
                    )

                    if let handoff = appModel.lastInstacartHandoff {
                        Button("Open in Instacart or Safari") {
                            openURL(handoff.url)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.green)
                    }
                }
            }
        }
        .sheet(item: $commerceSheet, onDismiss: commerceSheetDidDismiss) { destination in
            switch destination {
            case .safari(let handoff):
                InstacartSafariView(url: handoff.url)
                    .ignoresSafeArea()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .feedback(let handoff):
                CommerceFeedbackSheet(handoff: handoff) {
                    commerceSheet = .safari(handoff)
                    safariWasPresented = true
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var instacartHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                Image(systemName: "carrot.fill")
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 54, height: 54)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(appModel.activeRecipe.title)
                        .font(.title3.bold())
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("SmartCart → Instacart shopping-list handoff")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            Text("Review the final manifest before SmartCart creates a secure shopping-list link.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .smartCartCard()
        .smartCartShadow()
    }

    private var instacartSummary: some View {
        VStack(spacing: 11) {
            totalRow("Ingredients", value: "\(appModel.ingredientsToBuy.count)", emphasized: true)
            totalRow("Pantry items removed", value: "\(appModel.pantrySkipCount)")
            totalRow("Preferences", value: appModel.preferences.summary)
            totalRow("Preferred retailer", value: appModel.instacartRetailerPreference.label)
            totalRow("Fulfillment", value: "\(appModel.commerceFulfillmentPreference.label) · advisory")
            totalRow("List composition", value: listComposition)
            totalRow("Items requiring review", value: "\(appModel.commerceBlockingIssues.count)")
        }
        .smartCartCard()
    }

    private var listComposition: String {
        let grouped = Dictionary(grouping: appModel.ingredientsToBuy, by: \.category)
        return grouped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value.count) \($0.key.rawValue.lowercased())" }
            .joined(separator: " · ")
    }

    private var otherRetailerReview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkflowHeader(
                    step: 6,
                    total: 6,
                    eyebrow: "Retailer links",
                    title: "Choose an external destination",
                    message: "These links do not receive your SmartCart manifest. Products, prices, availability, fulfillment, and checkout are not connected."
                )
                ForEach(appModel.deliveryPartners) { partner in
                    Button {
                        openURL(partner.url)
                    } label: {
                        HStack {
                            Image(systemName: partner.symbol)
                                .foregroundStyle(partner.color)
                            Text(partner.name)
                                .font(.headline)
                                .foregroundStyle(SmartCartTheme.navy)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                InfoBanner(
                    symbol: "info.circle.fill",
                    title: "No list transfer",
                    message: "Return to Shopping route and choose Instacart when you want SmartCart to prepare a normalized list.",
                    color: SmartCartTheme.amber
                )
            }
            .padding(18)
        }
        .smartCartBackground()
        .navigationTitle("Retailer links")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prepareInstacartHandoff() async {
        guard let handoff = await appModel.prepareInstacartHandoff() else { return }
        safariWasPresented = true
        commerceSheet = .safari(handoff)
    }

    private func commerceSheetDidDismiss() {
        guard safariWasPresented, let handoff = appModel.lastInstacartHandoff else { return }
        safariWasPresented = false
        Task { @MainActor in
            await Task.yield()
            commerceSheet = .feedback(handoff)
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: appModel.activeRecipe.heroSymbol)
                    .font(.title.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 62, height: 62)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .shadow(color: SmartCartTheme.mintGlow, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.activeRecipe.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("\(appModel.desiredServings) servings · \(appModel.primaryStore.name)")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }

                Spacer(minLength: 0)
            }

            HStack {
                StatusPill(title: "\(appModel.matchedItemCount) exact", symbol: "checkmark.seal.fill")
                if appModel.searchFallbackCount > 0 {
                    StatusPill(title: "\(appModel.searchFallbackCount) searches", symbol: "magnifyingglass.circle.fill", color: SmartCartTheme.amber)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(appModel.estimatedTotal, format: .currency(code: "USD"))
                        .font(.title2.bold())
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Demo subtotal · not live")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SmartCartTheme.amber)
                }
            }
        }
        .smartCartCard()
        .smartCartShadow()
    }

    private var fulfillmentCard: some View {
        HStack(spacing: 13) {
            Image(systemName: appModel.fulfillmentMode == .pickup ? "car.fill" : "house.fill")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.walmartBlue)
                .frame(width: 43, height: 43)
                .background(SmartCartTheme.walmartLight)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(appModel.fulfillmentMode == .pickup ? "Preferred pickup window" : "Experimental delivery preference")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text(
                    appModel.fulfillmentMode == .pickup
                        ? "\(appModel.primaryStore.name) · \(appModel.selectedPickupSummary)"
                        : (appModel.linkedDeliveryPartnerName ?? "Choose a partner from the Store tab")
                )
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .lineLimit(2)
            }

            Spacer()
        }
        .smartCartCard(padding: 14)
    }

    private var totalsCard: some View {
        VStack(spacing: 11) {
            totalRow(
                "Demo subtotal · not live",
                value: appModel.estimatedTotal.formatted(.currency(code: "USD")),
                emphasized: true
            )
            totalRow(
                "Items with a price",
                value: "\(appModel.pricedItemCount) of \(appModel.shoppingItems.count)"
            )
            totalRow("Estimated tax", value: "Calculated by Walmart")
            totalRow("Pickup / delivery fees", value: "Calculated by Walmart")
            totalRow("Variable-weight changes", value: "Finalized at fulfillment")
        }
        .smartCartCard()
    }

    private func totalRow(_ label: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .subheadline.weight(.bold) : .caption)
                .foregroundStyle(emphasized ? SmartCartTheme.navy : SmartCartTheme.secondaryInk)
            Spacer()
            Text(value)
                .font(emphasized ? .headline : .caption.weight(.semibold))
                .foregroundStyle(emphasized ? SmartCartTheme.navy : SmartCartTheme.secondaryInk)
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
            title: "This is a manifest, not a retailer cart",
            message: "SmartCart saves your selected product records and progress. You open exact items or labeled searches, then add, reserve pickup, and pay at Walmart.",
            color: SmartCartTheme.green
        )
    }
}

private enum CommerceSheetDestination: Identifiable {
    case safari(InstacartHandoffResponse)
    case feedback(InstacartHandoffResponse)

    var id: String {
        switch self {
        case .safari(let handoff): "safari-\(handoff.manifestFingerprint)"
        case .feedback(let handoff): "feedback-\(handoff.manifestFingerprint)"
        }
    }
}

private struct InstacartIngredientRow: View {
    let ingredient: Ingredient
    let quantityText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ingredient.category.symbol)
                .font(.subheadline.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 38, height: 38)
                .background(SmartCartTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text(ingredient.preparation.isEmpty ? quantityText : "\(quantityText) · \(ingredient.preparation)")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
            Spacer()
            if ingredient.quantityReviewRequired == true || ingredient.alternativeGroup != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SmartCartTheme.amber)
                    .accessibilityLabel("Needs review")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SmartCartTheme.green)
                    .accessibilityLabel("Ready")
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
}

private struct CommerceHandoffLoadingView: View {
    let stage: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
            VStack(spacing: 17) {
                ProgressView()
                    .controlSize(.large)
                    .tint(SmartCartTheme.green)
                Text(stage)
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.center)
                Text("No order is placed during this step.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
            .padding(26)
            .frame(maxWidth: 300)
            .background(SmartCartTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .smartCartShadow()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stage)
    }
}

private struct InstacartSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(SmartCartTheme.green)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct CommerceFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    let handoff: InstacartHandoffResponse
    let reopen: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        title: "How did shopping go?",
                        subtitle: "This is self-reported. SmartCart does not infer checkout completion."
                    )
                    ForEach(CommerceHandoffFeedback.allCases) { feedback in
                        Button {
                            appModel.recordHandoffFeedback(feedback)
                            dismiss()
                        } label: {
                            HStack {
                                Text(feedback.label)
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Image(systemName: appModel.latestHandoffFeedback == feedback ? "checkmark.circle.fill" : "circle")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Button {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            reopen()
                        }
                    } label: {
                        Label("Reopen Instacart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(18)
            }
            .smartCartBackground()
            .navigationTitle("Shopping feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .textCase(.uppercase)
                    Text(item.product.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                        .lineLimit(2)
                    Text("\(item.product.package) · \(item.product.unitPrice)")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                    if appModel.storeStrategy == .multipleStops {
                        Text(appModel.store(for: item.storeID).name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SmartCartTheme.walmartBlue)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    if item.product.hasObservedPrice {
                        Text(item.lineTotal, format: .currency(code: "USD"))
                            .font(.headline)
                            .foregroundStyle(SmartCartTheme.navy)
                    } else {
                        Text("Price unavailable")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SmartCartTheme.amber)
                    }
                    if item.product.isExactProductLink {
                        StatusPill(title: "Exact item", symbol: "checkmark.circle.fill")
                    } else {
                        StatusPill(
                            title: "Retailer search",
                            symbol: "magnifyingglass.circle.fill",
                            color: SmartCartTheme.amber
                        )
                    }
                    Text(item.product.priceDisclosure)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(
                            item.product.hasObservedPrice
                                ? SmartCartTheme.amber
                                : SmartCartTheme.secondaryInk
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 112, alignment: .trailing)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipe needs \(item.requestedQuantity)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                    if item.product.variableWeight {
                        Text("Final weight may vary")
                            .font(.caption2)
                            .foregroundStyle(SmartCartTheme.amber)
                    }
                }

                Spacer()

                Menu {
                    ForEach(item.alternatives) { candidate in
                        Button {
                            appModel.selectAlternative(itemID: item.id, candidateID: candidate.id)
                        } label: {
                            Text(alternativeLabel(candidate))
                        }
                    }
                } label: {
                    Text("Change")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.walmartBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(SmartCartTheme.walmartLight)
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
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    item.product.isExactProductLink ? SmartCartTheme.border : SmartCartTheme.amber.opacity(0.55),
                    lineWidth: 1
                )
        }
    }

    private func alternativeLabel(_ candidate: RetailerProductRecord) -> String {
        let price = candidate.hasObservedPrice
            ? candidate.price.formatted(.currency(code: "USD"))
            : "price unavailable"
        return "\(candidate.brand) \(candidate.name) · \(price)"
    }

    private func quantityButton(_ symbol: String, delta: Int) -> some View {
        Button {
            appModel.updatePurchaseQuantity(for: item.id, delta: delta)
        } label: {
            Image(systemName: symbol)
                .font(.caption2.bold())
                .foregroundStyle(SmartCartTheme.navy)
                .frame(width: 25, height: 25)
                .background(SmartCartTheme.canvas)
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
        .smartCartBackground()
        .navigationTitle("Guided shopping")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var guidedHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Item \(appModel.guidedIndex + 1) of \(appModel.shoppingItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                Spacer()
                Text("\(appModel.guidedCompletedCount) completed")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SmartCartTheme.border)
                    Capsule()
                        .fill(SmartCartTheme.green)
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
                    .foregroundStyle(SmartCartTheme.green)
                    .textCase(.uppercase)
                Text(item.product.brand)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                Text(item.product.name)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.center)
                Text("\(item.product.package) · \(item.product.unitPrice)")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            if item.product.hasObservedPrice {
                VStack(spacing: 4) {
                    Text(item.product.price, format: .currency(code: "USD"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(item.product.priceDisclosure)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SmartCartTheme.amber)
                }
            } else {
                VStack(spacing: 4) {
                    Text("Price unavailable")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.amber)
                    Text(item.product.priceDisclosure)
                        .font(.caption2)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }

            Button {
                appModel.track(
                    .retailerLinkOpened,
                    properties: ["retailer": item.product.retailerID, "mode": item.product.linkKind.rawValue]
                )
                openURL(appModel.productURL(for: item))
            } label: {
                HStack {
                    Text(appModel.productHandoffLabel(for: item))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(BlueButtonStyle())

            Text(
                item.product.isExactProductLink
                    ? "This opens the selected item. Return after you add or review it yourself."
                    : "No exact eligible record was available. This opens a labeled retailer search."
            )
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .smartCartCard()
        .smartCartShadow()
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
                .foregroundStyle(SmartCartTheme.navy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(SmartCartTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(SmartCartTheme.border, lineWidth: 1)
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
        .foregroundStyle(SmartCartTheme.green)
        .padding(.horizontal, 4)
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58))
                .foregroundStyle(SmartCartTheme.green)
            Text("Shopping guide complete")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(SmartCartTheme.navy)
                .multilineTextAlignment(.center)
            Text("\(appModel.shoppingItems.filter { $0.status == .added }.count) products marked added · \(appModel.shoppingItems.filter { $0.status == .skipped }.count) skipped")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)

            Button {
                openURL(appModel.retailerURL())
            } label: {
                Label("Visit Walmart to continue", systemImage: "arrow.up.right")
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
        .smartCartCard()
        .smartCartShadow()
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SmartCartAppearanceController.self) private var appearanceController
    @State private var creatorMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                accountHeader
                appearanceCard
                preferenceCard
                advancedToolsCard
                testerModeCard
                if appModel.featureFlags.internalTesterModeEnabled {
                    testerDashboard
                    connectorReadinessCard
                }
                if appModel.featureFlags.advancedToolsEnabled {
                    creatorCard
                }
                if let issue = appModel.persistenceIssue {
                    InfoBanner(
                        symbol: "externaldrive.badge.exclamationmark",
                        title: "Could not save local state",
                        message: issue,
                        color: SmartCartTheme.coral
                    )
                }
                privacyCard
                aboutCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var cleanLightModeEnabled: Binding<Bool> {
        Binding(
            get: { appearanceController.cleanLightModeEnabled },
            set: { appearanceController.cleanLightModeEnabled = $0 }
        )
    }

    private var appearanceCard: some View {
        Toggle(isOn: cleanLightModeEnabled) {
            HStack(spacing: 13) {
                Image(systemName: cleanLightModeEnabled.wrappedValue ? "sun.max.fill" : "moon.stars.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(width: 42, height: 42)
                    .background(SmartCartTheme.herbLight)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Clean light theme")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(
                        cleanLightModeEnabled.wrappedValue
                            ? SmartCartAppearance.cleanLight.subtitle
                            : "Off · \(SmartCartAppearance.midnight.subtitle)"
                    )
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
        }
        .tint(SmartCartTheme.green)
        .accessibilityIdentifier("smartcart.appearance.cleanLight")
        .smartCartCard()
    }

    private var accountHeader: some View {
        HStack(spacing: 15) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(SmartCartTheme.navy)

            VStack(alignment: .leading, spacing: 4) {
                Text("SmartCart shopper")
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Local prototype profile")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                StatusPill(title: "Private on device", symbol: "lock.fill")
            }
        }
        .padding(.top, 8)
    }

    private var preferenceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(
                title: "Executable preferences",
                subtitle: appModel.preferences.summary
            )
            ShoppingPreferenceControls()
        }
    }

    private var advancedToolsCard: some View {
        Toggle(
            isOn: Binding(
                get: { appModel.featureFlags.advancedToolsEnabled },
                set: { appModel.setAdvancedToolsEnabled($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Advanced testing tools")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Reveal experimental multi-stop, delivery-provider, and creator surfaces.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .tint(SmartCartTheme.green)
        .smartCartCard()
    }

    private var testerModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(
                isOn: Binding(
                    get: { appModel.featureFlags.internalTesterModeEnabled },
                    set: { appModel.setInternalTesterModeEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Internal tester mode")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Show the on-device funnel, import quality, and connector readiness.")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
            .tint(SmartCartTheme.green)

            Toggle(
                "Record anonymous events on this device",
                isOn: Binding(
                    get: { appModel.featureFlags.localAnalyticsEnabled },
                    set: { appModel.setLocalAnalyticsEnabled($0) }
                )
            )
            .font(.subheadline.weight(.semibold))
            .tint(SmartCartTheme.green)
        }
        .smartCartCard()
    }

    private var testerDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(
                    title: "Closed-beta funnel",
                    subtitle: "Local diagnostic events only · no recipe text or UPC values"
                )
                Spacer()
                Button("Clear") { appModel.clearLocalAnalytics() }
                    .font(.caption.weight(.bold))
            }

            let importCount = eventCount(.importStarted)
            let extractionCount = eventCount(.extractionCompleted)
            let matchCount = eventCount(.matchingCompleted)
            let handoffCount = eventCount(.retailerLinkOpened)

            HStack(spacing: 8) {
                testerMetric("Imports", value: importCount)
                testerMetric("Extracted", value: extractionCount)
                testerMetric("Matched", value: matchCount)
                testerMetric("Handoffs", value: handoffCount)
            }

            if let report = appModel.lastImportReport {
                InfoBanner(
                    symbol: "waveform.path.ecg",
                    title: "Last import · \(report.confidenceLabel)",
                    message: "\(report.sourcePageCount) page(s), \(report.ingredientLineCount) ingredients, \(report.reviewCount) review item(s), evidence preserved for \(report.sourceEvidenceCount), \(report.quantityAlternativeReviewCount) quantity alternative(s), layout \(report.layoutConfidence.formatted(.percent.precision(.fractionLength(0)))) with \(report.layoutAmbiguityCount) ambiguity flag(s), \(report.ignoredInstructionLineCount) instruction line(s) excluded, \(report.retryCount) OCR retry/retries, \(report.duration.formatted(.number.precision(.fractionLength(2))))s.",
                    color: report.confidenceScore >= 0.82 ? SmartCartTheme.green : SmartCartTheme.amber
                )
            }
        }
        .smartCartCard()
    }

    private var connectorReadinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Retail connector lab",
                subtitle: "Contracts are ready; only Walmart demo handoff is active"
            )

            ForEach(RetailConnectorRegistry.profiles) { profile in
                HStack(spacing: 11) {
                    Image(systemName: profile.state == .demoReady ? "checkmark.seal.fill" : "lock.fill")
                        .foregroundStyle(profile.state == .demoReady ? SmartCartTheme.green : SmartCartTheme.amber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SmartCartTheme.navy)
                        Text(profile.state.rawValue)
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                    Spacer()
                    Text(profile.supportsCart ? "Cart API" : profile.supportsDelivery ? "Delivery" : "Handoff")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(SmartCartTheme.canvas)
                        .clipShape(Capsule())
                }
            }
        }
        .smartCartCard()
    }

    private func eventCount(_ name: AnalyticsEventName) -> Int {
        appModel.analyticsEvents.filter { $0.name == name }.count
    }

    private func testerMetric(_ title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.bold())
                .foregroundStyle(SmartCartTheme.green)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(SmartCartTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var creatorCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle(isOn: $creatorMode) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Creator mode")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Experimental preview; not part of the public-beta shopping path.")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
            .tint(SmartCartTheme.green)

            if creatorMode {
                InfoBanner(
                    symbol: "person.2.fill",
                    title: "Creator tools preview",
                    message: "Shared pages can include recipe attribution, product links, and clear affiliate disclosures.",
                    color: SmartCartTheme.purple
                )
            }
        }
        .smartCartCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "Trust & privacy")
            trustRow("No Walmart credentials", "key.slash.fill")
            trustRow("No payment data stored", "creditcard.trianglebadge.exclamationmark")
            trustRow("On-device photo text recognition", "text.viewfinder")
            trustRow("Retailer confirms final checkout", "checkmark.shield.fill")
        }
        .smartCartCard()
    }

    private func trustRow(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 26)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SmartCartTheme.navy)
        }
    }

    private var aboutCard: some View {
        HStack {
            SmartCartLogo(compact: true)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SmartCart Beta 2")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Beta 2 foundation · local state schema 1")
                    .font(.caption2)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .smartCartCard(padding: 14)
    }
}
