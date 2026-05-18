//
//  CredentialScanCard.swift
//  EusoTrip — registration / onboarding credential OCR card.
//
//  Drop-in card that lets the user scan or pick a photo of any
//  supported credential (CDL, COI, medical card, USDOT, USCG MMC,
//  FRA cert, SCT permit, etc.) and feeds the structured result
//  back to the host form. Powered server-side by Gemini Vision
//  through `credentialScanner.scan`.
//
//  Two capture paths:
//    • VisionKit `VNDocumentCameraViewController` — best for docs;
//      auto-cropped, multi-page, perspective-corrected.
//    • PhotosUI `PhotosPicker`             — fallback when the user
//      already has the photo / screenshot in their library.
//
//  Used by:
//    • 002 CreateAccount (per-role registration forms)
//    • Driver Me·Docs upload sheet (post-signup)
//    • Catalyst fleet onboarding step
//    • Compliance officer renewal upload
//

import SwiftUI
import PhotosUI
import VisionKit

/// Convenience accessor for one scanned field's display string.
extension CredentialScannerAPI.ScannedField {
    var displayString: String { value?.stringValue ?? "—" }
    var asStringArray: [String]? { value?.arrayValue }
    /// Confidence below 0.85 is highlighted as "needs review" so the
    /// host form can prompt the user to double-check.
    var needsReview: Bool { confidence < 0.85 }
}

struct CredentialScanCard: View {
    /// Server credential-type code (e.g. "us_cdl", "us_medical_card",
    /// "uscg_mmc"). Matches `credentialScannerRouter.CredentialTypes`.
    let credentialType: String

    /// Human-facing label for the card header (e.g. "Scan your CDL").
    let title: String

    /// Sub-line under the title explaining the value to the user.
    let subtitle: String

    /// Callback fired with the normalized envelope when the scan
    /// completes (even on AI failure — the host should check
    /// `overallConfidence` and `warnings`).
    let onResult: (CredentialScannerAPI.ScannedCredential) -> Void

    @Environment(\.palette) private var palette

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showCameraSheet: Bool = false
    @State private var inflight: Bool = false
    @State private var error: String? = nil
    @State private var lastResult: CredentialScannerAPI.ScannedCredential? = nil

    init(
        credentialType: String,
        title: String,
        subtitle: String,
        onResult: @escaping (CredentialScannerAPI.ScannedCredential) -> Void
    ) {
        self.credentialType = credentialType
        self.title = title
        self.subtitle = subtitle
        self.onResult = onResult
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            ctaRow
            if let err = error {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let r = lastResult { resultSummary(r) }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await scanFromLibrary(item: item) }
        }
        .sheet(isPresented: $showCameraSheet) {
            DocumentCameraSheet { data in
                showCameraSheet = false
                guard let data else { return }
                Task { await scanFromData(data) }
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 8) {
            // Camera capture — preferred for documents because
            // VNDocumentCameraViewController auto-crops + perspective-
            // corrects, producing cleaner OCR input.
            Button {
                guard !inflight else { return }
                showCameraSheet = true
            } label: {
                actionLabel(systemImage: "camera.fill", title: "Scan", filled: true)
            }
            .buttonStyle(.plain)
            .disabled(inflight)

            // Library fallback for users who already photographed the
            // document.
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                actionLabel(systemImage: "photo.on.rectangle", title: "Library", filled: false)
            }
            .buttonStyle(.plain)
            .disabled(inflight)

            if inflight {
                ProgressView().scaleEffect(0.6).tint(palette.textPrimary)
            }
        }
    }

    private func actionLabel(systemImage: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .heavy))
            Text(title)
                .font(.system(size: 13, weight: .heavy))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .foregroundStyle(filled ? .white : palette.textPrimary)
        .background(filled ? AnyView(LinearGradient.diagonal) : AnyView(palette.bgCardSoft))
        .overlay(filled ? AnyView(EmptyView()) : AnyView(
            Capsule().strokeBorder(palette.borderSoft)
        ))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func resultSummary(_ r: CredentialScannerAPI.ScannedCredential) -> some View {
        let conf = Int((r.overallConfidence * 100).rounded())
        let confColor: Color = r.overallConfidence >= 0.85 ? Brand.success
                            : r.overallConfidence >= 0.6 ? Brand.warning : Brand.danger
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(confColor)
                Text("CAPTURED · \(conf)% CONFIDENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(confColor)
            }
            ForEach(r.warnings, id: \.self) { w in
                Text("⚠ " + w)
                    .font(EType.caption).foregroundStyle(Brand.warning)
            }
        }
        .padding(.top, 4)
    }

    // MARK: — Capture pipelines

    @MainActor
    private func scanFromLibrary(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            error = "Couldn't read photo"
            pickerItem = nil
            return
        }
        pickerItem = nil
        await scanFromData(data)
    }

    @MainActor
    private func scanFromData(_ data: Data) async {
        guard !inflight else { return }
        inflight = true
        defer { inflight = false }
        error = nil

        // Compress JPEG so the Gemini payload stays under ~1MB.
        var jpeg = data
        if let img = UIImage(data: data) {
            var quality: CGFloat = 0.85
            while quality > 0.3 {
                if let d = img.jpegData(compressionQuality: quality), d.count <= 900_000 {
                    jpeg = d
                    break
                }
                quality -= 0.1
            }
        }
        let base64 = jpeg.base64EncodedString()

        do {
            let result = try await EusoTripAPI.shared.credentialScanner.scan(
                credentialType: credentialType,
                documentBase64: base64,
                mimeType: .jpeg
            )
            lastResult = result
            onResult(result)
        } catch let e {
            error = "Scan failed: \((e as? EusoTripAPIError)?.errorDescription ?? e.localizedDescription)"
        }
    }
}

// MARK: - VNDocumentCameraViewController wrapper
//
// SwiftUI-friendly wrapper around VisionKit's document camera. The
// camera auto-detects edges, crops the document, perspective-corrects
// it, and lets the user retake / add additional pages. We only need
// page 0 for credential scanning so we return the first page's
// JPEG-encoded data.

private struct DocumentCameraSheet: UIViewControllerRepresentable {
    let onResult: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coord { Coord(onResult: onResult) }

    final class Coord: NSObject, VNDocumentCameraViewControllerDelegate {
        let onResult: (Data?) -> Void
        init(onResult: @escaping (Data?) -> Void) { self.onResult = onResult }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { onResult(nil); return }
            let image = scan.imageOfPage(at: 0)
            let data = image.jpegData(compressionQuality: 0.9)
            onResult(data)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onResult(nil)
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onResult(nil)
        }
    }
}

// MARK: - Previews

#Preview("CredentialScanCard · Dark") {
    VStack(spacing: 16) {
        CredentialScanCard(
            credentialType: "us_cdl",
            title: "Scan your CDL",
            subtitle: "We'll auto-fill number, state, class, endorsements and expiration."
        ) { _ in }

        CredentialScanCard(
            credentialType: "us_coi",
            title: "Scan your ACORD 25 COI",
            subtitle: "Pulls policy #, insurer, liability limits, MCS-90 status and expiration."
        ) { _ in }
    }
    .padding(16)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
    .background(Theme.dark.bgPage)
}

#Preview("CredentialScanCard · Light") {
    CredentialScanCard(
        credentialType: "uscg_mmc",
        title: "Scan your USCG MMC",
        subtitle: "Auto-fills mariner reference number, endorsements, GT capacity."
    ) { _ in }
        .padding(16)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
