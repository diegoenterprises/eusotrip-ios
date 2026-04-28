//
//  307_RateConSign.swift
//  EusoTrip — Shipper · Rate-confirmation sign (Arc H).
//

import SwiftUI
import PencilKit

struct RateConSignScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { RateConSignBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct RateConSignBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var canvas = PKCanvasView()
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Rate-con signed and sent to carrier.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                pad
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · RATE-CON · SIGN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Sign rate confirmation").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var pad: some View {
        SignaturePad(canvas: $canvas)
            .frame(height: 200)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button { canvas.drawing = PKDrawing() } label: {
                Text("Clear").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { Task { await submit() } } label: {
                HStack(spacing: 6) {
                    if sending { ProgressView().tint(.white) }
                    Text(sending ? "Submitting…" : "Sign rate-con")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(sending)
        }
    }

    private func submit() async {
        sending = true; actionError = nil
        let bounds = canvas.bounds
        let img = canvas.drawing.image(from: bounds, scale: UIScreen.main.scale)
        let b64 = img.pngData()?.base64EncodedString() ?? ""
        struct In: Encodable { let loadId: Int; let signatureBase64: String }
        struct Out: Decodable { let success: Bool }
        let n = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation("documents.signRateCon", input: In(loadId: n, signatureBase64: b64))
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

private struct SignaturePad: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvas.drawingPolicy = .anyInput
        return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

#Preview("307 · Rate-con sign · Night") {
    RateConSignScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("307 · Rate-con sign · Afternoon") {
    RateConSignScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
