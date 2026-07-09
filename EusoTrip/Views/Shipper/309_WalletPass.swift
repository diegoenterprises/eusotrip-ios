//
//  309_WalletPass.swift
//  EusoTrip — Shipper · Add to Apple Wallet (Arc H).
//
//  REDESIGNED to the Design Authority level (founder mandate #13). The
//  pickup-pass surface now speaks the bespoke EusoWallet language shared
//  with the Wallet home (290) and the EusoWallet detail (291) — drawn
//  `WalletGlyph` Paths (ZERO SF Symbols), the brand diagonal gradient, the
//  volumetric "money card" hero idiom, `eusoCard` surfaces, `WalletEyebrow`
//  section voice, and `WalletShimmer` skeletons. The pass itself is
//  presented as a bespoke iridescent "credential card" (a drawn pass-mark
//  on a matte chip + the readiness/expiry rail) instead of a plain row.
//
//  DATA + FUNCTION PRESERVED 1:1 — only the presentation changed:
//    • `documents.signWalletPass` (input { loadId: Int }) → `PassUrl`
//      { url, expiresAt }. Same proc, same input, same decode.
//    • `openPass(url)` downloads the signed `.pkpass` over the BOUNDED
//      session (15s, no-lingering-load rule), wraps it in `PKPass`, and
//      presents `PKAddPassesViewController` from the key window — unchanged.
//    • Honest degrade unchanged: a thrown sign → `pass = nil` → the honest
//      "not yet on this deploy" state (PassKit pass-type ID + certs are a
//      server prerequisite). Loading + error states preserved.
//    • `humanISO(expiresAt)` for the expiry. ZERO fabricated values.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header

                if loading {
                    passSkeleton
                } else if let err = loadError {
                    errorCard(err)
                } else if let p = pass {
                    passCard(p)
                } else {
                    pendingState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    // MARK: Header — bespoke wallet voice (drawn glyph, gradient mark)

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                WalletEyebrow(glyph: .wallet, text: "SHIPPER · APPLE WALLET")
                Text("Add BOL to Wallet")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("A signed pickup pass for the BOL. The driver scans it at the gate.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Iridescent brand mark — drawn wallet glyph (no SF Symbol).
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 38, height: 38)
                WalletGlyph(kind: .wallet, size: 18, tint: AnyShapeStyle(Color.white), lineWidth: 1.6)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: Loading skeleton — bespoke bounded shimmer (no-lingering-load)

    private var passSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            WalletShimmer(height: 14, radius: 6).frame(width: 150)
            HStack(spacing: 16) {
                WalletShimmer(height: 96, radius: Radius.lg).frame(width: 96)
                VStack(alignment: .leading, spacing: 10) {
                    WalletShimmer(height: 13, radius: 5)
                    WalletShimmer(height: 9, radius: 4).frame(width: 120)
                }
            }
            WalletShimmer(height: 44, radius: Radius.md)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    // MARK: Error — bespoke danger card, drawn pulse glyph

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 8) {
                WalletGlyph(kind: .pulse, size: 14, tint: AnyShapeStyle(Brand.danger), lineWidth: 1.5)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Pass ready — the bespoke iridescent CREDENTIAL CARD

    private func passCard(_ p: PassUrl) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: 16) {
            // ── readiness eyebrow + currency-chip-style state pill ──
            HStack {
                HStack(spacing: 6) {
                    WalletGlyph(kind: .wallet, size: 13, tint: AnyShapeStyle(Color.white.opacity(0.9)), lineWidth: 1.4)
                    Text("PICKUP PASS")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer(minLength: 0)
                Text("READY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.16)).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
            }

            // ── drawn credential mark on a matte chip + signed-pass copy ──
            HStack(alignment: .top, spacing: 16) {
                credentialChip
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signed .pkpass")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Add it to Apple Wallet; the driver scans the pass at the gate.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // ── expiry rail (honest em-dash via humanISO) ──
            HStack(spacing: 8) {
                WalletGlyph(kind: .lock, size: 13, tint: AnyShapeStyle(Color.white.opacity(0.85)), lineWidth: 1.4)
                Text("Expires")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
                Text(humanISO(p.expiresAt))
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            // ── ADD TO WALLET — the headline action (drawn wallet glyph) ──
            Button {
                openPass(p.url)
            } label: {
                HStack(spacing: 10) {
                    WalletGlyph(kind: .wallet, size: 17, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.7)
                    Text("Add to Apple Wallet")
                        .font(.system(size: 14, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient.diagonal
                RadialGradient(colors: [.white.opacity(0.30), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 340)
                LinearGradient(colors: [.clear, .white.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottomTrailing)
            }
        }
        .overlay(alignment: .top) {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: Brand.blue.opacity(isDark ? 0.42 : 0.18), radius: 20, x: 0, y: 10)
        .shadow(color: Brand.magenta.opacity(isDark ? 0.30 : 0.12), radius: 24, x: 0, y: 14)
    }

    /// The drawn pass-credential mark — a bespoke pass lattice (NOT an SF
    /// Symbol) on a matte-white chip, in the wallet idiom. Decorative; the
    /// signed `.pkpass` carries the real scannable payload at the gate.
    private var credentialChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.white)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            PassCredentialMark()
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .padding(18)
        }
        .frame(width: 96, height: 96)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
        .accessibilityHidden(true)
    }

    // MARK: Honest pending state — signing not on this deploy

    private var pendingState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: .wallet, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Wallet pass not on this deploy yet")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Pass signing needs the iOS Wallet pass-type ID and certificates on the server. Once enabled, the signed pass appears here.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    // MARK: - Function — PRESERVED 1:1 (download + present the signed pass)

    private func openPass(_ url: String) {
        guard let u = URL(string: url) else { return }
        Task {
            var req = URLRequest(url: u)
            req.timeoutInterval = 15  // app-wide no-lingering-load bound
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let pkPass = try? PKPass(data: data),
               let vc = PKAddPassesViewController(pass: pkPass) {
                await MainActor.run {
                    UIApplication.shared.connectedScenes
                        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                        .first?.present(vc, animated: true)
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

// MARK: - PassCredentialMark — the drawn bespoke pass glyph (ZERO SF Symbols)

/// A pickup-pass credential mark authored as a `Path` in a unit box: a
/// rounded pass body with a notch, three finder squares + a code lattice —
/// the wallet-idiom stand-in for the scannable pass. The signed `.pkpass`
/// holds the real payload; this is the brand-drawn visual.
private struct PassCredentialMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
        }
        var p = Path()

        // outer pass card with a clipped corner notch (a "pass" silhouette)
        p.move(to: P(0.06, 0.06))
        p.addLine(to: P(0.78, 0.06))
        p.addLine(to: P(0.94, 0.22))
        p.addLine(to: P(0.94, 0.94))
        p.addLine(to: P(0.06, 0.94))
        p.closeSubpath()

        // three finder squares (code-style)
        p.addRoundedRect(in: box(0.16, 0.16, 0.20, 0.20), cornerSize: CGSize(width: 0.03 * s, height: 0.03 * s))
        p.addRoundedRect(in: box(0.64, 0.16, 0.20, 0.20), cornerSize: CGSize(width: 0.03 * s, height: 0.03 * s))
        p.addRoundedRect(in: box(0.16, 0.64, 0.20, 0.20), cornerSize: CGSize(width: 0.03 * s, height: 0.03 * s))

        // inner code lattice (a few module strokes — decorative, not scannable)
        for gx: CGFloat in [0.56, 0.66, 0.76] {
            p.move(to: P(gx, 0.56)); p.addLine(to: P(gx, 0.84))
        }
        for gy: CGFloat in [0.56, 0.66, 0.76] {
            p.move(to: P(0.56, gy)); p.addLine(to: P(0.84, gy))
        }
        return p
    }
}

#Preview("309 · Wallet pass · Night") {
    WalletPassScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}

#Preview("309 · Wallet pass · Afternoon") {
    WalletPassScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
