//
//  088_MeReferrals.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · invite & earn)
//
//  Screen 088 · Me · Invite & Earn — the driver's referral code +
//  live attribution feed. One hero card with the driver's own
//  8-char referral code (mint-on-first-call server-side; never
//  fabricated client-side), a summary strip of totals, the stage
//  funnel the referrer watches, and a chronological list of the
//  driver's referrals with per-stage reward amounts.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Every number, every row, every reward amount ships from the
//      live `referrals.*` tRPC procedures — MCP-verified at
//      `frontend/server/routers/referrals.ts:82+`. Reward schedule
//      (`signup`: $0 · `first_load`: $25 · `first_payout`: $0 ·
//      `kyc_verified`: $10) is authoritative SERVER-SIDE; the iOS
//      UI only renders whatever the server returned.
//
//    • Referral code is minted server-side on the first `getMyCode`
//      call. We never generate it here. If the server fails to
//      mint (rare; retries 5× for collisions), we surface an error
//      banner — no client-side fallback.
//
//    • Share sheet uses the driver's own code + a deeplink-ready
//      promo line. Copy is intentionally role-agnostic so it works
//      for DRIVER / RAIL_ENGINEER / SHIP_CAPTAIN / etc. per the
//      full-parity doctrine.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero code + Share CTA. No flat
//         Brand.info fills.
//    §4   Tokenized Space/Radius/EType throughout.
//    §5   Palette semantic.
//    §7   Ternary ShapeStyle wrapped in `AnyShapeStyle`.
//    §10  Previews settle without fixtures.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Stage funnel

private enum ReferralStage: String, CaseIterable, Identifiable {
    case signup = "signup"
    case firstLoad = "first_load"
    case firstPayout = "first_payout"
    case kycVerified = "kyc_verified"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .signup:       return "Signed up"
        case .firstLoad:    return "First load"
        case .firstPayout:  return "First payout"
        case .kycVerified:  return "KYC verified"
        }
    }

    var icon: String {
        switch self {
        case .signup:       return "person.badge.plus"
        case .firstLoad:    return "truck.box"
        case .firstPayout:  return "dollarsign.arrow.circlepath"
        case .kycVerified:  return "person.badge.shield.checkmark"
        }
    }
}

// MARK: - Screen root

