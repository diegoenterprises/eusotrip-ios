//
//  309_WalletPass.swift
//  EusoTrip — Shipper · Add to Apple Wallet (Arc H).
//

import SwiftUI

struct WalletPassScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            WalletPassBody(loadId: loadId)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct WalletPassBody: View {
    @Environment(\.palette) private var palette

    let loadId: String

    @State private var adding = false
    @State private var resultText: String?
    @State private var resultKind: ResultKind = .info
    @State private var inlineQrPayload: String?
    @State private var inlineShortCode: String?

    private enum ResultKind { case success, info, error }

    private var normalizedLoadId: String {
        EusoWalletPassService.numericLoadId(from: loadId)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                passCard
                if let resultText {
                    resultBanner(resultText, kind: resultKind)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                WalletEyebrow(glyph: .wallet, text: "SHIPPER · APPLE WALLET")
                Text("Pickup credential")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Add a signed pickup credential to Apple Wallet for faster gate and pickup verification.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 38, height: 38)
                WalletGlyph(kind: .wallet, size: 18, tint: AnyShapeStyle(Color.white), lineWidth: 1.6)
            }
        }
    }

    private var passCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOAD")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(normalizedLoadId.isEmpty ? loadId : normalizedLoadId)
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("Your pickup credential is signed, checked on-device and opened directly in Apple Wallet.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                EusoQRView(
                    kind: inlineQrPayload.map { .raw(text: $0) }
                        ?? .loadCredential(loadId: normalizedLoadId, mode: .credential),
                    role: .shipper,
                    size: 92,
                    cornerRadius: 10
                )
            }

            if let inlineShortCode {
                HStack {
                    Text("GATE CODE")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(inlineShortCode)
                        .font(EType.mono(.body))
                        .tracking(3.0)
                        .foregroundStyle(palette.textPrimary)
                        .accessibilityLabel("Gate fallback code \(inlineShortCode.map(String.init).joined(separator: " "))")
                }
            }

            Button {
                Task { await addToWallet() }
            } label: {
                HStack(spacing: Space.s2) {
                    if adding {
                        ProgressView().tint(.white)
                    } else {
                        WalletGlyph(kind: .wallet, size: 16, tint: AnyShapeStyle(Color.white), lineWidth: 1.8)
                    }
                    Text(adding ? "Opening Apple Wallet..." : "Add to Apple Wallet")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(adding)
            .opacity(adding ? 0.7 : 1)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func resultBanner(_ text: String, kind: ResultKind) -> some View {
        let color: Color = {
            switch kind {
            case .success: return Brand.success
            case .info: return palette.textSecondary
            case .error: return Brand.danger
            }
        }()
        return HStack(alignment: .top, spacing: Space.s2) {
            WalletGlyph(kind: .pulse, size: 14, tint: AnyShapeStyle(color), lineWidth: 1.5)
                .padding(.top, 2)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(kind == .error ? Brand.danger : palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md, intensity: .standard)
    }

    @MainActor
    private func apply(_ result: EusoWalletPassResult) {
        switch result {
        case .presented:
            resultKind = .success
            resultText = "Apple Wallet is open with the signed pass."
        case .signingUnavailable(let qrPayload, let shortCode):
            inlineQrPayload = qrPayload
            inlineShortCode = shortCode
            resultKind = .info
            resultText = "Apple Wallet signing is unavailable for this credential. The in-app QR and gate code are live and can be validated at the gate."
        case .failure(let message):
            resultKind = .error
            resultText = message
        }
    }

    @MainActor
    private func addToWallet() async {
        guard !adding else { return }
        adding = true
        resultText = nil
        let result = await EusoWalletPassService.shared.addPass(forLoadId: loadId)
        adding = false
        apply(result)
    }
}

#Preview("309 · Wallet pass · Night") {
    WalletPassScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}

#Preview("309 · Wallet pass · Afternoon") {
    WalletPassScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
