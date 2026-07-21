import SafariServices
import SwiftUI
import UIKit

struct RetailerSafariHandoffView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var sheetDestination: RetailerGuideSheetDestination?
    @State private var presentedProductSessionID: UUID?
    @State private var presentedProductItemID: UUID?
    @State private var productDismissalIsExplicit = false
    @State private var isBeginningTrip = false
    @State private var prewarmingToken: SFSafariViewController.PrewarmingToken?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if appModel.shoppingItems.isEmpty {
                    EmptyStateView(
                        symbol: "cart",
                        title: "No shopping trip yet",
                        message: "Match products before starting the \(retailerName) Shopping Trip."
                    )
                } else if !appModel.retailerSetupIsComplete {
                    retailerSetupView
                } else if appModel.retailerGuideIsComplete {
                    completionView
                } else if appModel.activeShoppingSessionIsImmutable {
                    immutableTripView
                } else if !appModel.retailerSessionIsInProgress {
                    tripPreparationView
                } else if let item = appModel.currentGuidedItem {
                    guideHeader
                    productCard(item)
                    instructionCard
                    replacementAndSkip
                    navigationControls
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .smartCartBackground()
        .navigationTitle("Shop at \(retailerName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appModel.retailerSessionIsInProgress,
               !appModel.activeShoppingSessionIsImmutable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pauseTripAndReturnHome()
                    } label: {
                        Label("Pause Trip", systemImage: "pause.fill")
                    }
                    .accessibilityIdentifier("retailer-session-pause")
                }
            }
        }
        .sheet(item: $sheetDestination, onDismiss: sheetDidDismiss) { destination in
            switch destination {
            case .product(let sessionID, let itemID, let url, _):
                RetailerTripSafariSheet(
                    sessionID: sessionID,
                    itemID: itemID,
                    url: url,
                    targetSearchURL: targetSearchURL(for: itemID),
                    configuration: appModel.retailerConfiguration,
                    position: appModel.guidedIndex + 1,
                    total: appModel.shoppingItems.count,
                    productIdentity: productIdentity(for: itemID),
                    replacementCandidates: safeReplacementCandidates,
                    onInitialLoad: { didLoadSuccessfully in
                        if didLoadSuccessfully {
                            prewarmAfterItem(itemID)
                        }
                    },
                    onNext: { advanceFromProduct(.visited, itemID: itemID, sessionID: sessionID) },
                    onUnavailable: { advanceFromProduct(.unavailable, itemID: itemID, sessionID: sessionID) },
                    onSkip: { advanceFromProduct(.skipped, itemID: itemID, sessionID: sessionID) },
                    onReplacement: { candidateID in
                        replaceCurrentProduct(candidateID: candidateID, itemID: itemID, sessionID: sessionID)
                    },
                    onPause: {
                        pauseTripAndReturnHome(sessionID: sessionID, itemID: itemID)
                    },
                    onAmbiguousDismiss: {
                        pauseTripAndReturnHome(sessionID: sessionID, itemID: itemID)
                    }
                )
                .id(destination.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .retailer(let url):
                RetailerSafariSheet(
                    url: url,
                    configuration: appModel.retailerConfiguration
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task {
            await Task.yield()
            beginTripAndOpenCurrentProduct()
        }
        .onDisappear { releasePrewarming() }
    }

    private var retailerName: String {
        appModel.retailerConfiguration.displayName
    }

    private func productIdentity(for itemID: UUID) -> String {
        guard let item = appModel.shoppingItems.first(where: { $0.id == itemID }) else {
            return "Current product"
        }
        return "\(item.ingredient.name), \(item.product.brand) \(item.product.name)"
    }

    private func targetSearchURL(for itemID: UUID) -> URL {
        guard let item = appModel.shoppingItems.first(where: { $0.id == itemID }) else {
            return ShoppingRetailer.target.configuration.homeURL
        }
        return appModel.targetSearchURL(for: item)
    }

    private var safeReplacementCandidates: [RetailerProductRecord] {
        guard let item = appModel.currentGuidedItem else { return [] }
        return ReplacementOptionPolicy.resolvedCandidates(from: item.alternatives) { candidate in
            appModel.resolvedReplacementPackageCount(for: item, product: candidate)
        }
    }

    private var immutableTripView: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(SmartCartTheme.green)
            Text("Completed trip · read only")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(SmartCartTheme.navy)
                .multilineTextAlignment(.center)
            Text("This trip’s products, quantities, and outcomes are frozen. Create a new trip before making changes.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .multilineTextAlignment(.center)
            Button {
                _ = appModel.forkCompletedShoppingTrip()
            } label: {
                Label("Edit as new trip", systemImage: "doc.on.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Creates an editable copy and preserves this completed trip")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .smartCartCard()
        .smartCartShadow()
    }

    private var retailerSetupView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("RETAILER SETUP")
                    .smartEyebrow()
                Text("Prepare \(retailerName)")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(SmartCartTheme.navy)
                Text("SmartCart never asks for your retailer password. Sign in and prepare your list directly with \(retailerName), then come back.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 14) {
                setupStep("1", "Open \(retailerName) and sign in.")
                setupStep("2", "Create or choose \(appModel.retailerConfiguration.savedListName).")
                setupStep("3", "Return here. SmartCart can remember your confirmation on this device.")
            }

            Button {
                appModel.recordRetailerSetupStarted()
                sheetDestination = .retailer(appModel.retailerSetupURL())
            } label: {
                HStack {
                    Text("Open \(retailerName) setup")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(BlueButtonStyle())
            .accessibilityIdentifier("retailer-setup-open")

            Button {
                appModel.completeRetailerSetup()
                Task { @MainActor in
                    await Task.yield()
                    beginTripAndOpenCurrentProduct()
                }
            } label: {
                Label("I’m signed in and my list is ready", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("retailer-setup-complete")
            .accessibilityHint("Records your confirmation on this device. SmartCart cannot verify retailer sign-in or list setup.")

            InfoBanner(
                symbol: "hand.raised.fill",
                title: "You stay in control",
                message: "This only records your confirmation. SmartCart cannot see your account, verify sign-in, or create a retailer list.",
                color: SmartCartTheme.amber
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .smartCartCard()
        .smartCartShadow()
    }

    private func setupStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.onAccent)
                .frame(width: 27, height: 27)
                .background(SmartCartTheme.green)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SmartCartTheme.navy)
            Spacer(minLength: 0)
        }
    }

    private var tripPreparationView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(SmartCartTheme.green)
            Text(appModel.guidedCompletedCount > 0 ? "Resuming your shopping trip…" : "Opening the first retailer product…")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.navy)
                .multilineTextAlignment(.center)
            Text("Closing the retailer page pauses at the current item. Only Next Item, unavailable, or skip advances the trip.")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .multilineTextAlignment(.center)
            if appModel.persistenceIssue != nil {
                Button("Retry") { beginTripAndOpenCurrentProduct() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("retailer-session-retry")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .smartCartCard()
        .smartCartShadow()
        .accessibilityElement(children: .contain)
    }

    private var guideHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Item \(appModel.guidedIndex + 1) of \(appModel.shoppingItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                Spacer()
                Text(appModel.retailerSessionProgressText)
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SmartCartTheme.border)
                    Capsule()
                        .fill(SmartCartTheme.green)
                        .frame(
                            width: proxy.size.width * CGFloat(appModel.guidedCompletedCount) /
                                CGFloat(max(1, appModel.shoppingItems.count))
                        )
                }
            }
            .frame(height: 7)
        }
    }

    private func productCard(_ item: ShoppingListItem) -> some View {
        VStack(spacing: 17) {
            ProductIcon(product: item.product, size: 118)

            VStack(spacing: 5) {
                Text("RECIPE NEEDS")
                    .smartEyebrow(SmartCartTheme.green)
                Text("\(item.requestedQuantity) \(item.ingredient.name)")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.center)
                Divider().padding(.vertical, 4)
                Text("SELECTED \(retailerName.uppercased()) PRODUCT")
                    .smartEyebrow(SmartCartTheme.mutedInk)
                Text(item.product.brand)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                Text(item.product.name)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.center)
                Text("\(item.product.package) · quantity \(item.purchaseQuantity)")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            if item.status != .waiting {
                Label(outcomeLabel(item.status), systemImage: outcomeSymbol(item.status))
                    .font(.caption.bold())
                    .foregroundStyle(SmartCartTheme.green)
            }

            Button {
                openProduct(item)
            } label: {
                HStack {
                    Text(item.product.isExactProductLink ? "Open at \(retailerName)" : "Search at \(retailerName)")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(BlueButtonStyle())
            .accessibilityIdentifier("retailer-product-open")

            Text(
                item.product.isExactProductLink
                    ? "This opens the selected item. \(retailerName) controls sign-in, local availability, price, quantity, list or cart actions, and checkout."
                    : "No eligible exact record was available, so this opens a clearly labeled \(retailerName) search."
            )
            .font(.caption)
            .foregroundStyle(SmartCartTheme.secondaryInk)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .smartCartCard()
        .smartCartShadow()
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: "At \(retailerName)", subtitle: "You stay in control of every retailer action")
            ForEach(Array(appModel.retailerConfiguration.instructions.enumerated()), id: \.offset) { index, text in
                instructionRow(String(index + 1), text)
            }
        }
        .smartCartCard()
    }

    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.onAccent)
                .frame(width: 23, height: 23)
                .background(SmartCartTheme.green)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.navy)
            Spacer(minLength: 0)
        }
    }

    private var replacementAndSkip: some View {
        ViewThatFits {
            HStack(spacing: 9) {
                if !safeReplacementCandidates.isEmpty {
                    replacementMenu
                }
                Button {
                    recordOutcome(.skipped)
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 9) {
                if !safeReplacementCandidates.isEmpty {
                    replacementMenu
                }
                Button {
                    recordOutcome(.skipped)
                } label: {
                    Label("Skip item", systemImage: "forward.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var replacementMenu: some View {
        Menu {
            if let item = appModel.currentGuidedItem {
                ForEach(safeReplacementCandidates) { candidate in
                    Button("\(candidate.brand) \(candidate.name)") {
                        appModel.selectAlternative(itemID: item.id, candidateID: candidate.id)
                    }
                }
            }
        } label: {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
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
        .disabled(safeReplacementCandidates.isEmpty)
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
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58))
                .foregroundStyle(SmartCartTheme.green)
            VStack(spacing: 5) {
                Text("Ready to finish shopping")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.center)
                Text("These results reflect only the SmartCart actions you explicitly chose. Visiting a page is not proof of a retailer action or purchase.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: completionMetricColumns, spacing: 10) {
                summaryMetric("Advanced only", value: appModel.retailerVisitedCount, symbol: "safari.fill")
                summaryMetric("Reported saved to list", value: appModel.savedForLaterCount, symbol: "bookmark.fill")
                summaryMetric("Reported added to cart", value: appModel.retailerAddedCount, symbol: "cart.fill")
                summaryMetric("Unavailable", value: appModel.retailerUnavailableCount, symbol: "exclamationmark.triangle.fill")
                summaryMetric("Skipped", value: appModel.retailerSkippedCount, symbol: "forward.fill")
            }

            HStack {
                Text("Original seeded plan · not live")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                Spacer()
                Text(appModel.estimatedTotal, format: .currency(code: "USD"))
                    .font(.title3.bold())
                    .foregroundStyle(SmartCartTheme.navy)
            }
            .padding(14)
            .background(SmartCartTheme.canvasRaise)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                sheetDestination = .retailer(appModel.retailerListsURL())
            } label: {
                HStack {
                    Text("Open \(appModel.retailerConfiguration.savedListName)")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(BlueButtonStyle())
            .accessibilityIdentifier("retailer-open-in-safari")

            InfoBanner(
                symbol: "info.circle.fill",
                title: "Finish at \(retailerName)",
                message: "\(retailerName) confirms your location, live inventory, quantities, substitutions, final prices, list or cart actions, fulfillment, payment, and checkout.",
                color: appModel.selectedRetailer == .walmart ? SmartCartTheme.walmartBlue : .red
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Did you place this order?")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Your pantry changes only after you choose to review and confirm what you bought.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appModel.startShoppingReconciliation()
            } label: {
                Label("Yes, update pantry", systemImage: "cabinet.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("shopping-completion-update-pantry")
            .accessibilityHint("Opens a review so you can report what was bought before pantry stock changes")

            Button {
                appModel.resetFlow()
            } label: {
                Label("Not yet", systemImage: "clock.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("shopping-completion-not-yet")
            .accessibilityHint("Closes this screen and keeps the pantry update reminder")

            Button {
                archivePantryUpdateReminder()
            } label: {
                Label("Archive without pantry update", systemImage: "archivebox.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("shopping-completion-archive")
            .accessibilityHint("Closes the reminder without changing pantry stock")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .smartCartCard()
        .smartCartShadow()
    }

    private var completionMetricColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func archivePantryUpdateReminder() {
        guard let sessionID = appModel.activeShoppingSessionID,
              appModel.archivePantryUpdateReminder(sessionID: sessionID) else { return }
        appModel.resetFlow()
    }

    private func summaryMetric(_ title: String, value: Int, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(SmartCartTheme.green)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(SmartCartTheme.navy)
            Text(title)
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(SmartCartTheme.canvasRaise)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private func openProduct(_ item: ShoppingListItem) {
        guard let sessionID = appModel.activeShoppingSessionID else { return }
        openProduct(item, sessionID: sessionID)
    }

    private func openProduct(
        _ item: ShoppingListItem,
        sessionID: UUID,
        refreshPrewarming: Bool = true,
        isExplicitTransition: Bool = false
    ) {
        appModel.recordRetailerProductOpened(itemID: item.id)
        presentedProductSessionID = sessionID
        presentedProductItemID = item.id
        productDismissalIsExplicit = isExplicitTransition
        if refreshPrewarming {
            prewarmAfterItem(item.id)
        }
        sheetDestination = .product(sessionID, item.id, appModel.productURL(for: item), UUID())
    }

    private func sheetDidDismiss() {
        guard presentedProductSessionID != nil, presentedProductItemID != nil else { return }
        if productDismissalIsExplicit {
            productDismissalIsExplicit = false
            // Swapping one product destination for the next dismisses the old
            // sheet before SwiftUI presents the replacement. Keep the new
            // product identity intact; a true Pause/final dismissal clears it.
            if sheetDestination == nil {
                presentedProductSessionID = nil
                presentedProductItemID = nil
            }
            return
        }
        guard let sessionID = presentedProductSessionID,
              let itemID = presentedProductItemID else { return }
        presentedProductSessionID = nil
        presentedProductItemID = nil
        pauseTripAndReturnHome(sessionID: sessionID, itemID: itemID)
    }

    private func beginTripAndOpenCurrentProduct() {
        guard !isBeginningTrip,
              sheetDestination == nil,
              appModel.retailerSetupIsComplete,
              !appModel.retailerGuideIsComplete,
              !appModel.activeShoppingSessionIsImmutable else { return }
        isBeginningTrip = true
        defer { isBeginningTrip = false }
        if !appModel.retailerSessionIsInProgress,
           !appModel.startOrResumeRetailerShoppingSession() {
            return
        }
        guard let sessionID = appModel.activeShoppingSessionID,
              let item = appModel.currentGuidedItem,
              item.status == .waiting else { return }
        openProduct(item, sessionID: sessionID)
    }

    private func advanceFromProduct(
        _ outcome: GuidedItemStatus,
        itemID: UUID,
        sessionID: UUID
    ) {
        guard appModel.recordRetailerOutcome(outcome, for: itemID, sessionID: sessionID) else { return }
        if appModel.retailerGuideIsComplete {
            productDismissalIsExplicit = true
            sheetDestination = nil
            return
        }
        guard let nextItem = appModel.currentGuidedItem, nextItem.status == .waiting else { return }
        // Retain the token for the page we are about to open. Its successful
        // initial load refreshes prewarming for the following waiting item.
        openProduct(
            nextItem,
            sessionID: sessionID,
            refreshPrewarming: false,
            isExplicitTransition: true
        )
    }

    private func replaceCurrentProduct(candidateID: UUID, itemID: UUID, sessionID: UUID) {
        guard appModel.selectAlternative(itemID: itemID, candidateID: candidateID),
              let updatedItem = appModel.shoppingItems.first(where: { $0.id == itemID }) else { return }
        openProduct(
            updatedItem,
            sessionID: sessionID,
            refreshPrewarming: false,
            isExplicitTransition: true
        )
    }

    private func pauseTripAndReturnHome(sessionID: UUID? = nil, itemID: UUID? = nil) {
        let didPause: Bool
        if let sessionID, let itemID {
            didPause = appModel.handleAmbiguousRetailerBrowserDismissal(
                sessionID: sessionID,
                itemID: itemID
            )
        } else {
            didPause = appModel.pauseRetailerShoppingSession()
        }
        guard didPause else { return }
        releasePrewarming()
        productDismissalIsExplicit = true
        sheetDestination = nil
        Task { @MainActor in
            await Task.yield()
            appModel.selectedTab = .home
            appModel.homePath = []
        }
    }

    private func prewarmAfterItem(_ itemID: UUID) {
        releasePrewarming()
        guard let itemIndex = appModel.shoppingItems.firstIndex(where: { $0.id == itemID }) else { return }
        let laterItems = Array(appModel.shoppingItems.dropFirst(itemIndex + 1))
        let earlierItems = Array(appModel.shoppingItems.prefix(itemIndex))
        guard let nextItem = (laterItems + earlierItems).first(where: { $0.status == .waiting }) else { return }
        let nextURL = appModel.productURL(for: nextItem)
        guard nextURL.scheme == "https" || nextURL.scheme == "http" else { return }
        prewarmingToken = SFSafariViewController.prewarmConnections(to: [nextURL])
    }

    private func releasePrewarming() {
        prewarmingToken?.invalidate()
        prewarmingToken = nil
    }

    private func recordOutcome(_ outcome: GuidedItemStatus) {
        guard let sessionID = appModel.activeShoppingSessionID,
              let item = appModel.currentGuidedItem else { return }
        appModel.recordRetailerOutcome(outcome, for: item.id, sessionID: sessionID)
    }

    private func outcomeLabel(_ status: GuidedItemStatus) -> String {
        switch status {
        case .waiting: "Awaiting answer"
        case .visited: "Retailer page visited"
        case .added, .savedToWishlist: "Reported added to \(appModel.retailerConfiguration.savedListName)"
        case .addedToCart: "Reported added at \(retailerName)"
        case .unavailable: "Reported unavailable"
        case .skipped: "Skipped"
        }
    }

    private func outcomeSymbol(_ status: GuidedItemStatus) -> String {
        switch status {
        case .waiting: "circle"
        case .visited: "checkmark.circle.fill"
        case .added, .savedToWishlist: "bookmark.fill"
        case .addedToCart: "cart.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .skipped: "forward.fill"
        }
    }
}

private enum RetailerGuideSheetDestination: Identifiable {
    case product(UUID, UUID, URL, UUID)
    case retailer(URL)

    var id: String {
        switch self {
        case .product(let sessionID, let itemID, _, let presentationID):
            "product-\(sessionID.uuidString)-\(itemID.uuidString)-\(presentationID.uuidString)"
        case .retailer(let url): "retailer-\(url.absoluteString)"
        }
    }
}

enum RetailerTripPageLoadState: Equatable {
    case loading
    case loaded
    case failed

    var canRecordVisited: Bool { self == .loaded }

    var accessibilityDescription: String {
        switch self {
        case .loading: "Retailer page loading"
        case .loaded: "Retailer page loaded"
        case .failed: "Retailer page failed to load"
        }
    }
}

private struct RetailerTripSafariSheet: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let sessionID: UUID
    let itemID: UUID
    let url: URL
    let targetSearchURL: URL
    let configuration: RetailerGuideConfiguration
    let position: Int
    let total: Int
    let productIdentity: String
    let replacementCandidates: [RetailerProductRecord]
    let onInitialLoad: (Bool) -> Void
    let onNext: () -> Void
    let onUnavailable: () -> Void
    let onSkip: () -> Void
    let onReplacement: (UUID) -> Void
    let onPause: () -> Void
    let onAmbiguousDismiss: () -> Void

    @State private var loadState = RetailerTripPageLoadState.loading
    @State private var loadAttempt = 0
    @State private var checkedTargetURL: URL?
    @State private var showsHelp = false

    var body: some View {
        VStack(spacing: 0) {
            tripBar
                // Large-detent Safari sheets can report a zero top safe-area
                // inset while still extending beneath the status bar. Keep
                // the trip controls below that system-owned region so Pause,
                // position, and Next Item remain visible and tappable.
                .padding(.top, 44)
            Divider()

            if loadState == .failed {
                loadFailureView
            } else {
                RetailerSafariView(
                    url: displayedURL,
                    onInitialLoad: { didLoadSuccessfully in
                        loadState = didLoadSuccessfully ? .loaded : .failed
                        onInitialLoad(didLoadSuccessfully)
                    },
                    onFinish: onAmbiguousDismiss
                )
                .id("\(itemID.uuidString)-\(displayedURL.absoluteString)-\(loadAttempt)")
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(SmartCartTheme.paper.ignoresSafeArea())
        .alert("Shopping Trip help", isPresented: $showsHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("SmartCart cannot inspect this retailer page or verify list, cart, order, purchase, price, or availability. Next Item records only that you chose to advance after viewing the page.")
        }
        .onChange(of: loadState) { _, newState in
            announceLoadState(newState)
        }
    }

    private var tripBar: some View {
        VStack(spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    tripPositionLabel
                    pauseButton
                        .frame(maxWidth: .infinity)
                    moreMenu
                        .frame(maxWidth: .infinity)
                    nextButton
                        .frame(maxWidth: .infinity)
                    checkTargetButton
                        .frame(maxWidth: .infinity)
                    retailerOwnershipLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 6) {
                        pauseButton
                        moreMenu
                    }
                    Spacer(minLength: 4)
                    tripPositionLabel
                        .padding(.top, 12)
                    Spacer(minLength: 4)
                    VStack(spacing: 6) {
                        nextButton
                        checkTargetButton
                    }
                }
                retailerOwnershipLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(SmartCartTheme.green)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(SmartCartTheme.paper)
    }

    private var tripPositionLabel: some View {
        Text("Item \(position) of \(total)")
            .font(.subheadline.bold())
            .foregroundStyle(SmartCartTheme.navy)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .accessibilityLabel("Item \(position) of \(total), \(productIdentity)")
            .accessibilityValue(loadState.accessibilityDescription)
            .accessibilityAddTraits(.isHeader)
    }

    private var pauseButton: some View {
        Button(action: onPause) {
            Label("Pause", systemImage: "pause.fill")
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(SmartCartTheme.green)
                .padding(.horizontal, 12)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .frame(minWidth: 44, minHeight: 44)
                .background(SmartCartTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(SmartCartTheme.borderStrong, lineWidth: 1)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Pause shopping trip")
        .accessibilityHint("Saves this shopping trip without advancing the current item")
        .accessibilityIdentifier("retailer-trip-pause")
    }

    private var nextButton: some View {
        Button(action: onNext) {
            Label("Next Item", systemImage: "arrow.right.circle.fill")
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    loadState.canRecordVisited
                        ? SmartCartTheme.onAccent
                        : SmartCartTheme.mutedInk
                )
                .padding(.horizontal, 14)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    loadState.canRecordVisited
                        ? SmartCartTheme.green
                        : SmartCartTheme.paperElevated
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    if !loadState.canRecordVisited {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(SmartCartTheme.border, lineWidth: 1)
                    }
                }
                .shadow(
                    color: loadState.canRecordVisited ? SmartCartTheme.mintGlow : .clear,
                    radius: 10,
                    y: 3
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint("Records only that you advanced after viewing this page. No list, cart, order, or purchase result is inferred.")
        .accessibilityValue(loadState.accessibilityDescription)
        .accessibilityIdentifier("retailer-trip-next")
        .disabled(!loadState.canRecordVisited)
    }

    private var retailerOwnershipLabel: some View {
        Label(retailerOwnershipText, systemImage: "lock.shield.fill")
            .font(.caption2)
            .foregroundStyle(SmartCartTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var checkTargetButton: some View {
        Button {
            checkedTargetURL = targetSearchURL
            loadState = .loading
            loadAttempt += 1
        } label: {
            Label("Check Target", systemImage: "magnifyingglass")
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(SmartCartTheme.onAccent)
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(SmartCartTheme.green)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .frame(minHeight: 44)
        .accessibilityIdentifier("retailer-trip-check-target")
        .accessibilityHint("Opens a fresh Target search for this ingredient without changing the shopping trip")
    }

    private var moreMenu: some View {
        Menu {
            Button("Report product unavailable", systemImage: "exclamationmark.triangle.fill", action: onUnavailable)
                .accessibilityIdentifier("retailer-trip-report-unavailable")

            if !replacementCandidates.isEmpty {
                Menu("Choose replacement in SmartCart", systemImage: "arrow.triangle.2.circlepath") {
                    ForEach(replacementCandidates) { candidate in
                        Button("\(candidate.brand) \(candidate.name)") {
                            onReplacement(candidate.id)
                        }
                        .accessibilityIdentifier("retailer-trip-replacement-\(candidate.id.uuidString)")
                    }
                }
                .accessibilityIdentifier("retailer-trip-choose-replacement")
            }

            Button("Skip item in SmartCart", systemImage: "forward.fill", action: onSkip)
                .accessibilityIdentifier("retailer-trip-skip")
            Button("Reload retailer page", systemImage: "arrow.clockwise") {
                loadState = .loading
                loadAttempt += 1
            }
            .accessibilityIdentifier("retailer-trip-reload")
            Button("Help and retailer disclaimer", systemImage: "questionmark.circle") {
                showsHelp = true
            }
            .accessibilityIdentifier("retailer-trip-help")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .frame(minWidth: 72, minHeight: 48)
                .background(SmartCartTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(SmartCartTheme.borderStrong, lineWidth: 1)
                }
        }
        .accessibilityIdentifier("retailer-trip-more")
        .accessibilityLabel("More actions")
    }

    private var displayedURL: URL {
        checkedTargetURL ?? url
    }

    private var retailerOwnershipText: String {
        guard checkedTargetURL != nil else {
            return "Shopping stays with \(configuration.displayName)"
        }
        if configuration.retailer == .target {
            return "Fresh Target search · shopping trip unchanged"
        }
        return "Checking Target · trip stays with \(configuration.displayName)"
    }

    private var loadFailureView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 46))
                    .foregroundStyle(SmartCartTheme.amber)
                    .accessibilityHidden(true)
                Text("This retailer page did not load")
                    .font(.title3.bold())
                    .foregroundStyle(SmartCartTheme.navy)
                    .accessibilityAddTraits(.isHeader)
                Text("The item is still waiting. Retry here, open the page externally, skip it, or pause the trip.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    loadState = .loading
                    loadAttempt += 1
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("retailer-trip-retry")

                Button("Open externally") { openURL(url) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("retailer-trip-open-externally")

                Button("Skip item in SmartCart", action: onSkip)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("retailer-trip-load-failure-skip")

                Button("Pause shopping", action: onPause)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("retailer-trip-load-failure-pause")
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SmartCartTheme.canvas)
    }

    private func announceLoadState(_ state: RetailerTripPageLoadState) {
        let message: String
        switch state {
        case .loading:
            message = "Loading retailer page for \(productIdentity)."
        case .loaded:
            message = "Retailer page loaded for \(productIdentity). Next Item is available."
        case .failed:
            message = "Retailer page for \(productIdentity) did not load. Retry or choose another action."
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

}

struct RetailerSafariSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let configuration: RetailerGuideConfiguration

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(SmartCartTheme.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Secure \(retailerName) page")
                        .font(.subheadline.bold())
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Sign-in and shopping stay with \(retailerName)")
                        .font(.caption2)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                Button("Return to SmartCart") {
                    dismiss()
                }
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.green)
                .accessibilityIdentifier("retailer-safari-return")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .padding(.top, 46)
            .background(SmartCartTheme.paper)

            Divider()

            RetailerSafariView(url: url, onFinish: { dismiss() })
                .ignoresSafeArea(edges: .bottom)
        }
        .background(SmartCartTheme.paper.ignoresSafeArea())
    }

    private var retailerName: String {
        configuration.displayName
    }
}

struct RetailerSafariView: UIViewControllerRepresentable {
    let url: URL
    var onInitialLoad: (Bool) -> Void = { _ in }
    var onFinish: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(SmartCartTheme.green)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIViewController(
        _ uiViewController: SFSafariViewController,
        coordinator: Coordinator
    ) {
        uiViewController.delegate = nil
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var parent: RetailerSafariView

        init(parent: RetailerSafariView) {
            self.parent = parent
        }

        func safariViewController(
            _ controller: SFSafariViewController,
            didCompleteInitialLoad didLoadSuccessfully: Bool
        ) {
            parent.onInitialLoad(didLoadSuccessfully)
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            parent.onFinish()
        }
    }
}
