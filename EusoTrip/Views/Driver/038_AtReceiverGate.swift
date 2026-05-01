//
//  038_AtReceiverGate.swift
//  EusoTrip — Lifecycle screen 038 · At Receiver Gate (credentials).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `038 At Receiver Gate.png`. Rig is at the perimeter; receiver
//  desk is pinged. Leads with an arrived-at-perimeter header,
//  3-step progress (SHOW CREDENTIALS live · SECURITY VERIFY · BAY
//  ASSIGNED), a driver credentials card with avatar + PIN block,
//  a 2×2 product-aware wallet grid, two bottom status chips, and
//  Call / Show pass at gate CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct AtReceiverGateFull: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isShowing: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackClock   = "21:15"
    private let fallbackGeofenceClock = "21:13"
    private let fallbackArrivalLine   = "—"
    private let fallbackAddress       = "7600 N ROOSEVELT HWY · GATE B-2"
    private let fallbackDeskState     = "RECEIVER DESK PINGED"
    private let fallbackDriverName    = "—"
    private let fallbackCDL           = "CDL X-XX"
    private let fallbackHazmatBadge   = "HAZMAT + TANK"
    private let fallbackPin           = "8-2-7-3"
    private let fallbackGuardTip      = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                arrivalStrip
                progressDots
                credentialsCard
                walletGrid
                statusChips
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("AT RECEIVER \(ctx.vertical.gateWord.uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(fallbackArrivalLine)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(fallbackAddress)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackClock)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("GEOFENCE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var arrivalStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.success)
            Text(fallbackDeskState)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.success)
            Spacer()
            Text(fallbackGeofenceClock)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(Brand.success.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var progressDots: some View {
        HStack(spacing: 0) {
            dotStep(index: 1, label: "SHOW CREDENTIALS", state: .now)
            connector()
            dotStep(index: 2, label: "SECURITY VERIFY",   state: .next)
            connector()
            dotStep(index: 3, label: "BAY ASSIGNED",      state: .next)
        }
    }

    private enum DotState { case done, now, next }
    private func dotStep(index: Int, label: String, state: DotState) -> some View {
        VStack(spacing: 4) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(Brand.success)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                case .now:
                    Circle().fill(LinearGradient.diagonal)
                    Text("\(index)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                case .next:
                    Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
                    Text("\(index)").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            .frame(width: 26, height: 26)
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(state == .now ? palette.textPrimary : palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func connector() -> some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(height: 1)
            .frame(maxWidth: 40)
            .padding(.bottom, 14)
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("STEP 1 · SHOW CREDENTIALS AT SECURITY HUT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.danger.opacity(0.5), lineWidth: 1))
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(palette.bgCardSoft).frame(width: 36, height: 36)
                    Text("ME").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(fallbackDriverName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(fallbackCDL)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if ctx.isHazmat {
                    Text(fallbackHazmatBadge)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
                }
            }

            // QR + PIN block
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.textPrimary)
                        .frame(width: 72, height: 72)
                    // Stylized QR
                    let tiles = 6
                    VStack(spacing: 1) {
                        ForEach(0..<tiles, id: \.self) { r in
                            HStack(spacing: 1) {
                                ForEach(0..<tiles, id: \.self) { c in
                                    Rectangle()
                                        .fill(((r * tiles + c) % 3 == 0) ? palette.bgPage : palette.textPrimary)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PIN · READ ALOUD AT GATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(fallbackPin)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
            }

            Text(fallbackGuardTip)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var walletGrid: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("IN YOUR WALLET FOR THIS STOP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            let items = walletItems
            VStack(spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    walletCell(items[safe: 0])
                    walletCell(items[safe: 1])
                }
                HStack(spacing: Space.s2) {
                    walletCell(items[safe: 2])
                    walletCell(items[safe: 3])
                }
            }
        }
    }

    private struct WalletItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let sub: String
    }

    private var walletItems: [WalletItem] {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            return [
                .init(icon: "doc.fill",            title: "BOL packet",      sub: "EUSO-PA-776"),
                .init(icon: "exclamationmark.triangle.fill", title: "Hazmat manifest", sub: "UN1005"),
                .init(icon: "calendar.badge.clock", title: "Sched window",   sub: "pinned"),
                .init(icon: "book.fill",           title: "ERG card",         sub: "Anhydrous NH3"),
            ]
        case .reefer:
            return [
                .init(icon: "doc.fill",        title: "BOL packet",    sub: "cold-chain"),
                .init(icon: "thermometer",      title: "Temp trace",    sub: "USDA frozen"),
                .init(icon: "calendar.badge.clock", title: "Sched window", sub: "pinned"),
                .init(icon: "seal.fill",        title: "Cold-seal photo", sub: "stored"),
            ]
        case .flatbed:
            return [
                .init(icon: "doc.fill",         title: "BOL packet",       sub: "wallet"),
                .init(icon: "link",             title: "Securement doc",   sub: "WLL sheet"),
                .init(icon: "calendar.badge.clock", title: "Sched window", sub: "pinned"),
                .init(icon: "person.fill.checkmark", title: "Rigger contact", sub: "standby"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(icon: "doc.fill",         title: "BOL + TIR",        sub: "wallet"),
                .init(icon: "cube.box.fill",    title: "Container / ISO",  sub: "ISO 4510"),
                .init(icon: "number",           title: "EDI 322",          sub: "armed"),
                .init(icon: "scalemass.fill",   title: "VGM",              sub: "filed"),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(icon: "doc.fill",         title: "Waybill",          sub: "AAR format"),
                .init(icon: "bolt.horizontal.fill", title: "Grounding log", sub: "ohms cap"),
                .init(icon: "calendar.badge.clock", title: "Sched window", sub: "pinned"),
                .init(icon: "tag.fill",         title: "Interchange tkt",  sub: "pinned"),
            ]
        case .dryVan:
            // 110th firing M2 retrofit: hardcoded "881204" seal id
            // excised. Seal photo subtitle now matches the generic copy
            // pattern used by every other product variant ("wallet",
            // "pinned", "pre-auth") — the actual seal value renders
            // when the Load hydrates the assigned seal field downstream
            // in the proof-of-delivery flow, not in the wallet preview.
            return [
                .init(icon: "doc.fill",        title: "BOL packet",       sub: "wallet"),
                .init(icon: "seal.fill",       title: "Seal photo",        sub: "wallet"),
                .init(icon: "calendar.badge.clock", title: "Sched window", sub: "pinned"),
                .init(icon: "person.fill",     title: "Lumper contact",    sub: "pre-auth"),
            ]
        }
    }

    private func walletCell(_ item: WalletItem?) -> some View {
        Group {
            if let item {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(palette.bgCardSoft)
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text(item.sub)
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.s2).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else {
                Color.clear
            }
        }
    }

    private var statusChips: some View {
        HStack(spacing: Space.s2) {
            Text("QUEUE · 1 of 1 · straight to dock")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Brand.success.opacity(0.12))
                .overlay(Capsule().stroke(Brand.success.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())
            Text("EUSOSHIELD · Handoff arming · 21:14")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .overlay(Capsule().stroke(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
                .clipShape(Capsule())
            Spacer()
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            // Receiver call CTA: dial only when the active load (or its
            // resolved receiver record) actually carries a phone number.
            // The 147th firing eradicated the "+17178542010" Yara North
            // America Figma fixture that previously short-circuited the
            // empty-closure on this button — we no longer fake an
            // outbound call when the load has no contact on file.
            let receiverPhone: String? = nil  // wired in once Load model
                                              // surfaces receiver.phone
                                              // from `loads.getActive`.
            Button {
                guard let raw = receiverPhone, !raw.isEmpty,
                      let url = URL(string: "tel://\(raw)") else { return }
                openURL(url)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(receiverPhone == nil ? "No phone on file" : "Call")
                        .font(EType.body.weight(.semibold))
                }
                .foregroundStyle(receiverPhone == nil ? palette.textSecondary : palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .disabled(receiverPhone == nil)
            CTAButton(
                title: "Show pass at \(ctx.vertical.gateWord)",
                action: { Task { await showPass() } },
                trailingIcon: "arrow.right",
                isLoading: isShowing
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func showPass() async {
        isShowing = true
        defer { isShowing = false }
        let keys = ["verified", "bay_assigned", "dock_assigned", "unloading"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

// Safe-index helper for the wallet grid.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct AtReceiverGateFullScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            AtReceiverGateFull(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_038(),
                      trailing: driverNavTrailing_038(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/038 At Receiver Gate.png` pins
// TRIPS current — at-perimeter QR-kiosk credential surface with
// canonical Michael Eusorone CDL-N-PA + HAZMAT/TANK chips. Icon set +
// trailing slot normalized to canonical 010-037 layout.
private func driverNavLeading_038() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_038() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("038 · At Receiver Gate · Dark") {
    AtReceiverGateFullScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("038 · At Receiver Gate · Light") {
    AtReceiverGateFullScreen(theme: Theme.light).preferredColorScheme(.light)
}
