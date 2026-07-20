import SwiftUI
import VisionKit

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    let embedded: Bool
    let title: String
    let amountLabel: String
    let onComplete: (() -> Void)?
    let onSubmission: ((String, Double, PantryBarcodeSubmission) -> Void)?

    @State private var manualCode = ""
    @State private var isResolving = false
    @State private var resolution: BarcodeResolutionResult?
    @State private var manualFallback: UnresolvedBarcode?
    @State private var stockName = ""
    @State private var stockBrand = ""
    @State private var stockAmount: Double = 1
    @State private var resolutionTask: Task<Void, Never>?

    init(
        embedded: Bool = false,
        title: String = "Scan pantry item",
        amountLabel: String = "Amount",
        onSubmission: ((String, Double, PantryBarcodeSubmission) -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.embedded = embedded
        self.title = title
        self.amountLabel = amountLabel
        self.onComplete = onComplete
        self.onSubmission = onSubmission
    }

    private var scannerAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }

    var body: some View {
        Group {
            if embedded {
                scannerContent
            } else {
                NavigationStack {
                    scannerContent
                        .navigationTitle(title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { finish() }
                            }
                        }
                }
            }
        }
        .onDisappear {
            resolutionTask?.cancel()
        }
    }

    private var scannerContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                if embedded {
                    SectionHeader(
                        title: "Scan pantry item",
                        subtitle: "Use the camera or enter a UPC, EAN, or GTIN"
                    )
                }
                scannerSurface
                codeEntry
                resolutionCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            if embedded {
                SmartCartTheme.scannerSurface
                    .ignoresSafeArea()
            } else {
                WoodGrainBackground()
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var scannerSurface: some View {
        if scannerAvailable {
            LiveBarcodeScanner { code, symbology in
                manualCode = code
                beginResolution(code: code, symbology: symbology, debounceCamera: true)
            }
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottom) {
                Text(manualCode.isEmpty ? "Center a UPC, EAN, or GTIN barcode" : "Captured \(manualCode)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(SmartCartTheme.canvas.opacity(0.86))
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(SmartCartTheme.border, lineWidth: 1) }
                    .padding(14)
            }
        } else {
            ContentUnavailableView(
                "Camera scanner unavailable",
                systemImage: "barcode.viewfinder",
                description: Text("The Simulator cannot scan a physical barcode. Enter a validated UPC, EAN, or GTIN below.")
            )
            .frame(height: 240)
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("UPC / EAN / GTIN")
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartCartTheme.secondaryInk)
            TextField(
                "Try 078742002163",
                text: Binding(
                    get: { manualCode },
                    set: { newValue in
                        manualCode = newValue
                        resetResolutionForManualCodeChange()
                    }
                )
            )
                .keyboardType(.numberPad)
                .textContentType(.none)
                .smartField()
                .accessibilityIdentifier("barcode-code")

            Button {
                beginResolution(code: manualCode, symbology: "manual-entry")
            } label: {
                if isResolving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Resolve product", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isResolving || manualCode.isEmpty)
            .accessibilityIdentifier("barcode-resolve")

            Text("SmartCart checks saved pantry names before its product catalog. If there is no match, name the product once.")
                .font(.caption2)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private var resolutionCard: some View {
        if isResolving {
            InfoBanner(
                symbol: "hourglass",
                title: "Looking up product…",
                message: "Checking your edited products, bundled fixtures, and configured catalog adapters.",
                color: SmartCartTheme.walmartBlue
            )
        } else if let resolution {
            switch resolution {
            case .resolved(let resolved):
                stockEntryCard(
                    heading: resolved.source == .localUserEditedCache
                        ? "Already in pantry — add another?"
                        : resolved.product.name,
                    headingSymbol: "checkmark.seal.fill",
                    headingColor: SmartCartTheme.green,
                    subheading: resolutionSubtitle(for: resolved),
                    knownPantryBarcode: resolved.source == .localUserEditedCache,
                    barcode: resolved.barcode,
                    raw: resolved.scan.rawBarcode,
                    submission: PantryBarcodeSubmission(
                        scan: resolved.scan,
                        barcode: resolved.barcode,
                        name: resolved.product.name,
                        brand: resolved.product.brand ?? "",
                        externalProductID: resolved.product.externalReference,
                        requiresUserNaming: false
                    )
                )

            case .notFound(let unresolved):
                manualNamingCard(
                    unresolved,
                    heading: "Product not found",
                    subheading: "Name this product once. SmartCart will use your saved name on future scans."
                )

            case .unavailable(let unresolved, let failure):
                VStack(alignment: .leading, spacing: 12) {
                    InfoBanner(
                        symbol: "wifi.exclamationmark",
                        title: "Product lookup unavailable",
                        message: unavailableMessage(failure),
                        color: SmartCartTheme.coral
                    )

                    HStack(spacing: 10) {
                        Button {
                            beginResolution(
                                code: unresolved.scan.rawBarcode,
                                symbology: unresolved.scan.rawSymbology
                            )
                        } label: {
                            Label("Retry Lookup", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("barcode-retry-lookup")

                        Button {
                            manualFallback = unresolved
                        } label: {
                            Text("Name Manually")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("barcode-name-manually")
                    }

                    if let manualFallback {
                        manualNamingCard(
                            manualFallback,
                            heading: "Name product manually",
                            subheading: "Your saved name will resolve this barcode locally next time, even while the catalog is unavailable."
                        )
                    }
                }

            case .invalid(let unresolved):
                InfoBanner(
                    symbol: "xmark.octagon.fill",
                    title: "Invalid barcode",
                    message: validationMessage(unresolved.reason),
                    color: SmartCartTheme.coral
                )
            }
        }
    }

    @ViewBuilder
    private func manualNamingCard(
        _ unresolved: UnresolvedBarcode,
        heading: String,
        subheading: String
    ) -> some View {
        if let barcode = unresolved.normalizedBarcode {
            stockEntryCard(
                heading: heading,
                headingSymbol: "questionmark.circle.fill",
                headingColor: SmartCartTheme.amber,
                subheading: subheading,
                barcode: barcode,
                raw: unresolved.scan.rawBarcode,
                submission: PantryBarcodeSubmission(
                    scan: unresolved.scan,
                    barcode: barcode,
                    name: "",
                    brand: "",
                    externalProductID: nil,
                    requiresUserNaming: true
                )
            )
        }
    }

    /// Shared name + amount entry shown after any successful scan. Typing a
    /// name queries saved pantry stock so the scan can top up an existing
    /// item instead of creating a duplicate.
    private func stockEntryCard(
        heading: String,
        headingSymbol: String,
        headingColor: Color,
        subheading: String?,
        knownPantryBarcode: Bool = false,
        barcode: NormalizedBarcode,
        raw: String,
        submission: PantryBarcodeSubmission
    ) -> some View {
        let trimmedName = stockName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergeTarget = onSubmission == nil
            ? appModel.pantryMergeTarget(named: trimmedName, submission: submission)
            : nil
        let suggestions = onSubmission == nil ? appModel.pantryNameSuggestions(for: stockName) : []
        let displayHeading = knownPantryBarcode ? heading : (mergeTarget?.name ?? heading)

        return VStack(alignment: .leading, spacing: 12) {
            Label(displayHeading, systemImage: headingSymbol)
                .font(.headline)
                .foregroundStyle(headingColor)
            if let mergeTarget {
                Text(
                    mergeTarget.name.caseInsensitiveCompare(heading) == .orderedSame
                        ? "Saved pantry barcode match"
                        : "Saved pantry barcode match · Catalog result: \(heading)"
                )
                .font(.caption)
                .foregroundStyle(SmartCartTheme.secondaryInk)
            } else if let subheading {
                Text(subheading)
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            if let mergeTarget {
                InfoBanner(
                    symbol: "rectangle.stack.badge.plus",
                    title: "Already in your pantry",
                    message: "\(mergeTarget.name) has \(mergeTarget.packageCount.formatted()) package(s) on hand. Adding \(stockAmount.formatted()) will stack it to \((mergeTarget.packageCount + stockAmount).formatted()), and this barcode stays linked to the same item.",
                    color: SmartCartTheme.green
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("PANTRY NAME")
                    .smartEyebrow(SmartCartTheme.mutedInk)
                TextField("What is this item?", text: $stockName)
                    .textInputAutocapitalization(.words)
                    .smartField()
                    .accessibilityIdentifier("barcode-product-name")

                if !suggestions.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            Text("Add to:")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                            ForEach(suggestions) { suggestion in
                                Button {
                                    stockName = suggestion.name
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(suggestion.name)
                                        Text(suggestion.packageCount.formatted())
                                            .foregroundStyle(SmartCartTheme.secondaryInk)
                                    }
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(SmartCartTheme.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(SmartCartTheme.herbLight)
                                    .clipShape(Capsule())
                                    .overlay { Capsule().stroke(SmartCartTheme.borderStrong, lineWidth: 1) }
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("BRAND · OPTIONAL")
                    .smartEyebrow(SmartCartTheme.mutedInk)
                TextField("Brand", text: $stockBrand)
                    .textInputAutocapitalization(.words)
                    .smartField()
                    .accessibilityIdentifier("barcode-product-brand")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(amountLabel.uppercased())
                    .smartEyebrow(SmartCartTheme.mutedInk)
                HStack(spacing: 10) {
                    amountButton("minus") { stockAmount = max(1, stockAmount - 1) }
                    TextField(
                        amountLabel,
                        value: $stockAmount,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
                    .smartField()
                    amountButton("plus") { stockAmount += 1 }
                    Spacer(minLength: 0)
                }
            }

            barcodeProvenance(barcode, raw: raw)

            Button {
                let editedSubmission = PantryBarcodeSubmission(
                    scan: submission.scan,
                    barcode: submission.barcode,
                    name: trimmedName,
                    brand: stockBrand.trimmingCharacters(in: .whitespacesAndNewlines),
                    externalProductID: submission.externalProductID,
                    requiresUserNaming: submission.requiresUserNaming
                )
                if let onSubmission {
                    onSubmission(trimmedName, stockAmount, editedSubmission)
                } else {
                    appModel.addPantryStock(name: trimmedName, amount: stockAmount, submission: editedSubmission)
                }
                finish()
            } label: {
                Label(
                    onSubmission == nil
                        ? (mergeTarget.map { "Add \(stockAmount.formatted()) to \($0.name)" } ?? "Add new pantry item")
                        : "Use as substituted product",
                    systemImage: onSubmission == nil
                        ? (mergeTarget == nil ? "plus.circle.fill" : "tray.and.arrow.down.fill")
                        : "arrow.triangle.2.circlepath"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmedName.isEmpty || stockAmount <= 0)
            .accessibilityIdentifier("barcode-add-to-pantry")
        }
        .smartCartCard(padding: 15)
    }

    private func amountButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 38, height: 38)
                .background(SmartCartTheme.herbLight)
                .clipShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .smartCartMinimumHitTarget()
        .accessibilityLabel(symbol == "plus" ? "Increase amount" : "Decrease amount")
        .accessibilityValue(stockAmount.formatted(.number.precision(.fractionLength(0...2))))
    }

    private func barcodeProvenance(_ barcode: NormalizedBarcode, raw: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Raw: \(raw)")
            Text("Format: \(barcode.format.rawValue) · GTIN-14: \(barcode.canonicalGTIN14)")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(SmartCartTheme.secondaryInk)
    }

    private func finish() {
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }

    @MainActor
    private func resetResolutionForManualCodeChange() {
        resolutionTask?.cancel()
        isResolving = false
        resolution = nil
        manualFallback = nil
    }

    @MainActor
    private func beginResolution(
        code: String,
        symbology: String?,
        debounceCamera: Bool = false
    ) {
        resolutionTask?.cancel()
        isResolving = true
        stockAmount = 1
        resolution = nil
        manualFallback = nil

        let scan = BarcodeScan(rawBarcode: code, rawSymbology: symbology)
        let resolver = BarcodeResolutionService(
            userEditedCache: PantryBarcodeUserEditedCache(items: appModel.pantryInventory),
            adapters: [SmartCartBackendBarcodeAdapter()]
        )
        resolutionTask = Task {
            if debounceCamera {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
            }
            let result = await resolver.resolve(scan)
            guard !Task.isCancelled else { return }

            resolution = result
            switch result {
            case .resolved(let resolved):
                stockName = appModel.pantryItem(matching: resolved.barcode)?.name
                    ?? resolved.product.name
                stockBrand = appModel.pantryItem(matching: resolved.barcode)?.brand
                    ?? resolved.product.brand
                    ?? ""
            case .notFound(let unresolved),
                 .unavailable(let unresolved, _),
                 .invalid(let unresolved):
                if let barcode = unresolved.normalizedBarcode,
                   let existing = appModel.pantryItem(matching: barcode) {
                    stockName = existing.name
                    stockBrand = existing.brand
                } else {
                    stockName = ""
                    stockBrand = ""
                }
            }
            isResolving = false
        }
    }

    private func validationMessage(_ reason: UnresolvedBarcodeReason) -> String {
        switch reason {
        case .invalid(let error): error.localizedDescription
        case .noMatch: "No verified product matched this barcode."
        }
    }

    private func unavailableMessage(_ failure: BarcodeLookupFailure) -> String {
        switch failure {
        case .configurationMissing:
            "Product lookup is not configured for this build. You can still name the product manually."
        case .offline:
            "Check your connection, retry, or name the product manually."
        case .timedOut:
            "The lookup took too long. Retry or name the product manually."
        case .rateLimited:
            "The catalog is receiving too many requests. Retry shortly or name the product manually."
        case .serverError, .malformedResponse:
            "The catalog could not complete this lookup. Retry or name the product manually."
        }
    }

    private func resolutionSubtitle(for resolved: ResolvedBarcodeProduct) -> String {
        let sourceText: String
        switch resolved.source {
        case .localUserEditedCache:
            sourceText = "This barcode uses your saved pantry name."
        case .bundledFixture:
            sourceText = "Bundled SmartCart demo result — confirm or edit before adding."
        case .adapter:
            let catalogName = resolved.product.catalogSource == "open_food_facts"
                ? "Open Food Facts"
                : "Catalog"
            sourceText = resolved.product.isVerified == true
                ? "\(catalogName) result — verified and editable."
                : "\(catalogName) result — unverified and editable."
        }
        if let packageDisplayText = resolved.product.packageDisplayText {
            return "\(sourceText) · Package: \(packageDisplayText)"
        }
        return sourceText
    }
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            // UPC-E requires an explicit expansion step before it can share the
            // canonical GTIN-14 path. Keep capture limited to formats the
            // normalizer can validate without guessing.
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String, String?) -> Void
        private var activeCodes: Set<String> = []

        init(onCode: @escaping (String, String?) -> Void) { self.onCode = onCode }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let code = barcode.payloadStringValue else { continue }
                guard activeCodes.insert(code).inserted else { continue }
                onCode(code, barcode.observation.symbology.rawValue)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didRemove removedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in removedItems {
                guard case .barcode(let barcode) = item,
                      let code = barcode.payloadStringValue else { continue }
                activeCodes.remove(code)
            }
        }
    }
}