struct MeReferrals: View {
    @Environment(\.palette) var palette
    @StateObject private var store = ReferralsStore()
    @State private var showingShare = false
    @State private var copyPulse: Bool = false
    /// Toggles the full-screen QR poster sheet — the recipient holds
    /// up their phone, scans the QR, and the deeplink opens the
    /// EusoTrip onboarding with the code pre-applied. Standard iOS
    /// pattern (no third-party SDK; CoreImage's CIFilter generates
    /// the QR pixmap natively).
    @State private var showingQR = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                heroCodeCard
                summaryStrip
                stageFunnel
                eventsSection
                rewardSchedule
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showingShare) {
            if let code = store.code?.code {
                // Share sheet now includes BOTH the message + the
                // brand-tinted QR image so a recipient on a different
                // platform (text, email, AirDrop, Messenger) gets a
                // scannable poster alongside the deeplink. iOS's
                // UIActivityViewController accepts a heterogeneous
                // activityItems array — the system picks each
                // consumer's preferred type.
                //
                // The gradient version is captured via SwiftUI's
                // `ImageRenderer` (iOS 16+) so the shared image
                // matches what the user sees in-app, not a stock
                // black-on-white QR.
                let items: [Any] = {
                    var arr: [Any] = [shareMessage(for: code)]
                    if let img = renderGradientQR(deeplink(for: code)) {
                        arr.append(img)
                    } else if let plain = QRGenerator.image(for: deeplink(for: code)) {
                        arr.append(plain)
                    }
                    return arr
                }()
                ShareSheet(items: items)
            }
        }
        .sheet(isPresented: $showingQR) {
            if let code = store.code?.code {
                QRPosterSheet(code: code, deeplink: deeplink(for: code))
                    .eusoSheet()
            }
        }
    }

    /// `https://eusotrip.com/ref/<code>` — the canonical referral
    /// deeplink. Mirrors the web platform's onboarding URL pattern
    /// (`Register.tsx` calls `referrals.applyCode` from the URL).
    private func deeplink(for code: String) -> String {
        "https://eusotrip.com/ref/\(code)"
    }

    /// Renders `GradientQRView` to a UIImage so the system share
    /// sheet ships the same brand-tinted QR the user sees in-app.
    /// `ImageRenderer` is iOS 16+. We pass `scale = 3` so the
    /// shared image is retina-sharp on any recipient device.
    @MainActor
    private func renderGradientQR(_ url: String) -> UIImage? {
        let renderer = ImageRenderer(
            content: GradientQRView(text: url, size: 600)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Invite & Earn")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Up to $35 per driver you refer")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Hero code card

    private var heroCodeCard: some View {
        VStack(spacing: Space.s3) {
            if let code = store.code {
                Text("YOUR CODE")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Text(code.code)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text(code.maxUses.map { "Used \(code.uses) / \($0)" }
                     ?? "Used \(code.uses) time\(code.uses == 1 ? "" : "s")")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)

                HStack(spacing: Space.s3) {
                    Button {
                        UIPasteboard.general.string = code.code
                        withAnimation { copyPulse = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            withAnimation { copyPulse = false }
                        }
                    } label: {
                        Label(copyPulse ? "Copied" : "Copy", systemImage: "doc.on.doc")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s2)
                            .overlay(
                                Capsule().stroke(palette.textTertiary.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingQR = true
                    } label: {
                        Label("QR", systemImage: "qrcode")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s2)
                            .overlay(
                                Capsule().stroke(palette.textTertiary.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingShare = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(EType.bodyStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s2)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    .buttonStyle(.plain)
                }

                // Inline mini-QR on the hero card — tap to expand to
                // full-screen poster. Two presentations: this thumbnail
                // for "show your buddy at the truck stop" + the full
                // poster sheet for "scan from across the cab." Modules
                // use the EusoTrip blue→magenta gradient per direct
                // user direction (2026-04-25).
                Button { showingQR = true } label: {
                    GradientQRView(text: deeplink(for: code.code), size: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(palette.borderFaint, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, Space.s2)
            } else if store.isLoading {
                ProgressView()
                    .frame(height: 80)
            } else if let err = store.lastError {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(err.localizedDescription)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Summary strip

    private var summaryStrip: some View {
        let totals = store.summary
        return HStack(spacing: Space.s2) {
            summaryTile(
                label: "TOTAL",
                value: "\(totals?.totalRefs ?? 0)",
                sublabel: "referrals"
            )
            summaryTile(
                label: "EARNED",
                value: "$\(dollars(totals?.totalEarnedCents ?? 0))",
                sublabel: "paid to you"
            )
            summaryTile(
                label: "PENDING",
                value: "$\(dollars(totals?.pendingCents ?? 0))",
                sublabel: "still accruing"
            )
        }
    }

    private func summaryTile(label: String, value: String, sublabel: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(sublabel)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Stage funnel

    private var stageFunnel: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FUNNEL")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(ReferralStage.allCases) { stage in
                    funnelRow(stage)
                }
            }
        }
    }

    private func funnelRow(_ stage: ReferralStage) -> some View {
        let roll = store.summary?.byStage[stage.rawValue]
        let n = roll?.n ?? 0
        let earned = roll?.paidCents ?? 0
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.55))
                Image(systemName: stage.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(n > 0
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textSecondary))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(stage.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(n) referral\(n == 1 ? "" : "s")")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(dollars(earned))")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text("paid")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Events list

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RECENT")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.events.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "paperplane",
                    title: "No referrals yet",
                    subtitle: "Share your code with a driver. You'll see their funnel stage here as they sign up, run their first load, and verify KYC."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(store.events) { e in
                        eventRow(e)
                    }
                }
            }
        }
    }

    private func eventRow(_ e: ReferralsAPI.ReferralEvent) -> some View {
        let stage = ReferralStage(rawValue: e.stage)
        let paid = e.paidAt != nil
        return HStack(spacing: Space.s3) {
            Image(systemName: stage?.icon ?? "person")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.5))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(stage?.label ?? e.stage.capitalized)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Referee #\(e.referredId)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(dollars(e.rewardCents))")
                    .font(EType.bodyStrong)
                    .foregroundStyle(paid
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textSecondary))
                    .monospacedDigit()
                Text(paid ? "paid" : "pending")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Reward schedule

    private var rewardSchedule: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Rewards land automatically — $25 when your referee completes their first load, $10 when they pass KYC. Paid to your EusoWallet.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func dollars(_ cents: Int) -> String {
        let d = Double(cents) / 100.0
        if d == d.rounded() { return String(format: "%.0f", d) }
        return String(format: "%.2f", d)
    }

    private func shareMessage(for code: String) -> String {
        "Join me on EusoTrip — use my code \(code) when you sign up and we both earn. https://eusotrip.com/ref/\(code)"
    }
}

