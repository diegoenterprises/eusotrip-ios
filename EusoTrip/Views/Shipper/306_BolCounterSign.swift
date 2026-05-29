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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { successCard }
                if let err = actionError { errorCard(err) }
                signaturePad
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "signature").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · BOL COUNTER-SIGN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Sign the BOL").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Sign with finger or Apple Pencil. Server records the signature image + load ID + timestamp.").font(EType.caption).foregroundStyle(palette.textSecondary)
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
            }.buttonStyle(.plain).disabled(sending || !EusoGradientInkCanvas.hasInk(strokes))
        }
    }

    private func submit() async {
        sending = true; actionError = nil
        // Gradient-ink signature via the shared renderer (was PencilKit solid
        // .label ink) — brand gradient now matches every other signing surface.
        let b64 = EusoGradientInkCanvas.renderPNGBase64(strokes, size: CGSize(width: 600, height: 200))
        struct In: Encodable { let loadId: Int; let signatureBase64: String; let role: String }
        struct Out: Decodable { let success: Bool; let signatureId: String? }
        let n = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation(
                "documents.signBol",
                input: In(loadId: n, signatureBase64: b64, role: "shipper")
            )
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("306 · BOL sign · Night") {
    BolCounterSignScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("306 · BOL sign · Afternoon") {
    BolCounterSignScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
