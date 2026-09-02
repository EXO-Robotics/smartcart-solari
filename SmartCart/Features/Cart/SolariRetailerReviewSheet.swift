import SwiftUI

struct SolariBasketComparisonPresentation: Equatable {
    let headline: String
    let detail: String

    init(_ comparison: SolariBasketComparison) {
        let premium = NSDecimalNumber(decimal: comparison.premiumOverCheapest).doubleValue
        let selectedSubtotal = Self.currencyText(comparison.selectedSubtotal)
        let cheapestSubtotal = Self.currencyText(comparison.cheapestAdequateSubtotal)
        let premiumCap = Self.currencyText(comparison.maxPremiumOverCheapest)

        if premium <= 0.005 || comparison.relativeSurplusAvoided <= 0.0005 {
            headline = "Selected basket is the cheapest adequate option for this trip."
        } else {
            headline =
                "Selected a lower-overage basket for " +
                "\(Self.currencyText(comparison.premiumOverCheapest)) above the cheapest adequate option."
        }

        detail =
            "Selected: \(selectedSubtotal), package-overage score \(Self.scoreText(comparison.selectedAggregateRelativeSurplus)) · " +
            "Cheapest: \(cheapestSubtotal), package-overage score \(Self.scoreText(comparison.cheapestAggregateRelativeSurplus)) · " +
            "Score reduction: \(Self.scoreText(comparison.relativeSurplusAvoided)) · " +
            "Premium cap: \(premiumCap). Review line items for exact leftover quantities."
    }