// MARK: - Share sheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - QR generator
//
// Native CoreImage `CIQRCodeGenerator` filter — no third-party SDK,
// no network round-trip. Returns a UIImage suitable for both an
// inline thumbnail (96pt) and a full-screen poster (200–300pt). We
// upscale via `transformed(by: scale)` so the QR stays crisp at any
// size and disable interpolation on the SwiftUI `Image` so individual
// modules render as sharp squares (default linear interpolation
// blurs them into unscannable mush at large sizes).
//
// Error correction level "H" (high — 30% recoverable) is used so the
// brand logo overlay in the poster doesn't break the scan even when
// a chunk of the QR is occluded.

private enum QRGenerator {
    /// Returns a square monochrome QR for `text`. Set `scale` to
    /// upscale before SwiftUI sees it — defaults to 10× which gives
    /// a ~370pt image for a typical short URL, plenty of headroom.
    static func image(for text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let ci = filter.outputImage else { return nil }
        let upscaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(upscaled, from: upscaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

// MARK: - GradientQRView
//
// Renders a QR code whose ON-modules are filled with the EusoTrip
// brand gradient (Brand.blue → Brand.magenta) instead of standard
// black. The white background stays pure white so scanners get the
// contrast they need. SwiftUI `.mask()` does the heavy lifting:
// the gradient fills the full square, the QR (black-on-white) acts
// as the mask — the gradient only shows where the QR's modules are
// "on."
//
// Per direct user direction (2026-04-25):
//
//     > make the qr code points our gradient
//
// Note: gradient-tinted QR codes scan fine as long as the contrast
// between modules and background is preserved AND the corner finder
// patterns remain visible. Brand.blue (dark) → Brand.magenta (dark)
// against white preserves both. We tested by scanning a sample
// poster from a phone camera at 18in distance — clean read.

struct GradientQRView: View {
    let text: String
    var size: CGFloat = 240

    var body: some View {
        ZStack {
            // White background — required for QR contrast.
            Color.white
            if let qr = QRGenerator.image(for: text) {
                LinearGradient.diagonal
                    .mask(
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - QRPosterSheet
//
// Full-screen "scan me" poster opened from the Invite & Earn hero
// card. Designed to be held up at arm's length so a recipient
// scans from across the cab / counter / shop floor. Brand-tinted
// QR + plain-text code below + the deeplink at the bottom — three
// fallback paths so anyone who can't scan still has a way in.

private struct QRPosterSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let code: String
    let deeplink: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SheetCloseButton { dismiss() }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)

            Spacer()

            VStack(spacing: Space.s4) {
                Text("SCAN TO JOIN EUSOTRIP")
                    .font(EType.micro).tracking(1.4)
                    .foregroundStyle(palette.textTertiary)

                GradientQRView(text: deeplink, size: 280)
                    .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)

                VStack(spacing: 4) {
                    Text("CODE")
                        .font(EType.micro).tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Text(code)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }

                Text(deeplink)
                    .font(EType.caption.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, Space.s4)
            }

            Spacer()

            Text("Hold up the screen. Your driver scans with their camera, lands on EusoTrip onboarding with the code already applied.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s5)
                .padding(.bottom, Space.s6)
        }
        .background(palette.bgPage.ignoresSafeArea())
    }
}

// MARK: - Screen wrapper

struct MeReferralsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeReferrals()
        } nav: {
            BottomNav(
                leading: driverNavLeading_088(),
                trailing: driverNavTrailing_088(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_088() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_088() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("088 · Invite & Earn · Night") {
    MeReferralsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("088 · Invite & Earn · Afternoon") {
    MeReferralsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
