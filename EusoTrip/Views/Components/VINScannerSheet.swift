//
//  VINScannerSheet.swift
//  EusoTrip — VIN barcode / text scanner for fleet onboarding.
//
//  Wraps VisionKit's `DataScannerViewController` so the fleet-
//  registration step can scan a truck's VIN barcode (Code 39 on
//  the driver-side jamb / engine block) OR the printed VIN text
//  in one motion. The sheet then calls `fleetRegistration.decodeVin`
//  against NHTSA vPIC and presents the make/model/year for confirm.
//
//  Used by:
//    • Catalyst registration step 3 — Fleet bulk register
//    • Catalyst fleet management — Add vehicle
//    • Driver pre-trip — verify VIN matches the assigned vehicle
//

import SwiftUI
import VisionKit
import AVFoundation

/// What the sheet reports back when the user confirms a scan. The
/// host pushes this into its pending-vehicles list (or calls the
/// fleet-register endpoint directly).
public struct VINScanResult: Hashable, Identifiable {
    public let vin: String
    public let decoded: FleetRegistrationAPI.VinDecoded?
    public let suggestedVehicleType: String?
    public let gvwrClassNumber: Int?
    public var id: String { vin }
}

public struct VINScannerSheet: View {
    public let onConfirm: (VINScanResult) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var manualVIN: String = ""
    @State private var scannedVIN: String? = nil
    @State private var decoding: Bool = false
    @State private var decodeError: String? = nil
    @State private var preview: VINScanResult? = nil

    public init(onConfirm: @escaping (VINScanResult) -> Void) {
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if scannedVIN == nil && preview == nil {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerHostView { code in
                        let v = normalize(code)
                        guard isLikelyVIN(v) else { return }
                        scannedVIN = v
                        Task { await decode(v) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(scanOverlay)
                } else {
                    unsupportedFallback
                }
            } else if decoding {
                decodingState
            } else if let p = preview {
                confirmCard(p)
            }

            manualEntryBar
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .background(palette.bgPage)
        .alert(isPresented: Binding(get: { decodeError != nil }, set: { _ in decodeError = nil })) {
            Alert(
                title: Text("VIN decode failed"),
                message: Text(decodeError ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: — Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VIN SCAN").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Add a vehicle to your fleet")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var scanOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Aim at the VIN barcode or printed 17-character code")
                    .font(EType.caption).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.55))
        }
    }

