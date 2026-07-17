import SwiftUI

struct ShoppingReconciliationView: View {
    @Environment(AppModel.self) private var appModel

    let sessionID: UUID

    @State private var outcome: ShoppingTripOutcome?
    @State private var purchasedItemIDs = Set<UUID>()
    @State private var substitutions: [UUID: ShoppingSubstitutionFeedback] = [:]
    @State private var replacementTarget: ReplacementTarget?
    @State private var errorMessage: String?

    private var session: ShoppingSession? {
        appModel.shoppingSession(id: sessionID)
    }

    private var purchasedItems: [ShoppingListItem] {
        session?.items.filter { purchasedItemIDs.contains($0.id) } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let committed = session?.reconciliation {
                    committedView(committed)
                } else if let session {
                    WorkflowHeader(
                        step: 1,
                        total: 1,
                        eyebrow: "After shopping",
                        title: "How did shopping go?",
                        message: "One answer sets a sensible default. You only need to tap the exceptions before SmartCart updates your pantry."
                    )

                    outcomeChoices

                    if let outcome {
                        selectionSummary(outcome, session: session)
                        substitutionSection

                        if let errorMessage {
                            InfoBanner(
                                symbol: "exclamationmark.triangle.fill",
                                title: "Pantry was not changed",
                                message: errorMessage,
                                color: SmartCartTheme.coral
                            )
                        }

                        Button {
                            commit(outcome)
                        } label: {
                            HStack {
                                Text(outcome == .didNotShop ? "Leave pantry unchanged" : "Update pantry")
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("shopping-reconciliation-commit")
                    }
                } else {
                    EmptyStateView(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Shopping session unavailable",
                        message: "Return to the current shopping guide and try again."
                    )
                }
            }
            .padding(18)
            .padding(.bottom, 34)
        }
        .smartCartBackground()
        .navigationTitle("Update pantry")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $replacementTarget) { target in
            SubstitutionPickerSheet(item: target.item) { feedback in
                substitutions[target.item.id] = feedback
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear(perform: restoreDraftDefaults)
    }

    private var outcomeChoices: some View {
        VStack(spacing: 10) {
            ForEach(ShoppingTripOutcome.allCases) { candidate in
                Button {
                    choose(candidate)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: candidate.symbol)
                            .font(.headline.bold())
                            .foregroundStyle(outcome == candidate ? SmartCartTheme.onAccent : SmartCartTheme.green)
                            .frame(width: 42, height: 42)
                            .background(outcome == candidate ? SmartCartTheme.green : SmartCartTheme.herbLight)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(SmartCartTheme.navy)
                            Text(candidate.guidance)
                                .font(.caption)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: outcome == candidate ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(outcome == candidate ? SmartCartTheme.green : SmartCartTheme.borderStrong)
                    }
                    .smartCartCard(padding: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(outcome == candidate ? SmartCartTheme.green : Color.clear, lineWidth: 2)
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("shopping-outcome-\(candidate.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func selectionSummary(
        _ outcome: ShoppingTripOutcome,
        session: ShoppingSession
    ) -> some View {
        switch outcome {
        case .boughtEverything:
            VStack(alignment: .leading, spacing: 12) {
                InfoBanner(
                    symbol: "checkmark.circle.fill",
                    title: "\(purchasedItemIDs.count) available items selected",
                    message: "SmartCart will add this trip to your pantry in one step. Record any substitutions below first.",
                    color: SmartCartTheme.green
                )
                let excludedItems = session.items.filter {
                    $0.status == .unavailable || $0.status == .skipped
                }
                if !excludedItems.isEmpty {
                    itemSelection(
                        items: excludedItems,
                        title: "Bought an excluded item elsewhere?",
                        subtitle: "Unavailable and skipped items start off. Select one if you still bought or substituted it."
                    )
                }
            }

        case .boughtMost:
            itemSelection(
                items: session.items,
                title: "Tap anything you didn’t buy",
                subtitle: "Everything starts selected"
            )

        case .boughtFew:
            itemSelection(
                items: session.items,
                title: "Tap what you bought",
                subtitle: "Everything starts unselected"
            )

        case .didNotShop:
            InfoBanner(
                symbol: "hand.raised.fill",
                title: "No pantry update",
                message: "Your saved shopping progress stays available, but pantry quantities and product preferences will not change.",
                color: SmartCartTheme.amber
            )
        }
    }

    private func itemSelection(
        items: [ShoppingListItem],
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: title, subtitle: subtitle)
            LazyVStack(spacing: 8) {
                ForEach(items) { item in
                    let selected = purchasedItemIDs.contains(item.id)
                    Button {
                        if selected {
                            purchasedItemIDs.remove(item.id)
                            substitutions.removeValue(forKey: item.id)
                        } else {
                            purchasedItemIDs.insert(item.id)
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? SmartCartTheme.green : SmartCartTheme.borderStrong)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.ingredient.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SmartCartTheme.navy)
                                Text("\(item.product.brand) \(item.product.name) · qty \(item.purchaseQuantity)")
                                    .font(.caption)
                                    .foregroundStyle(SmartCartTheme.secondaryInk)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(SmartCartTheme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(SmartCartTheme.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("\(item.ingredient.name), \(selected ? "purchased" : "not purchased")")
                }
            }
        }
    }

    @ViewBuilder
    private var substitutionSection: some View {
        if outcome != .didNotShop, !purchasedItemIDs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Any substitutions?",
                    subtitle: "Optional · scan the replacement or search SmartCart’s matched alternatives"
                )

                Menu {
                    ForEach(purchasedItems) { item in
                        Button(item.ingredient.name) {
                            replacementTarget = ReplacementTarget(item: item)
                        }
                    }
                } label: {
                    Label("Record a substituted product", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("record-substitution")

                ForEach(substitutions.values.sorted { $0.replacementName < $1.replacementName }) { feedback in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feedback.replacementName)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SmartCartTheme.navy)
                                Text("Replacement for \(originalIngredientName(feedback.originalItemID))")
                                    .font(.caption)
                                    .foregroundStyle(SmartCartTheme.secondaryInk)
                            }
                            Spacer()
                            Button {
                                substitutions.removeValue(forKey: feedback.originalItemID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(SmartCartTheme.secondaryInk)
                            }
                            .accessibilityLabel("Remove substitution")
                        }

                        Toggle(
                            "Prefer this product next time",
                            isOn: Binding(
                                get: { substitutions[feedback.originalItemID]?.preferNextTime ?? false },
                                set: { substitutions[feedback.originalItemID]?.preferNextTime = $0 }
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .tint(SmartCartTheme.green)
                    }
                    .smartCartCard(padding: 12)
                }
            }
        }
    }

    private func committedView(_ record: ShoppingReconciliationRecord) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58))
                .foregroundStyle(SmartCartTheme.green)
            Text(record.outcome == .didNotShop ? "Pantry left unchanged" : "Pantry updated")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(SmartCartTheme.navy)
                .multilineTextAlignment(.center)
            Text(
                record.outcome == .didNotShop
                    ? "SmartCart kept your shopping progress without changing stock."
                    : "Added \(record.pantryItemIDs.count) pantry item\(record.pantryItemIDs.count == 1 ? "" : "s") from \(record.purchasedItemIDs.count) purchased product\(record.purchasedItemIDs.count == 1 ? "" : "s")."
            )
            .font(.subheadline)
            .foregroundStyle(SmartCartTheme.secondaryInk)
            .multilineTextAlignment(.center)

            Button {
                appModel.resetFlow()
            } label: {
                Label("Done", systemImage: "house.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .smartCartCard()
        .smartCartShadow()
    }

    private func choose(_ candidate: ShoppingTripOutcome) {
        outcome = candidate
        purchasedItemIDs = appModel.defaultPurchasedItemIDs(for: candidate, sessionID: sessionID)
        substitutions = Dictionary(
            uniqueKeysWithValues: substitutions
                .filter { purchasedItemIDs.contains($0.key) }
                .map { ($0.key, $0.value) }
        )
        errorMessage = nil
    }

    private func commit(_ outcome: ShoppingTripOutcome) {
        do {
            try appModel.commitShoppingReconciliation(
                sessionID: sessionID,
                outcome: outcome,
                purchasedItemIDs: purchasedItemIDs,
                substitutions: Array(substitutions.values)
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreDraftDefaults() {
        guard outcome == nil,
              let committed = session?.reconciliation
        else { return }
        outcome = committed.outcome
        purchasedItemIDs = committed.purchasedItemIDs
        substitutions = Dictionary(uniqueKeysWithValues: committed.substitutions.map { ($0.originalItemID, $0) })
    }

    private func originalIngredientName(_ itemID: UUID) -> String {
        session?.items.first(where: { $0.id == itemID })?.ingredient.name ?? "shopping item"
    }
}

private struct ReplacementTarget: Identifiable {
    var item: ShoppingListItem
    var id: UUID { item.id }
}

private struct SubstitutionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingListItem
    let onSelect: (ShoppingSubstitutionFeedback) -> Void

    @State private var query = ""
    @State private var preferNextTime = false
    @State private var showScanner = false

    private var candidates: [RetailerProductRecord] {
        item.alternatives.filter { product in
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return "\(product.brand) \(product.name) \(product.package)"
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What replaced \(item.ingredient.name)?")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(SmartCartTheme.navy)
                        Text("Nothing changes until you confirm the shopping-trip update.")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }

                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan replacement barcode", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    VStack(alignment: .leading, spacing: 9) {
                        Text("SEARCH MATCHED PRODUCTS")
                            .smartEyebrow(SmartCartTheme.mutedInk)
                        TextField("Brand or product name", text: $query)
                            .textInputAutocapitalization(.words)
                            .smartField()
                        Text("Search covers the retailer alternatives already matched for this ingredient; it is not a live Walmart catalog search.")
                            .font(.caption2)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }

                    Toggle("Prefer the replacement next time", isOn: $preferNextTime)
                        .font(.subheadline.weight(.semibold))
                        .tint(SmartCartTheme.green)
                        .smartCartCard(padding: 12)

                    if candidates.isEmpty {
                        ContentUnavailableView(
                            "No saved alternative found",
                            systemImage: "magnifyingglass",
                            description: Text("Try scanning the replacement barcode instead.")
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(candidates) { candidate in
                                Button {
                                    select(candidate)
                                } label: {
                                    HStack(spacing: 12) {
                                        ProductIcon(product: candidate, size: 52)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(candidate.brand)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                            Text(candidate.name)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(SmartCartTheme.navy)
                                                .multilineTextAlignment(.leading)
                                            Text(candidate.package)
                                                .font(.caption)
                                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(SmartCartTheme.green)
                                    }
                                    .smartCartCard(padding: 12)
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                        }
                    }
                }
                .padding(18)
            }
            .smartCartBackground()
            .navigationTitle("Substituted product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerSheet(
                title: "Scan substituted product",
                onSubmission: { name, amount, submission in
                    onSelect(
                        ShoppingSubstitutionFeedback(
                            originalItemID: item.id,
                            replacementName: name,
                            replacementBrand: submission.brand,
                            replacementRetailerProductID: submission.externalProductID,
                            replacementGTIN14: submission.barcode.canonicalGTIN14,
                            replacementAmount: amount,
                            preferNextTime: preferNextTime
                        )
                    )
                    showScanner = false
                    Task { @MainActor in
                        await Task.yield()
                        dismiss()
                    }
                }
            )
            .presentationDetents([.large])
        }
    }

    private func select(_ product: RetailerProductRecord) {
        onSelect(
            ShoppingSubstitutionFeedback(
                originalItemID: item.id,
                replacementName: product.name,
                replacementBrand: product.brand,
                replacementRetailerProductID: product.retailerProductID,
                replacementGTIN14: product.gtin,
                packageQuantity: product.packageQuantity,
                packageUnit: product.packageUnit,
                preferNextTime: preferNextTime
            )
        )
        dismiss()
    }
}
