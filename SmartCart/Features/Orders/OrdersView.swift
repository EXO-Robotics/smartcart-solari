import SafariServices
import SwiftUI

struct ProductMatchingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var activeSheet: LegacyMatchingSheet?
    @State private var isPreparingProducts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(
                    step: 6,
                    total: 6,
                    eyebrow: "Product preparation",
                    title: isPreparingProducts ? "Preparing Products…" : "Products prepared",
                    message: "SmartCart is preparing the products for this trip. Only matches that need a decision will interrupt you."
                )

                preparationCard
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .smartCartBackground()
        .navigationTitle("Prepare products")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("legacy-product-preparation")
        .task {
            await prepareProducts()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .productExceptions:
                ProductExceptionReviewSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
        }
    }

    private var preparationCard: some View {
        HStack(spacing: 14) {
            if isPreparingProducts {
                ProgressView()
                    .controlSize(.large)
                    .tint(SmartCartTheme.green)
                    .accessibilityIdentifier("legacy-product-preparation-progress")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(SmartCartTheme.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isPreparingProducts ? "Preparing Products…" : "Opening your shopping trip")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                Text("\(appModel.ingredientsToBuy.count) ingredients · \(appModel.retailerConfiguration.displayName)")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .smartCartCard()
        .smartCartShadow()
    }

    private func prepareProducts() async {
        guard !isPreparingProducts else { return }
        isPreparingProducts = true
        await appModel.startMatching()
        guard !Task.isCancelled else {
            isPreparingProducts = false
            return
        }
        isPreparingProducts = false

        if appModel.unresolvedMatchingExceptionItems.isEmpty {
            _ = appModel.continueToShoppingTrip()
        } else {
            activeSheet = .productExceptions
        }
    }
}

private enum LegacyMatchingSheet: String, Identifiable {
    case productExceptions

    var id: String { rawValue }
}

struct ProductExceptionReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var activeSheet: ProductExceptionSheetDestination?
    @State private var sheetReturnFocusItemID: UUID?
    @AccessibilityFocusState private var focusedExceptionItemID: UUID?

    private var unresolvedItems: [ShoppingListItem] {
        appModel.unresolvedMatchingExceptionItems
    }

    var body: some View {
        let reviewItems = unresolvedItems

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    exceptionHeader

                    Button {
                        activeSheet = .allProducts
                    } label: {
                        Label("View All Products", systemImage: "list.bullet.rectangle.portrait.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("product-exception-view-all-products")
                    .accessibilityHint("Opens the complete prepared product list without resolving these decisions")

                    LazyVStack(spacing: 14) {
                        ForEach(reviewItems) { item in
                            ProductExceptionCard(
                                item: item,
                                reasons: appModel.matchingExceptionReasons(for: item),
                                onSearchManually: {
                                    sheetReturnFocusItemID = item.id
                                    activeSheet = .manualSearch(
                                        itemID: item.id,
                                        url: manualSearchURL(for: item)
                                    )
                                },
                                onDecision: {
                                    focusAfterResolving(item.id, previousItems: reviewItems)
                                }
                            )
                            .accessibilityFocused($focusedExceptionItemID, equals: item.id)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .smartCartBackground()
            .navigationTitle("Review product choices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        returnToRecipeReady()
                    } label: {
                        Label("Recipe Ready", systemImage: "chevron.backward")
                    }
                    .accessibilityIdentifier("product-exception-return-recipe-ready")
                }
            }
            .accessibilityIdentifier("product-exception-review")
        }
        .sheet(item: $activeSheet, onDismiss: restoreFocusAfterSheet) { sheet in
            switch sheet {
            case .allProducts:
                AllPreparedProductsSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .manualSearch(_, let url):
                RetailerSafariSheet(
                    url: url,
                    configuration: appModel.retailerConfiguration
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var exceptionHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("PRODUCT DECISIONS", systemImage: "exclamationmark.bubble.fill")
                .smartEyebrow(SmartCartTheme.amber)
            Text("Review \(unresolvedItems.count) product \(unresolvedItems.count == 1 ? "choice" : "choices")")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.navy)
            Text("Everything else is ready. SmartCart stopped only where a fallback or product selection needs your approval.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .smartCartCard()
        .smartCartShadow()
        .accessibilityIdentifier("product-exception-header")
    }

    private func continueIfResolved() {
        guard appModel.unresolvedMatchingExceptionItems.isEmpty else { return }
        if appModel.continueToShoppingTrip() {
            dismiss()
        } else {
            returnToRecipeReady()
        }
    }

    private func focusAfterResolving(
        _ resolvedItemID: UUID,
        previousItems: [ShoppingListItem]
    ) {
        let remainingItems = appModel.unresolvedMatchingExceptionItems
        guard !remainingItems.isEmpty else {
            continueIfResolved()
            return
        }

        let remainingIDs = Set(remainingItems.map(\.id))
        let nextItemID: UUID
        if let resolvedIndex = previousItems.firstIndex(where: { $0.id == resolvedItemID }) {
            let candidates = Array(previousItems.dropFirst(resolvedIndex + 1))
                + Array(previousItems.prefix(resolvedIndex).reversed())
            nextItemID = candidates.first(where: { remainingIDs.contains($0.id) })?.id
                ?? remainingItems[0].id
        } else {
            nextItemID = remainingItems[0].id
        }

        Task { @MainActor in
            await Task.yield()
            focusedExceptionItemID = nextItemID
        }
    }

    private func restoreFocusAfterSheet() {
        continueIfResolved()
        guard let itemID = sheetReturnFocusItemID,
              unresolvedItems.contains(where: { $0.id == itemID }) else {
            sheetReturnFocusItemID = nil
            return
        }
        sheetReturnFocusItemID = nil
        Task { @MainActor in
            await Task.yield()
            focusedExceptionItemID = itemID
        }
    }

    private func manualSearchURL(for item: ShoppingListItem) -> URL {
        let query = item.ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch appModel.retailerConfiguration.retailer {
        case .walmart:
            var components = URLComponents(string: "https://www.walmart.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
            return components?.url ?? appModel.retailerURL()
        case .target:
            let terms = query
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }
                .joined(separator: "%2B")
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.target.com"
            components.percentEncodedPath = "/s/\(terms)"
            return components.url ?? appModel.retailerURL()
        case .kroger:
            var components = URLComponents(string: "https://www.kroger.com/search")
            components?.queryItems = [URLQueryItem(name: "query", value: query)]
            return components?.url ?? appModel.retailerURL()
        }
    }

    private func returnToRecipeReady() {
        dismiss()
        guard appModel.homePath.last != .recipeReady else { return }
        appModel.selectedTab = .home
        appModel.homePath = [.recipeReady]
    }
}

private enum ProductExceptionSheetDestination: Identifiable {
    case allProducts
    case manualSearch(itemID: UUID, url: URL)

    var id: String {
        switch self {
        case .allProducts:
            "all-products"
        case .manualSearch(let itemID, _):
            "manual-search-\(itemID.uuidString)"
        }
    }
}

private struct ProductExceptionCard: View {
    @Environment(AppModel.self) private var appModel

    let item: ShoppingListItem
    let reasons: [String]
    let onSearchManually: () -> Void
    let onDecision: () -> Void

    private var safeAlternatives: [RetailerProductRecord] {
        ReplacementOptionPolicy.resolvedCandidates(from: item.alternatives) { candidate in
            appModel.resolvedReplacementPackageCount(for: item, product: candidate)
        }
    }

    private var acceptTitle: String {
        item.product.isExactProductLink ? "Use this product" : "Add Search to Shopping Trip"
    }

    private var acceptSymbol: String {
        item.product.isExactProductLink ? "checkmark.circle.fill" : "plus.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ProductIcon(product: item.product, size: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.ingredient.name)
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("\(item.product.brand) \(item.product.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.product.isExactProductLink ? "Selected retailer product" : "Retailer search fallback")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.product.isExactProductLink ? SmartCartTheme.green : SmartCartTheme.amber)
                }

                Spacer(minLength: 0)
            }

            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Why this needs review")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                    ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                        Label(reason, systemImage: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SmartCartTheme.amber.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            Button {
                guard appModel.acceptMatchingException(itemID: item.id) else { return }
                onDecision()
            } label: {
                Label(acceptTitle, systemImage: acceptSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("product-exception-accept-\(item.id.uuidString)")
            .accessibilityHint(
                item.product.isExactProductLink
                    ? "Uses this product for the current shopping trip"
                    : "Adds this retailer search as the product page for this ingredient in the current shopping trip"
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    alternativeMenu
                    manualSearchButton
                    skipButton
                }
                VStack(spacing: 9) {
                    alternativeMenu
                    manualSearchButton
                    skipButton
                }
            }
        }
        .padding(14)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SmartCartTheme.amber.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product-exception-item-\(item.id.uuidString)")
    }

    @ViewBuilder
    private var alternativeMenu: some View {
        if !safeAlternatives.isEmpty {
            Menu {
                ForEach(safeAlternatives) { candidate in
                    Button(alternativeLabel(candidate)) {
                        appModel.selectAlternative(itemID: item.id, candidateID: candidate.id)
                        onDecision()
                    }
                }
            } label: {
                Label("Choose alternative", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("product-exception-alternative-\(item.id.uuidString)")
            .accessibilityHint("Shows compatible alternatives with a resolved package quantity")
        }
    }

    private var manualSearchButton: some View {
        Button(action: onSearchManually) {
            Label("Search at \(appModel.retailerConfiguration.displayName)", systemImage: "safari.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("product-exception-search-\(item.id.uuidString)")
        .accessibilityHint("Opens the retailer search. Returning does not resolve this product decision.")
    }

    private var skipButton: some View {
        Button {
            guard appModel.skipMatchingException(itemID: item.id) else { return }
            onDecision()
        } label: {
            Label("Skip this item", systemImage: "forward.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("product-exception-skip-\(item.id.uuidString)")
        .accessibilityHint("Excludes this item from the current shopping trip")
    }

    private func alternativeLabel(_ candidate: RetailerProductRecord) -> String {
        let price = candidate.hasObservedPrice
            ? candidate.price.formatted(.currency(code: "USD"))
            : "price unavailable"
        return "\(candidate.brand) \(candidate.name) · \(price)"
    }
}

private struct AllPreparedProductsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "All prepared products",
                        subtitle: "\(appModel.shoppingItems.count) products · this list does not block your exception review"
                    )

                    ForEach(appModel.shoppingItems) { item in
                        ShoppingProductRow(
                            item: item,
                            isReadOnly: appModel.activeShoppingSessionIsImmutable
                        )
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .smartCartBackground()
            .navigationTitle("All Products")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("all-prepared-products-done")
                }
            }
            .accessibilityIdentifier("all-prepared-products")
        }
    }
}

struct ShoppingListReviewView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        retailerReview
    }

    private var retailerReview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                listHeader

                if appModel.activeShoppingSessionIsImmutable {
                    InfoBanner(
                        symbol: "lock.fill",
                        title: "Completed trip · read only",
                        message: "Products, quantities, and shopping outcomes are frozen for reconciliation. Choose Edit as new trip before making any changes.",
                        color: SmartCartTheme.green
                    )
                }

                VStack(alignment: .leading, spacing: 11) {
                    SectionHeader(
                        title: "Matched products",
                        subtitle: appModel.activeShoppingSessionIsImmutable
                            ? "\(appModel.shoppingItems.count) items · frozen completed snapshot"
                            : "\(appModel.shoppingItems.count) items · change any match"
                    )

                    ForEach(appModel.shoppingItems) { item in
                        ShoppingProductRow(
                            item: item,
                            isReadOnly: appModel.activeShoppingSessionIsImmutable
                        )
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
                if appModel.activeShoppingSessionIsImmutable {
                    VStack(spacing: 9) {
                        if !activeSessionIsCommitted {
                            Button {
                                appModel.beginGuidedShopping()
                            } label: {
                                HStack {
                                    Label("Review shopping results", systemImage: "checkmark.seal.fill")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }

                        Button {
                            _ = appModel.forkCompletedShoppingTrip()
                        } label: {
                            Label("Edit as new trip", systemImage: "doc.on.doc.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityHint("Creates an editable copy and preserves this completed trip")
                    }
                } else {
                    Button {
                        appModel.beginGuidedShopping()
                    } label: {
                        HStack {
                            Label(retailerGuideButtonTitle, systemImage: "safari.fill")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var activeSessionIsCommitted: Bool {
        guard let sessionID = appModel.activeShoppingSessionID else { return false }
        return appModel.shoppingSession(id: sessionID)?.isCommitted == true
    }

    private var retailerGuideButtonTitle: String {
        if appModel.retailerGuideIsComplete {
            return "Review shopping results"
        }
        if appModel.guidedCompletedCount > 0 {
            return "Resume \(appModel.retailerConfiguration.displayName) Shopping Trip"
        }
        return "Start \(appModel.retailerConfiguration.displayName) Shopping Trip"
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: appModel.isMealPrepShopping ? "calendar.badge.checkmark" : appModel.activeRecipe.heroSymbol)
                    .font(.title.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 62, height: 62)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .shadow(color: SmartCartTheme.mintGlow, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.currentShoppingTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(appModel.isMealPrepShopping
                        ? "\(appModel.currentShoppingMealPrepSnapshot?.recipeCount ?? 0) recipes · \(appModel.primaryStore.name)"
                        : "\(appModel.desiredServings) servings · \(appModel.primaryStore.name)")
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
            totalRow("Taxes and fees", value: "Confirmed by \(appModel.retailerConfiguration.displayName)")
            totalRow("Variable-weight changes", value: "Confirmed by \(appModel.retailerConfiguration.displayName)")
            totalRow("Final total", value: "Confirmed by \(appModel.retailerConfiguration.displayName)")
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

    @ViewBuilder
    private var shareActions: some View {
        if appModel.activeShoppingSessionIsImmutable {
            ShareLink(item: appModel.shareText) {
                Label("Share read-only list", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        } else {
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
    }

    private var transparencyDisclosure: some View {
        InfoBanner(
            symbol: "checkmark.shield.fill",
            title: "Opens in Safari, not account linking",
            message: "SmartCart opens selected \(appModel.retailerConfiguration.displayName) products and remembers only what you report. The retailer owns sign-in, live availability, list or cart actions, fulfillment, payment, and checkout.",
            color: SmartCartTheme.green
        )
    }
}

private struct ShoppingProductRow: View {
    @Environment(AppModel.self) private var appModel
    let item: ShoppingListItem
    let isReadOnly: Bool

    private var selectableAlternatives: [RetailerProductRecord] {
        ReplacementOptionPolicy.resolvedCandidates(from: item.alternatives) { candidate in
            appModel.resolvedReplacementPackageCount(for: item, product: candidate)
        }
    }

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

                if !isReadOnly, !selectableAlternatives.isEmpty {
                    Menu {
                        ForEach(selectableAlternatives) { candidate in
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
                    .smartCartMinimumHitTarget()
                    .accessibilityIdentifier("shopping-product-change-\(item.id.uuidString)")
                }

                VStack(spacing: 3) {
                    Text(isReadOnly ? "FROZEN QTY" : "PLANNED QTY")
                        .smartEyebrow(SmartCartTheme.mutedInk)
                    if isReadOnly {
                        Text("\(item.purchaseQuantity)")
                            .font(.caption.bold())
                            .frame(minWidth: 12)
                            .accessibilityLabel("Frozen quantity")
                            .accessibilityValue("\(item.purchaseQuantity) packages")
                    } else {
                        HStack(spacing: 8) {
                            quantityButton("minus", delta: -1)
                            Text("\(item.purchaseQuantity)")
                                .font(.caption.bold())
                                .frame(minWidth: 12)
                            quantityButton("plus", delta: 1)
                        }
                    }
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
        .accessibilityIdentifier("shopping-product-row-\(item.id.uuidString)")
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
        .smartCartMinimumHitTarget()
        .accessibilityLabel(symbol == "plus" ? "Increase planned quantity" : "Decrease planned quantity")
        .accessibilityValue("\(item.purchaseQuantity) packages")
        .accessibilityIdentifier("shopping-product-quantity-\(delta > 0 ? "increase" : "decrease")-\(item.id.uuidString)")
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SmartCartAppearanceController.self) private var appearanceController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                accountHeader
                appearanceCard
                preferenceCard
                testerModeCard
                if appModel.featureFlags.internalTesterModeEnabled {
                    testerDashboard
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
                title: "Shopping preferences",
                subtitle: appModel.preferences.summary
            )
            ShoppingPreferenceControls()
        }
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
                testerMetric("Retailer opens", value: handoffCount)
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

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "Trust & privacy")
            trustRow("No retailer credentials", "key.slash.fill")
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