    private var unsupportedFallback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "camera.slash")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("Camera scanning isn't available on this device.")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Type the 17-character VIN below to continue. NHTSA decodes it the same way.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var decodingState: some View {
        VStack(spacing: 10) {
            ProgressView().scaleEffect(1.1).tint(palette.textPrimary)
            Text("Decoding VIN via NHTSA…")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            if let v = scannedVIN {
                Text(v)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func confirmCard(_ r: VINScanResult) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.success)
                Text("VIN DECODED").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(Brand.success)
            }
            Text(r.vin)
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                if let d = r.decoded {
                    if let y = d.year { kv("YEAR", "\(y)") }
                    if let m = d.make { kv("MAKE", m) }
                    if let m = d.model { kv("MODEL", m) }
                    if let g = d.gvwrClass { kv("GVWR", g) }
                    if let f = d.fuelType { kv("FUEL", f) }
                    if let p = d.plant { kv("PLANT", p + (d.plantCountry.map { " · " + $0 } ?? "")) }
                }
                if let t = r.suggestedVehicleType {
                    kv("CLASSIFIED AS", humanizeType(t))
                }
            }
            HStack(spacing: 8) {
                Button {
                    scannedVIN = nil
                    preview = nil
                    manualVIN = ""
                } label: {
                    Text("Rescan")
                        .font(.system(size: 13, weight: .heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(palette.textPrimary)
                        .background(palette.bgCardSoft)
                        .overlay(Capsule().strokeBorder(palette.borderSoft))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onConfirm(r)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Add to fleet")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 100, alignment: .leading)
            Text(v).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var manualEntryBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OR ENTER VIN MANUALLY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                TextField("17-character VIN", text: $manualVIN)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .font(.system(size: 14, design: .monospaced))
                Button {
                    let v = normalize(manualVIN)
                    guard isLikelyVIN(v) else { decodeError = "VIN must be 17 characters"; return }
                    scannedVIN = v
                    Task { await decode(v) }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(isLikelyVIN(normalize(manualVIN)) ? LinearGradient.diagonal : LinearGradient(colors: [palette.textTertiary, palette.textTertiary], startPoint: .top, endPoint: .bottom))
                }
                .buttonStyle(.plain)
                .disabled(!isLikelyVIN(normalize(manualVIN)))
            }
        }
    }

    // MARK: — Behavior

    private func normalize(_ s: String) -> String {
        s.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func isLikelyVIN(_ s: String) -> Bool {
        // NHTSA VINs are 17 chars and exclude I, O, Q. Permissive check
        // — the server (and NHTSA) is the source of truth for full
        // validation including the check-digit at position 9.
        s.count == 17 && !s.contains("I") && !s.contains("O") && !s.contains("Q")
    }

    private func humanizeType(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    @MainActor
    private func decode(_ vin: String) async {
        decoding = true
        defer { decoding = false }
        decodeError = nil
        do {
            let resp = try await EusoTripAPI.shared.fleetRegistration.decodeVin(vin)
            if resp.ok, let d = resp.decoded {
                preview = VINScanResult(
                    vin: d.vin,
                    decoded: d,
                    suggestedVehicleType: resp.suggestedVehicleType,
                    gvwrClassNumber: resp.gvwrClassNumber
                )
            } else if resp.ok == false {
                // NHTSA didn't know the VIN — let the user add it as
                // a manual row anyway (trailers, yard trucks, etc.).
                preview = VINScanResult(
                    vin: vin, decoded: nil,
                    suggestedVehicleType: "tractor",
                    gvwrClassNumber: nil
                )
                decodeError = resp.reason
            }
        } catch {
            decodeError = "NHTSA didn't respond. You can still add this vehicle manually."
            preview = VINScanResult(
                vin: vin, decoded: nil,
                suggestedVehicleType: "tractor",
                gvwrClassNumber: nil
            )
        }
    }
}

// MARK: - DataScannerViewController wrapper

private struct DataScannerHostView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            return UIViewController()
        }
        // Recognize both VIN barcodes (Code 39 on the jamb) AND the
        // printed 17-char text. iOS 16+ DataScanner supports
        // simultaneous text + barcode recognition.
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.code39, .code128, .qr]),
                .text(textContentType: nil),
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        DispatchQueue.main.async {
            try? scanner.startScanning()
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coord { Coord(onCode: onCode) }

    final class Coord: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var fired = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item, scanner: dataScanner)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // Pick the first viable candidate — text takes precedence
            // since VIN text is more reliable than the barcode on
            // weathered jambs.
            for item in addedItems {
                if handle(item, scanner: dataScanner) { return }
            }
        }

        @discardableResult
        private func handle(_ item: RecognizedItem, scanner: DataScannerViewController) -> Bool {
            guard !fired else { return false }
            switch item {
            case .text(let t):
                let candidate = t.transcript.uppercased().filter { $0.isLetter || $0.isNumber }
                if candidate.count == 17 {
                    fired = true
                    try? scanner.stopScanning()
                    onCode(candidate)
                    return true
                }
            case .barcode(let b):
                if let payload = b.payloadStringValue {
                    let candidate = payload.uppercased().filter { $0.isLetter || $0.isNumber }
                    if candidate.count == 17 {
                        fired = true
                        try? scanner.stopScanning()
                        onCode(candidate)
                        return true
                    }
                }
            @unknown default: break
            }
            return false
        }
    }
}

// MARK: - Previews

#Preview("VIN Scanner · Dark") {
    VINScannerSheet { _ in }
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("VIN Scanner · Light") {
    VINScannerSheet { _ in }
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
