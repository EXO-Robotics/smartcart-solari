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
    @State private var capturedSymbology: String?
    @State private var isResolving = false
    @State private var resolution: BarcodeResolutionResult?
    @State private var stockName = ""
    @State private var stockAmount: Double = 1
    @State private var resolutionTask: Task<Void, Never>?

    private let resolver = BarcodeResolutionService()

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
                capturedSymbology = symbology
                beginResolution(code: code, symbology: symbology)
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
            TextField("Try 078742002163", text: $manualCode)
                .keyboardType(.numberPad)
                .textContentType(.none)
                .smartField()
                .onChange(of: manualCode) { _, _ in resolution = nil }

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

            Text("Offline fixtures: 078742002163 pasta · 078742131917 olive oil · 041000303319 parmesan")
                .font(.caption2)
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private var resolutionCard: some View {
        if isResolving {
            InfoBanner(
                symbol: "hourglass",
                title: "Resolving product",
                message: "Checking your edited products, bundled fixtures, and configured catalog adapters.",
                color: SmartCartTheme.walmartBlue
            )
        } else if let resolution {
            switch resolution {
            case .resolved(let resolved):
                stockEntryCard(
                    heading: resolved.product.name,
                    headingSymbol: "checkmark.seal.fill",
                    headingColor: SmartCartTheme.green,
                    subheading: (resolved.product.brand?.isEmpty == false) ? resolved.product.brand : nil,
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

            case .unresolved(let unresolved):
                if let barcode = unresolved.normalizedBarcode {
                    stockEntryCard(
                        heading: "Name this product",
                        headingSymbol: "questionmark.circle.fill",
                        headingColor: SmartCartTheme.amber,
                        subheading: "No verified product matched this barcode. SmartCart will not invent a name.",
                        barcode: barcode,
                        raw: unresolved.scan.rawBarcode,
                        submission: PantryBarcodeSubmission(
                            scan: unresolved.scan,
                            barcode: barcode,
                            name: "",
                            brand: "",
                            externalProductID: nil,
                            requiresUserNaming: false
                        )
                    )
                } else {
                    InfoBanner(
                        symbol: "xmark.octagon.fill",
                        title: "Invalid barcode",
                        message: validationMessage(unresolved.reason),
                        color: SmartCartTheme.coral
                    )
                }
            }
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
        barcode: NormalizedBarcode,
        raw: String,
        submission: PantryBarcodeSubmission
    ) -> some View {
        let trimmedName = stockName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergeTarget = onSubmission == nil
            ? appModel.pantryMergeTarget(named: trimmedName, submission: submission)
            : nil
        let suggestions = onSubmission == nil ? appModel.pantryNameSuggestions(for: stockName) : []
        let displayHeading = mergeTarget?.name ?? heading

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
                if let onSubmission {
                    onSubmission(trimmedName, stockAmount, submission)
                } else {
                    appModel.addPantryStock(name: trimmedName, amount: stockAmount, submission: submission)
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
    private func beginResolution(code: String, symbology: String?) {
        resolutionTask?.cancel()
        isResolving = true
        stockAmount = 1
        resolution = nil

        let scan = BarcodeScan(rawBarcode: code, rawSymbology: symbology)
        resolutionTask = Task {
            let result = await resolver.resolve(scan)
            guard !Task.isCancelled else { return }

            resolution = result
            switch result {
            case .resolved(let resolved):
                stockName = appModel.pantryItem(matching: resolved.barcode)?.name
                    ?? resolved.product.name
            case .unresolved(let unresolved):
                if let barcode = unresolved.normalizedBarcode,
                   let existing = appModel.pantryItem(matching: barcode) {
                    stockName = existing.name
                } else {
                    stockName = ""
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
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
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
        private var lastCode: String?

        init(onCode: @escaping (String, String?) -> Void) { self.onCode = onCode }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let code = barcode.payloadStringValue,
                      code != lastCode else { continue }
                lastCode = code
                onCode(code, barcode.observation.symbology.rawValue)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}
