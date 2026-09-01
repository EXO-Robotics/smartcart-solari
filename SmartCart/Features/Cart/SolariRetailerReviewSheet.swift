import SwiftUI

struct SolariRetailerReviewSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let context: SolariReviewContext

    @State private var phase: Phase = .loading
    @State private var retryID = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    trustBoundary
                    phaseContent
                }
                .padding(18)
                .padding(.bottom, 118)
            }
            .scrollIndicators(.hidden)
            .smartCartWorkflowBackground()
            .navigationTitle("Solari Basket Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { dismiss() }
                        .accessibilityHint("Returns to Recipe Review without opening Walmart")
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .task(id: retryID) {
            await loadEvidence()
        }
    }

    private var trustBoundary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("RECORDED RETAILER EVIDENCE", systemImage: "checkmark.shield.fill")
                .smartEyebrow()

            Text("Walmart replay — not live")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.navy)

            Text("This internship experiment replays a timestamped Walmart research fixture. Live automated Walmart retrieval stays off unless retailer authorization is documented.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                "Solari never signs in, reads cookies, changes a cart, or checks out. You decide whether to continue to Walmart in Safari.",
                systemImage: "person.crop.circle.badge.checkmark"
            )
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
                ProgressView()
                    .tint(SmartCartTheme.green)
                Text("Validating recorded evidence…")
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                Text("SmartCart checks source references, timestamps, completeness, and basket math before showing a recommendation.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .smartCartCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Validating recorded Solari evidence")
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
                    Label("Review before continuing", systemImage: "exclamationmark.triangle.fill")
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
                Text("Recommended products")
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
        }
    }

    private func basketSummary(_ basket: SolariBasketSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                basket.completeness == .complete ? "Evidence-backed basket" : "Partial basket estimate",
                systemImage: basket.completeness == .complete ? "basket.fill" : "basket"
            )
            .font(.headline)
            .foregroundStyle(SmartCartTheme.navy)

            if let subtotal = basket.observedSubtotal {
                Text(currencyText(subtotal))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .accessibilityLabel("Observed subtotal \(currencyText(subtotal))")
            } else {
                Text("No observed subtotal")
                    .font(.title3.bold())
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            Text("Observed fixture prices only. Walmart confirms current price, availability, and final total.")
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .smartCartCard()
        .smartCartShadow()
        .accessibilityIdentifier("solari-basket-summary")
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    confidenceLabel(observation)
                    observedTimestamp(observation)
                }
                VStack(alignment: .leading, spacing: 6) {
                    confidenceLabel(observation)
                    observedTimestamp(observation)
                }
            }

            if let protein = decision.proteinGramsPerDollar {
                Text("Protein value: \(protein.formatted(.number.precision(.fractionLength(1)))) g per observed dollar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
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
                Label("View evidence source", systemImage: "safari")
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint("Opens the submitted Walmart product page in Safari")
        }
        .padding(16)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SmartCartTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("solari-recommendation-\(decision.requirementID.uuidString.lowercased())")
    }

    private func confidenceLabel(_ observation: SolariRetailerObservation) -> some View {
        Label("\(observation.confidence.label) confidence", systemImage: "checkmark.seal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(observation.confidence == .high ? SmartCartTheme.green : SmartCartTheme.coral)
    }

    private func observedTimestamp(_ observation: SolariRetailerObservation) -> some View {
        Label(
            "Observed \(observation.observedAt.formatted(date: .abbreviated, time: .shortened))",
            systemImage: "clock"
        )
        .font(.caption)
        .foregroundStyle(SmartCartTheme.secondaryInk)
    }

    private func unavailableContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Solari review unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.coral)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("You can retry the evidence replay or continue with SmartCart’s normal user-controlled Walmart Safari queue. No purchase or cart action has occurred.")
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
                    Button("Continue to Walmart") { continueToWalmart() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("solari-continue-walmart")
                        .accessibilityHint("Opens SmartCart’s user-controlled Walmart shopping queue")
                    Button("Edit shopping list") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("solari-edit-list")
                }
            case .failed:
                VStack(spacing: 10) {
                    Button("Retry Solari Review") {
                        phase = .loading
                        retryID += 1
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("solari-retry")

                    Button("Continue with Normal SmartCart") { continueToWalmart() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("solari-normal-fallback")
                        .accessibilityHint("Skips Solari and opens the existing Walmart Safari queue")
                }
            }
        }
    }

    @MainActor
    private func loadEvidence() async {
        guard let configuration = SolariBackendConfiguration(
            rawValue: context.backendURL.absoluteString,
            walmartFixtureReplayEnabled: true
        ) else {
            phase = .failed("The experimental Solari backend is not configured safely.")
            return
        }
        do {
            let result = try await SolariRetailerResearchClient().research(
                request: context.request,
                configuration: configuration
            )
            guard !Task.isCancelled else { return }
            phase = .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func continueToWalmart() {
        guard appModel.finalizeShoppingPlanForRetailerQueue() else {
            phase = .failed("SmartCart’s shopping plan changed. Return to Recipe Review and try again.")
            return
        }
        dismiss()
    }

    private func currencyText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.currency(code: "USD"))
    }
}

private extension SolariRetailerReviewSheet {
    enum Phase {
        case loading
        case loaded(SolariValidatedResearch)
        case failed(String)
    }
}
