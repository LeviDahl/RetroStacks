#if os(iOS)
import SwiftUI
import SwiftData
import Vision
import VisionKit

/// Wraps VisionKit's `DataScannerViewController` — camera-only, real-device
/// hardware (the Simulator reports `.isSupported == false`, so this can be
/// build-verified but not actually exercised without a physical device).
/// Recognizes the barcode symbologies used on North American game/console
/// boxes (UPC-A shows up as EAN-13 with a leading zero once decoded, so
/// `.ean13`/`.upce` cover it; `.code128` for the odd third-party case/reissue).
private struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

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

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}

/// Full-screen scan sheet: point the camera at a barcode, look it up against
/// `CatalogItem.upc`, hand the match back to the presenter. Doesn't add
/// anything itself — the caller decides how (`AddToCollectionFlow` adds the
/// same simple way every other row in that sheet does, for consistency).
struct BarcodeScanScreen: View {
    var onFound: (CatalogItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var catalog: [CatalogItem]
    @State private var notFoundCode: String?

    private var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if isAvailable {
                    scannerContent
                } else {
                    ContentUnavailableView {
                        Label("Scanning Unavailable", systemImage: "camera.metering.unknown")
                    } description: {
                        Text(DataScannerViewController.isSupported
                             ? "Camera access is needed to scan barcodes — enable it in Settings."
                             : "Barcode scanning isn't supported on this device.")
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var scannerContent: some View {
        ZStack(alignment: .bottom) {
            BarcodeScannerView(onScan: handleScan)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                if let notFoundCode {
                    Text("No catalog match for \(notFoundCode)")
                } else {
                    Text("Point the camera at the barcode on the box or cartridge.")
                }
            }
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 40)
            .animation(.snappy, value: notFoundCode)
        }
    }

    private func handleScan(_ code: String) {
        guard let match = catalog.first(where: { $0.upc == code }) else {
            notFoundCode = code
            return
        }
        onFound(match)
        dismiss()
    }
}
#endif
