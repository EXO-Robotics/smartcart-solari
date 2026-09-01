import SwiftUI

struct SolariRetailerReviewSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SolariResearchStore.self) private var researchStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let context: SolariReviewContext

    @State private var phase: Phase = .loading
    @State private var loadSequence = 0
    @State private var refreshNextLoad = false
    @State private var isProvenanceExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    trustBoundary
                    phaseContent
                }
                .padding(18)
                .padding(.bottom, 126)
            }
            .scrollIndicators(.hidden)
            .smartCartWorkflowBackground()
            .navigationTitle("Solari Basket Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { dismiss() }
                        .accessibilityHint("Returns to Recipe Review without opening a retailer")
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .task(id: loadSequence) {
            let refresh = refreshNextLoad
            refreshNextLoad = false
            await loadEvidence(refresh: refresh)
        }
    }

    private var trustBoundary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                isRecordedFixture ? "DEBUG RECORDED REPLAY · NOT LIVE" : "OWNED DEMO RETAILER RESEARCH",
                systemImage: isRecordedFixture ? "record.circle" : "checkmark.shield.fill"
            )
                .smartEyebrow()

            Text(isRecordedFixture ? "Recorded catalog evidence — not live" : "Observed options — not a checkout quote")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.navy)

            Text(
                isRecordedFixture
                    ? "This DEBUG build replays historical synthetic Demo Grocer evidence so the native review can be exercised without device signing. Solari Browser and Sandbox do not run in replay mode."
                    : "Solari Browser reads only SmartCart’s owned synthetic Demo Grocer pages. Solari Sandbox normalizes package math and proposes the smallest sufficient basket."
            )
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Label(isRecordedFixture
                ? "Apple App Attest is not used for this local recorded replay. Release-SolariBeta has no replay bypass."
                : "Apple App Attest gates each request. No retailer login, cookies, account, cart, or checkout data is sent or stored.",
                systemImage: "lock.shield")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SmartCartTheme.green)
            .fixedSize(horizontal: false, vertical: true)
        }
        .smartCartCard()
        .smartCartShadow()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("solari-trust-boundary")
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .loading:
            VStack(spacing: 14) {
                ProgressView().tint(SmartCartTheme.green)
                Text(isRecordedFixture ? "Loading recorded evidence…" : "Researching current options…")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                Text("SmartCart verifies submitted product identities, source URLs, timestamps, provenance, completeness, and basket math before showing a result.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .smartCartCard()
            .accessibilityElement(children: .combine)
                    .accessibilityLabel(isRecordedFixture ? "Loading recorded Demo Grocer evidence, not live" : "Researching and validating current Demo Grocer options")
            .accessibilityIdentifier("solari-loading")
        case .loaded(let research):
            loadedContent(research)
        case .failed(let message):
            unavailableContent(message: message)
        }
    }

    private func loadedContent(_ research: SolariValidatedResearch) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            basketSummary(research.result.basket)
            if !research.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Limitations to review", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.coral)
                    ForEach(research.warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.subheadline)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .smartCartCard()
                .accessibilityIdentifier("solari-partial-warning")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Recommended packages")
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

            provenanceDisclosure(research.result)
        }
    }

    private func basketSummary(_ basket: SolariBasketSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                basket.completeness == .complete ? "Evidence-backed comparison" : "Partial comparison",
                systemImage: basket.completeness == .complete ? "basket.fill" : "basket"
            )
            .font(.headline)
            .foregroundStyle(SmartCartTheme.navy)

            if let subtotal = basket.observedSubtotal {
                Text(currencyText(subtotal))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .accessibilityLabel("Observed subtotal \(currencyText(subtotal))")
                if context.plan.servingCount > 0 {
                    Text("\(currencyText(subtotal / Decimal(context.plan.servingCount))) per serving")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .accessibilityIdentifier("solari-cost-per-serving")
                }
            } else {
                Text("No observed subtotal")
                    .font(.title3.bold())
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            Text(isRecordedFixture
                ? "Historical recorded synthetic prices only — not live or guaranteed. Availability, tax, fees, fulfillment, and your final retailer total remain unknown."
                : "Timestamped visible prices from the synthetic test catalog only. Availability, tax, fees, fulfillment, and your final retailer total remain unknown.")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .smartCartCard()
        .smartCartShadow()
        .accessibilityIdentifier("solari-basket-summary")
    }

    private func provenanceDisclosure(_ result: SolariResearchResult) -> some View {
        DisclosureGroup(isExpanded: $isProvenanceExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if result.executionMode == .recordedFixture {
                    Label("Solari Browser · not run for recorded replay", systemImage: "safari")
                    Label("Solari Sandbox · not run for recorded replay", systemImage: "shippingbox")
                    Label("Apple App Attest · not used for DEBUG recorded replay", systemImage: "iphone.slash")
                    Label("SmartCart deterministic fixture math · \(result.optimizer.algorithmVersion)", systemImage: "function")
                } else {
                    Label("Solari Browser · owned Demo Grocer pages", systemImage: "safari")
                    Label("Solari Sandbox · \(result.optimizer.algorithmVersion)", systemImage: "shippingbox")
                    Label("Apple App Attest · verifies this app and binds the exact request body", systemImage: "iphone.and.arrow.forward")
                    Label("Browser and Sandbox resources closed before response", systemImage: "lock")
                }
            }
            .padding(.top, 10)
        } label: {
            Label("How was this estimated?", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(SmartCartTheme.navy)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SmartCartTheme.secondaryInk)
        .smartCartCard()
        .accessibilityIdentifier("solari-provenance")
    }

    private func recommendationRow(
        decision: SolariBasketDecision,
        observation: SolariRetailerObservation
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Text(
                    "Needs \(quantityText(requirement.requiredQuantity)) \(requirement.unit.rawValue) · " +
                    "covers \(quantityText(decision.coveredQuantity)) \(unitText(decision.quantityUnit))"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(SmartCartTheme.secondaryInk)

                if decision.surplusQuantity > 0.000_1 {
                    Text(
                        "Estimated overage: \(quantityText(decision.surplusQuantity)) " +
                        "\(unitText(decision.quantityUnit))"
                    )
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { confidenceLabel(observation); observedTimestamp(observation) }
                VStack(alignment: .leading, spacing: 6) { confidenceLabel(observation); observedTimestamp(observation) }
            }

            ForEach(observation.ambiguityReasons, id: \.self) { ambiguity in
                Label(ambiguity, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let substitution = decision.substitutionNote,
               !substitution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(substitution, systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Link(destination: observation.sourceURL) {
                Label("View timestamped source", systemImage: "safari")
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint("Opens the owned synthetic Demo Grocer product page")
        }
        .padding(16)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SmartCartTheme.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("solari-recommendation-\(decision.requirementID.uuidString.lowercased())")
    }

    private func confidenceLabel(_ observation: SolariRetailerObservation) -> some View {
        Label("\(observation.confidence.label) confidence", systemImage: "checkmark.seal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(observation.confidence == .high ? SmartCartTheme.green : SmartCartTheme.coral)
    }

    private func observedTimestamp(_ observation: SolariRetailerObservation) -> some View {
        Label("Observed \(observation.observedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(SmartCartTheme.secondaryInk)
    }

    private func unavailableContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Solari research unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.coral)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Retry, edit the plan, or continue with SmartCart’s normal user-controlled retailer queue. No account, cart, purchase, or checkout action has occurred.")
                .font(.caption)
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
            case .loaded:
                VStack(spacing: 10) {
                    Button("Continue to \(appModel.retailerConfiguration.displayName)") { continueWithSmartCart() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("solari-continue-retailer")
                        .accessibilityHint("Opens SmartCart’s existing user-controlled retailer shopping queue")
                    Button("Refresh current options") { retry(refresh: true) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("solari-refresh")
                    Button("Edit shopping list") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("solari-edit-list")
                }
            case .failed:
                VStack(spacing: 10) {
                    Button("Retry Solari Research") { retry(refresh: true) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("solari-retry")
                    Button("Continue with Normal SmartCart") { continueWithSmartCart() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("solari-normal-fallback")
                }
            }
        }
    }

    private func retry(refresh: Bool) {
        phase = .loading
        refreshNextLoad = refresh
        loadSequence += 1
    }

    @MainActor
    private func loadEvidence(refresh: Bool) async {
        do {
            let result = try await researchStore.research(plan: context.plan, refresh: refresh)
            guard !Task.isCancelled else { return }
            phase = .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func continueWithSmartCart() {
        let servings = appModel.isMealPrepShopping ? 0 : appModel.desiredServings
        guard SolariResearchRequestBuilder.matchesCurrentPlan(
            context.plan,
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

    private func currencyText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.currency(code: "USD"))
    }

    private func quantityText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func unitText(_ unit: SolariEvidenceUnit) -> String {
        switch unit {
        case .ounce: "oz"
        case .pound: "lb"
        case .count: "count"
        }
    }

    private var isRecordedFixture: Bool {
        context.plan.request.executionMode == .recordedFixture
    }
}

private extension SolariRetailerReviewSheet {
    enum Phase {
        case loading
        case loaded(SolariValidatedResearch)
        case failed(String)
    }
}