    private static func currencyText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.currency(code: "USD"))
    }

    private static func scoreText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct SolariRetailerReviewSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SolariResearchStore.self) private var researchStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let context: SolariReviewContext

    @State private var activePlan: SolariResearchPlan
    @State private var phase: Phase = .loading
    @State private var loadSequence = 0
    @State private var refreshNextLoad = false
    @State private var isProvenanceExpanded = false
    @State private var presentedProductSource: SolariProductSourceDestination?

    init(context: SolariReviewContext) {
        self.context = context
        _activePlan = State(initialValue: context.plan)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    phaseContent
                }
                .padding(18)
                .padding(.bottom, 92)
            }
            .scrollIndicators(.hidden)
            .smartCartWorkflowBackground()
            .navigationTitle("Price Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                        .accessibilityHint("Returns to Recipe Review")
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .sheet(item: $presentedProductSource) { destination in
            RetailerSafariView(
                url: destination.url,
                onFinish: { presentedProductSource = nil }
            )
            .ignoresSafeArea()
            .presentationDetents([.large])
        }
        .task(id: loadSequence) {
            let refresh = refreshNextLoad
            refreshNextLoad = false
            await loadEvidence(refresh: refresh)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView().tint(SmartCartTheme.green)
                Text(isRecordedFixture ? "Loading recorded prices…" : "Checking prices…")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Finding package sizes and estimating your total.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .smartCartCard()
            .accessibilityElement(children: .combine)
                    .accessibilityLabel(isRecordedFixture ? "Loading recorded Demo Grocer evidence, not live" : "Researching and validating owned Demo Grocer options")
            .accessibilityIdentifier("solari-loading")
        case .loaded(let research):
            loadedContent(research)
        case .failed(let message):
            unavailableContent(message: message)
        }
    }

    private func loadedContent(_ research: SolariValidatedResearch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isRecordedFixture {
                Label("DEBUG RECORDED REPLAY · NOT LIVE", systemImage: "record.circle")
                    .smartEyebrow()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("solari-recorded-replay-label")
            }

            priceSummary(research.result.basket)

            VStack(alignment: .leading, spacing: 12) {
                Text("Prices found")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(SmartCartTheme.navy)

                ForEach(research.result.decisions) { decision in
                    if let observation = research.result.observations.first(where: {
                        $0.observationID == decision.observationID
                    }) {
                        recommendationRow(decision: decision, observation: observation)
                    }
                }
            }

            detailsDisclosure(research)
        }
    }

    private func priceSummary(_ basket: SolariBasketSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(basket.completeness == .complete ? "Estimated total" : "Prices found")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.secondaryInk)

            if let subtotal = basket.observedSubtotal {
                Text(currencyText(subtotal))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(SmartCartTheme.green)
                    .accessibilityLabel("Estimated subtotal \(currencyText(subtotal))")
                if context.plan.servingCount > 0, basket.completeness == .complete {
                    Text("\(currencyText(subtotal / Decimal(context.plan.servingCount))) per serving")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .accessibilityIdentifier("solari-cost-per-serving")
                }
            } else {
                Text("Price unavailable")
                    .font(.title3.bold())
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            Text(coverageText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .smartCartCard()
        .smartCartShadow()
        .accessibilityIdentifier("solari-price-summary")
    }

    private func detailsDisclosure(_ research: SolariValidatedResearch) -> some View {
        let result = research.result
        let comparison = SolariBasketComparisonPresentation(result.comparison)
        return DisclosureGroup(isExpanded: $isProvenanceExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(isRecordedFixture
                    ? "Recorded synthetic Demo Grocer prices. They are not live or guaranteed."
                    : "Timestamped visible prices from SmartCart’s owned Demo Grocer test catalog. They are not a checkout quote.")

                Label(coverageText, systemImage: "checklist")
                Label(comparison.headline, systemImage: "scale.3d")

                ForEach(research.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SmartCartTheme.coral)
                }

                if !activePlan.skippedLines.isEmpty {
                    Text("Not priced: \(activePlan.skippedLines.map(\.name).joined(separator: ", ")).")
                }

                Divider()

                if result.executionMode == .recordedFixture {
                    Label("Solari Browser · not run for recorded replay", systemImage: "safari")
                    Label("Solari Sandbox · not run for recorded replay", systemImage: "shippingbox")
                    Label("Apple App Attest · not used for DEBUG recorded replay", systemImage: "iphone.slash")
                    Label("SmartCart deterministic fixture math · \(result.optimizer.algorithmVersion)", systemImage: "function")
                } else {
                    Label("Solari Browser · owned Demo Grocer pages", systemImage: "safari")
                    Label("Solari Sandbox · optimality authority · \(result.optimizer.algorithmVersion)", systemImage: "shippingbox")
                    Label("SmartCart · verified evidence, coverage, arithmetic, and premium cap — not the global optimum", systemImage: "checkmark.shield")
                    Label("Apple App Attest · verifies this app and binds the exact request body", systemImage: "iphone.and.arrow.forward")
                    Label("Browser and Sandbox resources closed before response", systemImage: "lock")
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Details and sources", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.navy)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SmartCartTheme.secondaryInk)
        .smartCartCard()
        .accessibilityIdentifier("solari-details")
    }

    private var coverageText: String {
        let found = activePlan.request.requirements.count
        let skipped = activePlan.skippedLines.count
        if skipped == 0 {
            return "\(found) of \(activePlan.totalWaitingCount) prices found"
        }
        return "\(found) price\(found == 1 ? "" : "s") found · \(skipped) item\(skipped == 1 ? "" : "s") unchanged"
    }

    private func recommendationRow(
        decision: SolariBasketDecision,
        observation: SolariRetailerObservation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(observation.title ?? "Product title unavailable")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(decision.packageCount) × \(observation.packageDescription ?? "package details unavailable")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                if let lineTotal = decision.lineTotal {
                    Text(currencyText(lineTotal))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(SmartCartTheme.green)
                } else {
                    Text("Price unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.coral)
                }
            }

            if let requirement = context.plan.request.requirements.first(where: {
                $0.id == decision.requirementID
            }) {
                let required = "\(quantityText(requirement.requiredQuantity)) \(unitText(requirement.unit.evidenceUnit)) needed"
                let overage = decision.surplusQuantity > 0.000_1
                    ? " · \(quantityText(decision.surplusQuantity)) \(unitText(decision.quantityUnit)) extra"
                    : ""
                Text(required + overage)
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            HStack(spacing: 10) {
                observedTimestamp(observation)
                if observation.confidence != .high || !observation.ambiguityReasons.isEmpty {
                    Label("Check match", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.coral)
                }
            }

            Button {
                presentedProductSource = SolariProductSourceDestination(
                    url: observation.sourceURL
                )
            } label: {
                Label("View product", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("solari-view-product-\(decision.requirementID.uuidString.lowercased())")
            .accessibilityHint("Opens the product page inside SmartCart")
        }
        .padding(16)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SmartCartTheme.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("solari-recommendation-\(decision.requirementID.uuidString.lowercased())")
    }

    private func observedTimestamp(_ observation: SolariRetailerObservation) -> some View {
        Label("Observed \(observation.observedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(SmartCartTheme.secondaryInk)
    }

    private func unavailableContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn’t check prices", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.coral)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .smartCartCard()
        .smartCartShadow()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("solari-unavailable")
    }

    @ViewBuilder
    private var actionBar: some View {
        BottomActionBar {
            switch phase {
            case .loading:
                Button("Back to Recipe Review") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("solari-back")
            case .loaded(let research):
                VStack(spacing: 10) {
                    Button("Looks good — continue shopping") {
                        continueWithOriginalSmartCartList(research)
                    }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("solari-prices-look-good")
                        .accessibilityHint("Continues with SmartCart’s original retailer matches; no product is purchased or added to a retailer cart")
                    Button("Edit my list") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("solari-edit-list")
                }
            case .failed:
                VStack(spacing: 10) {
                    Button("Try again") { retry(refresh: false) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("solari-retry")
                    Button("Back to my list") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("solari-normal-fallback")
                }
            }
        }
    }

    private func retry(refresh: Bool) {
        if refresh {
            activePlan = SolariResearchRequestBuilder.refreshedPlan(from: activePlan)
        }
        phase = .loading
        refreshNextLoad = refresh
        loadSequence += 1
    }

    @MainActor
    private func loadEvidence(refresh: Bool) async {
        do {
            let result = try await researchStore.research(plan: activePlan, refresh: refresh)
            guard !Task.isCancelled else { return }
            phase = .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func continueWithNormalSmartCartAfterFailure() {
        let servings = appModel.isMealPrepShopping ? 0 : appModel.desiredServings
        guard SolariResearchRequestBuilder.matchesCurrentPlan(
            activePlan,
            items: appModel.shoppingItems,
            servingCount: servings
        ) else {
            phase = .failed("SmartCart’s reviewed shopping requirements changed. Return to Recipe Review and research the updated plan.")
            return
        }
        guard appModel.finalizeShoppingPlanForRetailerQueue() else {
            phase = .failed("SmartCart could not finalize the current shopping plan. Return to Recipe Review and try again.")
            return
        }
        dismiss()
    }

    private func continueWithOriginalSmartCartList(_ research: SolariValidatedResearch) {
        let servings = appModel.isMealPrepShopping ? 0 : appModel.desiredServings
        guard SolariOriginalSmartCartContinuation.permitsFinalization(
            plan: activePlan,
            research: research,
            items: appModel.shoppingItems,
            servingCount: servings
        ) else {
            phase = .failed(
                "SmartCart’s reviewed shopping requirements or original retailer matches changed. " +
                "Return to Recipe Review before continuing."
            )
            return
        }
        guard appModel.finalizeShoppingPlanForRetailerQueue() else {
            phase = .failed("SmartCart could not finalize the original shopping list. Return to Recipe Review and try again.")
            return
        }
        dismiss()
    }

    private func currencyText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.currency(code: "USD"))
    }

    private func quantityText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func unitText(_ unit: SolariEvidenceUnit) -> String {
        switch unit {
        case .gram: "g"
        case .milliliter: "ml"
        case .count: "count"
        }
    }

    private var isRecordedFixture: Bool {
        context.plan.request.executionMode == .recordedFixture
    }
}

private struct SolariProductSourceDestination: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}

private extension SolariRetailerReviewSheet {
    enum Phase {
        case loading
        case loaded(SolariValidatedResearch)
        case failed(String)
    }
}
