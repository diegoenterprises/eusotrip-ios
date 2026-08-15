//
//  306_BolCounterSign.swift
//  EusoTrip — Shipper · BOL counter-sign with PencilKit (Arc H).
//

import SwiftUI

struct BolCounterSignScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { CounterSignBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct CounterSignBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var strokes: [[CGPoint]] = [[]]
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var actionError: String? = nil
    @State private var bolReview: SignableBOL?
    @State private var pendingReviewedChecksum: String?
    @State private var reviewedChecksum: String?
    @State private var bolPresentation: EusoPDFPresentation?

    private struct SignableBOL: Decodable {
        let loadId: Int
        let bolNumber: String
        let documentId: Int
        let documentName: String
        let downloadUrl: String
        let mimeType: String
        let sizeBytes: Int
        let checksumSha256: String
        let signerCapacity: String
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { successCard }
                if let err = actionError { errorCard(err) }
                reviewCard
                if bolReview != nil {
                    signaturePad
                    consentCopy
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await loadBOLForSigning() }
        .fullScreenCover(item: $bolPresentation, onDismiss: {
            if let pendingReviewedChecksum {
                reviewedChecksum = pendingReviewedChecksum
                self.pendingReviewedChecksum = nil
            }
        }) { presentation in
            EusoPDFViewer(
                title: presentation.title,
                subtitle: presentation.subtitle,
                source: .url(presentation.url),
                allowSigning: false,
                loadIdForWalletPass: presentation.loadIdForWalletPass
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "signature").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · \(TransportLexicon.generic(key: "billOfLading").uppercased()) COUNTER-SIGN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("Sign the \(TransportLexicon.generic(key: "billOfLading"))").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            Text("Sign with finger or Apple Pencil. EusoTrip records the signature image, load ID, and timestamp.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // Shared bespoke gradient-ink surface — was PencilKit (solid .label ink);
    // BOL counter-signatures now render the EusoTrip brand gradient like every
    // other signing surface.
    private var signaturePad: some View {
        EusoGradientInkCanvas(strokes: $strokes)
            .frame(height: 200)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var reviewCard: some View {
        LifecycleCard(accentGradient: true) {
            if let source = bolReview {
                Button { presentBOL(source) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: reviewedChecksum == source.checksumSha256 ? "checkmark.shield.fill" : "doc.text.magnifyingglass")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reviewedChecksum == source.checksumSha256 ? "BOL reviewed" : "Review exact BOL")
                                .font(EType.body.weight(.semibold))
                            Text("\(source.bolNumber) · SHA-256 \(source.checksumSha256.prefix(12))…")
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(reviewedChecksum == source.checksumSha256 ? AnyShapeStyle(Color.green) : AnyShapeStyle(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
            } else if sending {
                HStack(spacing: 8) {
                    ProgressView().tint(LinearGradient.diagonal)
                    Text("Verifying the BOL source…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                Text("A verified BOL is required before counter-signing.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var consentCopy: some View {
        Text("I consent to use this electronic signature on the identified Bill of Lading and confirm that I reviewed the bound source document.")
            .font(.caption2)
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var successCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal)
                Text("Signature recorded.").font(EType.body).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
        }
    }

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button { strokes = [[]] } label: {
                Text("Clear").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { Task { await submit() } } label: {
                HStack(spacing: 6) {
                    if sending { ProgressView().tint(.white) }
                    Text(sending ? "Submitting…" : "Submit signature")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(
                sending ||
                reviewedChecksum != bolReview?.checksumSha256 ||
                !EusoGradientInkCanvas.hasInk(strokes)
            )
        }
    }

    private func submit() async {
        guard let source = bolReview,
              reviewedChecksum == source.checksumSha256,
              EusoGradientInkCanvas.hasInk(strokes) else {
            actionError = "Review this BOL version and add your signature before committing."
            return
        }
        sending = true; actionError = nil
        // Gradient-ink signature via the shared renderer (was PencilKit solid
        // .label ink) — brand gradient now matches every other signing surface.
        let b64 = EusoGradientInkCanvas.renderPNGBase64(strokes, size: CGSize(width: 600, height: 200))
        guard !b64.isEmpty else {
            actionError = "The signature image could not be prepared. Clear it and sign again."
            sending = false
            return
        }
        struct In: Encodable {
            let loadId: Int
            let bolNumber: String
            let signatureBase64: String
            let consentAccepted: Bool
        }
        struct Out: Decodable {
            let success: Bool
            let signatureId: String?
            let signatureHash: String?
        }
        guard let n = Int(loadId.replacingOccurrences(of: "load_", with: "")), n > 0 else {
            actionError = "The load identifier is invalid. Reopen the load and try again."
            sending = false
            return
        }
        do {
            let response: Out = try await EusoTripAPI.shared.mutation(
                "documents.signBol",
                input: In(
                    loadId: n,
                    bolNumber: source.bolNumber,
                    signatureBase64: b64,
                    consentAccepted: true
                )
            )
            sent = response.success
            if response.success { strokes = [[]] }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }

    private func loadBOLForSigning() async {
        struct In: Encodable { let loadId: String; let bolNumber: String? }
        sending = true
        defer { sending = false }
        do {
            let source: SignableBOL = try await EusoTripAPI.shared.query(
                "loads.getBOLForSigning",
                input: In(loadId: loadId, bolNumber: nil)
            )
            if bolReview?.checksumSha256 != source.checksumSha256 {
                reviewedChecksum = nil
                strokes = [[]]
            }
            bolReview = source
        } catch {
            bolReview = nil
            reviewedChecksum = nil
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func presentBOL(_ source: SignableBOL) {
        guard let base = EusoTripAPI.shared.baseURL,
              let url = URL(string: source.downloadUrl, relativeTo: base)?.absoluteURL else {
            actionError = "The verified BOL URL is unavailable."
            return
        }
        pendingReviewedChecksum = source.checksumSha256
        bolPresentation = EusoPDFPresentation(
            url: url,
            title: source.documentName,
            subtitle: "BOL \(source.bolNumber) · SHA-256 \(source.checksumSha256.prefix(12))…",
            loadIdForWalletPass: loadId
        )
    }
}

#Preview("306 · BOL sign · Night") {
    BolCounterSignScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("306 · BOL sign · Afternoon") {
    BolCounterSignScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
