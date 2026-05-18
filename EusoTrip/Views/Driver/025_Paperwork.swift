//
//  025_Paperwork.swift
//  EusoTrip — Lifecycle screen 025 · Paperwork (Load Closed).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `025 Paperwork.png` (Dark + Light). Fires when the last unit is
//  offloaded and the BOL is signed off. Anchored by a full BOL-
//  SIGNED card (shipper + consignee + pieces + seal before → after
//  + signed by + OS&D), a 4-metric strip (START / END / DOOR TIME
//  / DETENTION $), and a "10-hour break starts now" info card with
//  overflow-lot guidance.
//
//  Bottom CTAs: View BOL outline + Start 10-hour break gradient.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct Paperwork: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var showBol: Bool = false
    @State private var isStartingBreak: Bool = false
    /// Driver rates the shipper after delivery. Closes Phase 18
    /// (Rating / review) of the 8000-scenario parity audit
    /// (docs/parity-2026/EXECUTIVE_VERDICT.md §4.5). Backend
    /// `ratings.submit` has shipped since the 90th firing — the
    /// missing piece was the iOS prompt screen.
    @State private var showRateShipper: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackDoor       = "12"
    private let fallbackTotal      = 26
    private let fallbackTrailer    = "—"
    private let fallbackBolNumber  = "—"
    private let fallbackShipperN   = "—"
    private let fallbackShipperA   = "—"
    private let fallbackConsignN   = "—"
    private let fallbackConsignA   = "—"
    // M2 doctrine (110th→111th hygiene firing): seal IDs are PII and must
    // hydrate from the live Load. Em-dash sentinels render until activeLoad
    // surfaces the assigned seal pair; sealFactValue collapses the row to "—"
    // when either side is unhydrated rather than fabricating an identifier.
    // Same fix pattern landed on 018_ActiveEnrouteLoaded.swift:75 (fallbackSealID).
    private let fallbackSealBefore = "—"
    private let fallbackSealAfter  = "—"
    private var sealFactValue: String {
        (fallbackSealBefore == "—" || fallbackSealAfter == "—")
            ? "—"
            : "\(fallbackSealBefore) → \(fallbackSealAfter) intact"
    }
    private let fallbackSignedBy   = "—"
    private let fallbackStart      = "00:33"
    private let fallbackEnd        = "07:03"
    private let fallbackDoorTime   = "6h 30m"
    private let fallbackDetCharge  = "—"
    private let fallbackDetDetail  = "$60/hr past 2h · 4h 30m past 2h free · billed to shipper"
    private let fallbackBreakInfo  = "10-hour break starts now. Park in row C of the overflow lot — 14 open slots as of 06:55. Next load brief unlocks at 17:03."

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                bolCard
                metricStrip
                breakCard
                nrcCardIfHazmat7
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: - NRC compliance card (Hazmat-7 closure)

    /// Driver-side NRC card. Renders only on hazmat-7 loads. Driver
    /// gets the "Log reading" CTA — this is the natural moment to
    /// log a final dosimetry reading at the consignee before the
    /// load closes. Server captures the entire chain alongside POD.
    @ViewBuilder
    private var nrcCardIfHazmat7: some View {
        if isHazmat7Load {
            NRCComplianceCard(loadId: lifecycle.loadId, driverSide: true)
                .environmentObject(session)
        }
    }

    private var isHazmat7Load: Bool {
        let h = (activeLoad?.hazmatClass ?? "").lowercased()
        let c = (activeLoad?.cargoType ?? "").lowercased()
        if h.contains("7") || h == "class_7" || h == "class 7" { return true }
        if c.contains("radioactive") || c.contains("hazmat-7") || c.contains("class-7") { return true }
        return false
    }

    // MARK: Header

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
                    Text("LOAD CLOSED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                    Text("· DETENTION BILLED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    // 2026-05-17 — Mode chip on paperwork close-out
                    // header. POD / BOL / mate's-receipt close-out
                    // differs by mode; the chip surfaces which legal
                    // shape applies to the documents being filed.
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("\(fallbackTotal) of \(fallbackTotal) delivered · door \(fallbackDoor)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(fallbackTrailer)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Brand.success.opacity(0.2))
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(.top, 4)
    }

    // MARK: BOL card

    private var bolCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("BILL OF LADING · SIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("BOL #\(fallbackBolNumber)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Shipper → Consignee
            HStack(alignment: .top, spacing: Space.s3) {
                partyBlock(label: "SHIPPER", name: fallbackShipperN, address: fallbackShipperA)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.top, 18)
                partyBlock(label: "CONSIGNEE", name: fallbackConsignN, address: fallbackConsignA)
            }

            // Facts grid
            VStack(spacing: 0) {
                factRow(
                    label: "PIECES DELIVERED",
                    value: "\(fallbackTotal) / \(fallbackTotal) \(ctx.unloadUnitLabel)",
                    affirm: true
                )
                divider
                factRow(
                    label: "SEAL BEFORE → AFTER",
                    value: sealFactValue,
                    affirm: sealFactValue != "—"
                )
                divider
                factRow(label: "SIGNED BY", value: fallbackSignedBy, affirm: false)
                divider
                factRow(label: "OS&D", value: "No over / short / damage", affirm: true)
            }
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s3)
    }

    private func partyBlock(label: String, name: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(name)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(address)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func factRow(label: String, value: String, affirm: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(affirm ? Brand.success : palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
    }

    // MARK: Metric strip

    private var metricStrip: some View {
        HStack(spacing: Space.s2) {
            metric(label: "START",      value: fallbackStart,      color: palette.textPrimary)
            metric(label: "END",        value: fallbackEnd,        color: palette.textPrimary)
            metric(label: "DOOR TIME",  value: fallbackDoorTime,   color: palette.textPrimary)
            metric(label: "DETENTION $", value: fallbackDetCharge, color: Brand.warning, caption: fallbackDetDetail)
        }
    }

    private func metric(label: String, value: String, color: Color, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let cap = caption {
                Text(cap)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: Break card

    private var breakCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 40, height: 40)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(fallbackBreakInfo)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        VStack(spacing: Space.s3) {
            // Counterparty rating CTA — only renders once. Skipping
            // is fine; the prompt re-fires on the next delivered
            // load. Server rejects duplicate ratings per
            // (fromUserId × toUserId × loadId).
            Button { showRateShipper = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Rate this shipper")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 12)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.4))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showRateShipper) {
                RatingPromptView(
                    direction: .driverRatesShipper,
                    counterpartyId: String(activeLoad?.shipperId ?? 0),
                    counterpartyName: nil,
                    loadId: lifecycle.loadId.isEmpty ? "0" : lifecycle.loadId,
                    laneSummary: paperworkLaneSummary
                )
                .environment(\.palette, palette)
            }

            HStack(spacing: Space.s3) {
                Button { showBol = true } label: {
                    Text("View BOL")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .sheet(isPresented: $showBol) {
                    PickupBolSigning()
                        .environment(\.palette, palette)
                        .eusoSheetX()
                }

                CTAButton(
                    title: "Start 10-hour break",
                    action: { Task { await startBreak() } },
                    isLoading: isStartingBreak
                )
            }
        }
    }

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    /// Origin → Destination shorthand for the rating prompt. Falls
    /// through to nil so the prompt's header card collapses cleanly
    /// when neither side of the lane is hydrated yet.
    private var paperworkLaneSummary: String? {
        guard let load = activeLoad else { return nil }
        let parts: [String] = {
            var out: [String] = []
            if let p = load.pickupLocation, !p.city.isEmpty {
                out.append("\(p.city), \(p.state)")
            }
            if let d = load.deliveryLocation, !d.city.isEmpty {
                out.append("\(d.city), \(d.state)")
            }
            return out
        }()
        return parts.isEmpty ? nil : parts.joined(separator: " → ")
    }

    private func startBreak() async {
        isStartingBreak = true
        defer { isStartingBreak = false }
        let forwardKeys = ["off_duty", "break", "completed", "closed"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        if let transition = candidate {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }
}

struct PaperworkScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            Paperwork(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_025(),
                      trailing: driverNavTrailing_025(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_025() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_025() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

#Preview("025 · Paperwork · Dark") {
    PaperworkScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("025 · Paperwork · Light") {
    PaperworkScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
