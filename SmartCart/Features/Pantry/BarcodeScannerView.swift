import SwiftUI
import VisionKit

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void

    @State private var manualCode = ""
    @State private var capturedCode: String?

    private var scannerAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if scannerAvailable {
                    LiveBarcodeScanner { code in
                        capturedCode = code
                        manualCode = code
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .bottom) {
                        Text(capturedCode == nil ? "Center a UPC or EAN barcode" : "Captured \(capturedCode!)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(SmartCartTheme.navy.opacity(0.86))
                            .clipShape(Capsule())
                            .padding(14)
                    }
                } else {
                    ContentUnavailableView(
                        "Camera scanner unavailable",
                        systemImage: "barcode.viewfinder",
                        description: Text("The Simulator cannot scan a physical barcode. Enter a UPC below to test the offline pantry flow.")
                    )
                    .frame(maxHeight: .infinity)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("UPC / EAN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                    TextField("Try 078742002166", text: $manualCode)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                        .smartField()
                    Text("Offline test codes: 078742002166 pasta · 078742131910 olive oil · 041000303314 parmesan")
                        .font(.caption2)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }

                Button {
                    onCode(manualCode)
                    dismiss()
                } label: {
                    Label("Add to pantry", systemImage: "cabinet.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(manualCode.filter(\.isNumber).isEmpty)
            }
            .padding(18)
            .background(SmartCartTheme.canvas)
            .navigationTitle("Scan pantry item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

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
        let onCode: (String) -> Void
        private var lastCode: String?

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

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
                onCode(code)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}
