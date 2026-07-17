import SafariServices
import SwiftUI

struct WalmartWishlistSetupCard: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: appModel.walmartWishlistReference == nil ? "shield.lefthalf.filled" : "checkmark.seal.fill")
                    .font(.headline.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(appModel.walmartWishlistReference == nil ? SmartCartTheme.walmartBlue : SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.walmartWishlistReference == nil ? "Set up Walmart shopping" : "Walmart Wishlist ready")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    if let reference = appModel.walmartWishlistReference {
                        Text(reference.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SmartCartTheme.green)
                        Text("SmartCart can reopen this shared link, but it cannot view or change the list.")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    } else {
                        Text("Sign in securely at Walmart, create a wishlist, then optionally save its shared link here.")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                appModel.presentedSheet = .walmartSetup
            } label: {
                Label(
                    appModel.walmartWishlistReference == nil ? "Set up Walmart Wishlist" : "Edit Walmart setup",
                    systemImage: "arrow.up.right.square"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("walmart-setup-card-button")
        }
        .smartCartCard()
    }
}

struct WalmartSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    @State private var displayName = "SmartCart Groceries"
    @State private var sharedURLText = ""
    @State private var validationMessage: String?
    @State private var safariDestination: WalmartSafariDestination?
    @State private var hasLoaded = false
    @State private var confirmRemoval = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    securityHeader
                    setupSteps
                    wishlistReferenceForm
                    capabilityDisclosure
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .smartCartBackground()
            .navigationTitle("Walmart setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadOnce)
        .sheet(item: $safariDestination) { destination in
            WalmartSafariSheet(url: destination.url)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Remove saved Wishlist?", isPresented: $confirmRemoval) {
            Button("Remove", role: .destructive) {
                appModel.removeWalmartWishlistReference()
                displayName = "SmartCart Groceries"
                sharedURLText = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes only SmartCart’s saved shared link. It does not change anything in Walmart.")
        }
    }

    private var securityHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 52, height: 52)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in directly with Walmart")
                        .font(.title3.bold())
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("SmartCart never asks for or stores your Walmart password.")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }

            Button {
                safariDestination = WalmartSafariDestination(url: appModel.walmartListsURL())
            } label: {
                HStack {
                    Text("Open Walmart Lists")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(BlueButtonStyle())
            .accessibilityIdentifier("walmart-setup-open-lists")
        }
        .smartCartCard()
        .smartCartShadow()
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "First-time setup", subtitle: "Walmart owns sign-in and list creation")
            setupStep(1, "Open Walmart and sign in or create an account.")
            setupStep(2, "Choose My Items → Lists → Create a wishlist.")
            setupStep(3, "Name it SmartCart or SmartCart Groceries.")
            setupStep(4, "Choose Share → Copy URL, then return here.")
        }
        .smartCartCard()
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.onAccent)
                .frame(width: 25, height: 25)
                .background(SmartCartTheme.green)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.navy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var wishlistReferenceForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "Remember my Wishlist",
                subtitle: "Optional · stores only the name and shared walmart.com URL on this device"
            )

            TextField("Wishlist name", text: $displayName)
                .textContentType(.name)
                .smartField()
                .accessibilityIdentifier("walmart-wishlist-name")

            TextField("https://www.walmart.com/lists/shared/WL/…", text: $sharedURLText, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .smartField()
                .accessibilityIdentifier("walmart-wishlist-url")

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.coral)
            }

            Button(action: saveReference) {
                Label("Save Wishlist reference", systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("walmart-setup-save")

            if appModel.walmartWishlistReference != nil {
                Button(role: .destructive) {
                    confirmRemoval = true
                } label: {
                    Label("Remove saved reference", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .smartCartCard()
    }

    private var capabilityDisclosure: some View {
        InfoBanner(
            symbol: "hand.raised.fill",
            title: "Guided, not connected",
            message: "SmartCart cannot read Walmart cookies, verify sign-in, choose a wishlist, press Add to Wishlist, or inspect list contents. You stay in control of every Walmart action.",
            color: SmartCartTheme.amber
        )
    }

    private func loadOnce() {
        guard !hasLoaded else { return }
        hasLoaded = true
        appModel.recordWalmartSetupStarted()
        if let reference = appModel.walmartWishlistReference {
            displayName = reference.displayName
            sharedURLText = reference.sharedURL.absoluteString
        }
    }

    private func saveReference() {
        do {
            try appModel.saveWalmartWishlistReference(
                displayName: displayName,
                rawURL: sharedURLText
            )
            validationMessage = nil
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct WalmartWishlistGuideView: View {
    @Environment(AppModel.self) private var appModel

    @State private var sheetDestination: WalmartGuideSheetDestination?
    @State private var pendingFeedbackItemID: UUID?
    @State private var expectsReturnFeedback = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if appModel.shoppingItems.isEmpty {
                    EmptyStateView(
                        symbol: "cart",
                        title: "Nothing to guide yet",
                        message: "Match products before starting guided Walmart shopping."
                    )
                } else if appModel.walmartGuideIsComplete {
                    completionView
                } else if let item = appModel.currentGuidedItem {
                    guideHeader
                    wishlistTarget
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
        .navigationTitle("Shop at Walmart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appModel.presentedSheet = .walmartSetup
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Walmart setup")
            }
        }
        .sheet(item: $sheetDestination, onDismiss: sheetDidDismiss) { destination in
            switch destination {
            case .product(_, let url), .wishlist(let url):
                WalmartSafariSheet(url: url)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .feedback(let itemID):
                WalmartReturnFeedbackSheet(itemID: itemID)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var guideHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Item \(appModel.guidedIndex + 1) of \(appModel.shoppingItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                Spacer()
                Text("\(appModel.guidedCompletedCount) answered")
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

    private var wishlistTarget: some View {
        Group {
            if let reference = appModel.walmartWishlistReference {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(SmartCartTheme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SAVE TARGET")
                            .smartEyebrow(SmartCartTheme.mutedInk)
                        Text(reference.displayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(SmartCartTheme.navy)
                    }
                    Spacer()
                    Button("Edit") { appModel.presentedSheet = .walmartSetup }
                        .font(.caption.bold())
                }
                .smartCartCard(padding: 13)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    InfoBanner(
                        symbol: "list.bullet.clipboard",
                        title: "Wishlist reference is optional",
                        message: "You can still save products at Walmart. Add the shared URL if you want a reliable final Open Wishlist button.",
                        color: SmartCartTheme.amber
                    )
                    Button("Set up Walmart Wishlist") {
                        appModel.presentedSheet = .walmartSetup
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
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
                Text("SELECTED WALMART PRODUCT")
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
                    Text(item.product.isExactProductLink ? "Open at Walmart" : "Search at Walmart")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(BlueButtonStyle())
            .accessibilityIdentifier("walmart-product-open")

            Text(
                item.product.isExactProductLink
                    ? "This opens the selected item. Walmart controls sign-in, local availability, price, quantity, and the Add to Wishlist action."
                    : "No eligible exact record was available, so this opens a clearly labeled Walmart search."
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
            SectionHeader(title: "At Walmart", subtitle: "You perform the required account action")
            instructionRow("1", "Tap Add to Wishlist on the product page.")
            instructionRow("2", "Choose your SmartCart wishlist and save.")
            instructionRow("3", "Return here and tell SmartCart what happened.")
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
                replacementMenu
                Button {
                    recordOutcome(.skipped)
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 9) {
                replacementMenu
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
                ForEach(item.alternatives) { candidate in
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
        .disabled(appModel.currentGuidedItem?.alternatives.isEmpty != false)
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
                Text("These results are based on what you reported after each Walmart page.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryMetric("Saved", value: appModel.walmartWishlistSavedCount, symbol: "bookmark.fill")
                summaryMetric("In cart", value: appModel.walmartCartAddedCount, symbol: "cart.fill")
                summaryMetric("Unavailable", value: appModel.walmartUnavailableCount, symbol: "exclamationmark.triangle.fill")
                summaryMetric("Skipped", value: appModel.walmartSkippedCount, symbol: "forward.fill")
            }

            if appModel.walmartWishlistReference != nil {
                Button {
                    guard appModel.ensureCurrentShoppingSession() != nil else { return }
                    guard let url = appModel.openSavedWalmartWishlist() else { return }
                    sheetDestination = .wishlist(url)
                } label: {
                    HStack {
                        Text("Finish shopping at Walmart")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(BlueButtonStyle())
                .accessibilityIdentifier("walmart-open-saved-wishlist")
            } else {
                Button("Set up final Walmart link") {
                    appModel.presentedSheet = .walmartSetup
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            InfoBanner(
                symbol: "info.circle.fill",
                title: "Finish at Walmart",
                message: "Wishlist quantities, local pickup eligibility, substitutions, final prices, cart, payment, and checkout remain in Walmart.",
                color: SmartCartTheme.walmartBlue
            )

            Button {
                appModel.startShoppingReconciliation()
            } label: {
                Label("I’m back — update pantry", systemImage: "cabinet.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                appModel.resetFlow()
            } label: {
                Label("Do this later", systemImage: "clock.fill")
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
    }

    private func openProduct(_ item: ShoppingListItem) {
        appModel.recordWalmartProductOpened(itemID: item.id)
        pendingFeedbackItemID = item.id
        expectsReturnFeedback = true
        sheetDestination = .product(item.id, appModel.productURL(for: item))
    }

    private func sheetDidDismiss() {
        guard expectsReturnFeedback, let itemID = pendingFeedbackItemID else { return }
        expectsReturnFeedback = false
        pendingFeedbackItemID = nil
        Task { @MainActor in
            await Task.yield()
            sheetDestination = .feedback(itemID)
        }
    }

    private func recordOutcome(_ outcome: GuidedItemStatus) {
        guard let item = appModel.currentGuidedItem else { return }
        appModel.recordWalmartOutcome(outcome, for: item.id)
    }

    private func outcomeLabel(_ status: GuidedItemStatus) -> String {
        switch status {
        case .waiting: "Awaiting answer"
        case .added, .savedToWishlist: "Reported saved to Wishlist"
        case .addedToCart: "Reported added to cart"
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

private struct WalmartReturnFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    let itemID: UUID

    private var item: ShoppingListItem? {
        appModel.shoppingItems.first { $0.id == itemID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Did you save this item?")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(SmartCartTheme.navy)
                        Text(item.map { "\($0.product.brand) \($0.product.name)" } ?? "Walmart product")
                            .font(.subheadline)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }

                    feedbackButton(
                        "Saved to Wishlist",
                        symbol: "bookmark.fill",
                        outcome: .savedToWishlist,
                        primary: true
                    )
                    feedbackButton("Added directly to cart", symbol: "cart.fill", outcome: .addedToCart)
                    feedbackButton("Product unavailable", symbol: "exclamationmark.triangle.fill", outcome: .unavailable)
                    feedbackButton("Skip this item", symbol: "forward.fill", outcome: .skipped)

                    InfoBanner(
                        symbol: "hand.raised.fill",
                        title: "Your answer only",
                        message: "SmartCart cannot read the Walmart page or verify what happened. It records only the option you choose here.",
                        color: SmartCartTheme.amber
                    )
                }
                .padding(18)
            }
            .smartCartBackground()
            .navigationTitle("Walmart return")
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
            appModel.recordWalmartOutcome(outcome, for: itemID)
            dismiss()
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(primary ? AnyWalmartButtonStyle.primary : AnyWalmartButtonStyle.secondary)
        .accessibilityIdentifier("walmart-feedback-\(outcome.rawValue)")
    }
}

private enum AnyWalmartButtonStyle: ButtonStyle {
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

private enum WalmartGuideSheetDestination: Identifiable {
    case product(UUID, URL)
    case feedback(UUID)
    case wishlist(URL)

    var id: String {
        switch self {
        case .product(let itemID, _): "product-\(itemID.uuidString)"
        case .feedback(let itemID): "feedback-\(itemID.uuidString)"
        case .wishlist(let url): "wishlist-\(url.absoluteString)"
        }
    }
}

private struct WalmartSafariDestination: Identifiable {
    let id = UUID()
    let url: URL
}

struct WalmartSafariSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(SmartCartTheme.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Secure Walmart page")
                        .font(.subheadline.bold())
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Sign-in and shopping stay with Walmart")
                        .font(.caption2)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                Button("Return to SmartCart") {
                    dismiss()
                }
                .font(.caption.bold())
                .foregroundStyle(SmartCartTheme.green)
                .accessibilityIdentifier("walmart-safari-return")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .padding(.top, 46)
            .background(SmartCartTheme.paper)

            Divider()

            WalmartSafariView(url: url)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(SmartCartTheme.paper.ignoresSafeArea())
    }
}

struct WalmartSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(SmartCartTheme.green)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
