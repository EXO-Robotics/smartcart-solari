import SafariServices
import SwiftUI

struct ProductMatchingView: View {
    @Environment(AppModel.self) private var appModel

    private var stages: [(String, String)] {
        return [
            ("Reading saved shopping preferences", "slider.horizontal.3"),
            ("Searching \(appModel.retailerConfiguration.displayName)", "magnifyingglass"),
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
                    eyebrow: "Product matching",
                    title: appModel.matchProgress == 1 ? "Your products are ready" : "Finding the best matches",
                    message: "SmartCart applies \(appModel.preferences.summary), then resolves exact \(appModel.retailerConfiguration.displayName) products or clearly labeled searches."
                )

                matchingCard
                stageList

                if appModel.matchProgress == 1 {
                    resultsSummary
                    productPreview
                }

                InfoBanner(
                    symbol: "waveform.path.ecg",
                    title: "Seeded \(appModel.retailerConfiguration.displayName) records",
                    message: "Exact retailer item IDs and observed non-live prices are stored on-device. Availability is not live, and search fallbacks are never presented as exact products.",
                    color: SmartCartTheme.amber
                )
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .smartCartBackground()
        .navigationTitle("Match products")
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
                    Text("matched")
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
                Text("\(appModel.ingredientsToBuy.count) ingredients · \(appModel.primaryStore.name)")
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
            resultMetric("\(appModel.matchedItemCount)", "Exact links", "checkmark.seal.fill", SmartCartTheme.green)
            resultMetric("\(appModel.searchFallbackCount)", "Searches", "magnifyingglass.circle.fill", SmartCartTheme.amber)
            resultMetric(appModel.estimatedTotal.formatted(.currency(code: "USD")), "Observed", "cart.fill", SmartCartTheme.walmartBlue)
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
            return "Resume \(appModel.retailerConfiguration.displayName) guide"
        }
        return "Start \(appModel.retailerConfiguration.displayName) guide"
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
            title: "Browser handoff, not account linking",
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
                title: "Executable preferences",
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
