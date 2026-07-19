import SafariServices
import SwiftUI

struct RetailerSafariHandoffView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    @State private var sheetDestination: RetailerGuideSheetDestination?
    @State private var pendingFeedbackSessionID: UUID?
    @State private var pendingFeedbackItemID: UUID?
    @State private var expectsReturnFeedback = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if appModel.shoppingItems.isEmpty {
                    EmptyStateView(
                        symbol: "cart",
                        title: "Nothing to guide yet",
                        message: "Match products before starting the \(retailerName) guide."
                    )
                } else if !appModel.retailerSetupIsComplete {
                    retailerSetupView
                } else if appModel.retailerGuideIsComplete {
                    completionView
                } else if appModel.activeShoppingSessionIsImmutable {
                    immutableTripView
                } else if !appModel.retailerSessionIsInProgress {
                    sessionStartView
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
                    Button("Pause") {
                        if appModel.pauseRetailerShoppingSession() {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("retailer-session-pause")
                }
            }
        }
        .sheet(item: $sheetDestination, onDismiss: sheetDidDismiss) { destination in
            switch destination {
            case .product(_, _, let url), .retailer(let url):
                RetailerSafariSheet(
                    url: url,
                    configuration: appModel.retailerConfiguration
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .feedback(let sessionID, let itemID):
                RetailerReturnFeedbackSheet(
                    sessionID: sessionID,
                    itemID: itemID,
                    configuration: appModel.retailerConfiguration
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var retailerName: String {
        appModel.retailerConfiguration.displayName
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
            } label: {
                Label("I’m signed in and my list is ready", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("retailer-setup-complete")

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

    private var sessionStartView: some View {
        VStack(spacing: 20) {
            Image(systemName: appModel.guidedCompletedCount > 0 ? "location.fill.viewfinder" : "location.north.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(SmartCartTheme.green)

            VStack(spacing: 7) {
                Text(appModel.guidedCompletedCount > 0 ? "Resume shopping" : "Your shopping session is ready")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.center)
                Text("SmartCart will guide you through one product at a time and remember your place.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                summaryMetric("Products", value: appModel.shoppingItems.count, symbol: "basket.fill")
                summaryMetric("Remaining", value: appModel.retailerSessionRemainingCount, symbol: "arrow.right.circle.fill")
            }

            Button {
                appModel.startOrResumeRetailerShoppingSession()
            } label: {
                HStack {
                    Text(appModel.guidedCompletedCount > 0 ? "Continue shopping" : "Start shopping")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("retailer-session-start")

            Button("Redo \(retailerName) setup") {
                appModel.resetRetailerSetup()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(SmartCartTheme.green)
            .accessibilityIdentifier("retailer-setup-reset")

            Text("Each product opens on the retailer’s secure page. When you return, report what happened and SmartCart advances to the next item.")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .smartCartCard()
        .smartCartShadow()
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
                Text("These results are based on what you reported after each \(retailerName) page.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryMetric("Saved to list", value: appModel.savedForLaterCount, symbol: "bookmark.fill")
                summaryMetric("Added to cart", value: appModel.retailerAddedCount, symbol: "cart.fill")
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

            Button {
                appModel.startShoppingReconciliation()
            } label: {
                Label("I’m back — update pantry", systemImage: "cabinet.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                dismiss()
            } label: {
                Label("Finish later", systemImage: "clock.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .smartCartCard()
        .smartCartShadow()
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
        appModel.recordRetailerProductOpened(itemID: item.id)
        pendingFeedbackSessionID = sessionID
        pendingFeedbackItemID = item.id
        expectsReturnFeedback = true
        sheetDestination = .product(sessionID, item.id, appModel.productURL(for: item))
    }

    private func sheetDidDismiss() {
        guard expectsReturnFeedback,
              let sessionID = pendingFeedbackSessionID,
              let itemID = pendingFeedbackItemID else { return }
        expectsReturnFeedback = false
        pendingFeedbackSessionID = nil
        pendingFeedbackItemID = nil
        Task { @MainActor in
            await Task.yield()
            sheetDestination = .feedback(sessionID, itemID)
        }
    }

    private func recordOutcome(_ outcome: GuidedItemStatus) {
        guard let sessionID = appModel.activeShoppingSessionID,
              let item = appModel.currentGuidedItem else { return }
        appModel.recordRetailerOutcome(outcome, for: item.id, sessionID: sessionID)
    }

    private func outcomeLabel(_ status: GuidedItemStatus) -> String {
        switch status {
        case .waiting: "Awaiting answer"
        case .added, .savedToWishlist: "Reported added to \(appModel.retailerConfiguration.savedListName)"
        case .addedToCart: "Reported added at \(retailerName)"
        case .unavailable: "Reported unavailable"
        case .skipped: "Skipped"
        }
    }

    private func outcomeSymbol(_ status: GuidedItemStatus) -> String {
        switch status {
        case .waiting: "circle"
        case .added, .savedToWishlist: "bookmark.fill"
        case .addedToCart: "cart.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .skipped: "forward.fill"
        }
    }
}

private struct RetailerReturnFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    let sessionID: UUID
    let itemID: UUID
    let configuration: RetailerGuideConfiguration

    private var item: ShoppingListItem? {
        appModel.shoppingItems.first { $0.id == itemID }
    }

    private var retailerName: String {
        configuration.displayName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("What happened at \(retailerName)?")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(SmartCartTheme.navy)
                        Text(item.map { "\($0.product.brand) \($0.product.name)" } ?? "Retailer product")
                            .font(.subheadline)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }

                    feedbackButton(
                        "Added at \(retailerName)",
                        symbol: "cart.fill",
                        outcome: .addedToCart,
                        primary: true
                    )
                    feedbackButton(savedListOutcomeLabel, symbol: "bookmark.fill", outcome: .savedToWishlist)
                    feedbackButton("Product unavailable", symbol: "exclamationmark.triangle.fill", outcome: .unavailable)
                    feedbackButton("Skip this item", symbol: "forward.fill", outcome: .skipped)

                    InfoBanner(
                        symbol: "hand.raised.fill",
                        title: "Your answer only",
                        message: "SmartCart cannot read the \(retailerName) page or verify what happened. It records only the option you choose here.",
                        color: SmartCartTheme.amber
                    )
                }
                .padding(18)
            }
            .smartCartBackground()
            .navigationTitle("\(retailerName) return")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not yet") { dismiss() }
                }
            }
        }
    }

    private func feedbackButton(
        _ title: String,
        symbol: String,
        outcome: GuidedItemStatus,
        primary: Bool = false
    ) -> some View {
        Button {
            appModel.recordRetailerOutcome(outcome, for: itemID, sessionID: sessionID)
            dismiss()
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(primary ? AnyRetailerButtonStyle.primary : AnyRetailerButtonStyle.secondary)
        .accessibilityIdentifier("retailer-feedback-\(outcome.rawValue)")
    }

    private var savedListOutcomeLabel: String {
        switch configuration.retailer {
        case .walmart: "Added to Walmart Wishlist"
        case .target: "Added to Target Shopping List"
        case .kroger: "Added to Kroger Shopping List"
        }
    }
}

private enum AnyRetailerButtonStyle: ButtonStyle {
    case primary
    case secondary

    private var isPrimary: Bool { self == .primary }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(isPrimary ? SmartCartTheme.onAccent : SmartCartTheme.navy)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isPrimary ? SmartCartTheme.green : SmartCartTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(SmartCartTheme.border, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private enum RetailerGuideSheetDestination: Identifiable {
    case product(UUID, UUID, URL)
    case feedback(UUID, UUID)
    case retailer(URL)

    var id: String {
        switch self {
        case .product(let sessionID, let itemID, _): "product-\(sessionID.uuidString)-\(itemID.uuidString)"
        case .feedback(let sessionID, let itemID): "feedback-\(sessionID.uuidString)-\(itemID.uuidString)"
        case .retailer(let url): "retailer-\(url.absoluteString)"
        }
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

            RetailerSafariView(url: url)
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

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(SmartCartTheme.green)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
