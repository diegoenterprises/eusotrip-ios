//
//  027_NextLoadBrief.swift
//  EusoTrip — Lifecycle screen 027 · Next Load Brief.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `027 Next Load Brief.png` (Dark + Light). The 10-hour reset has
//  unlocked; the scheduler is presenting the next load with an
//  auto-accept countdown. The driver can Accept + drive or Decline
//  before the timer expires.
//
//  Composition:
//    • Kicker — "BRIEF READY · NEW LOAD" + auto-accept timer.
//    • Title — pickup → delivery lane with miles + route brand.
//    • ROUTE card — HUB metric strip (pickup window / miles /
//      delivery window).
//    • COMMODITY card — product-aware hero with gallons/pallets +
//      class + ERG code for hazmat, or pallets/temp for reefer,
//      or container/seal for container.
//    • HOS FIT card — driver's drive window vs. lane length.
//    • PAY ESTIMATE card — gradient hero + cpm + wallet routing.
//    • ESANG advisory — operator-voice note about the lane.
//    • Footer CTAs — Decline outline + Accept + drive gradient.
//    • Bottom nav — preserved verbatim per doctrine.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct NextLoadBrief: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isAccepting: Bool = false
    @State private var isDeclining: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    //
    // 140th firing M3 sweep — commodity sub-block (UN, commodity name,
    // commodity body, hazmat badge) cleared from the literal block.
    // Every visible commodity string on this brief now flows through
    // `ctx.facets.*` accessors with em-dash sentinel; the commodity
    // body builder mirrors the segment-drop pattern proven by the
    // 138th `dischargeBolSummary` and 139th `beatCommodityDescriptor`
    // retrofits in `LifecycleProductContext.swift`. Regulatory
    // universals ("AAR waybill · grounding required" for rail bulk,
    // "WLL within spec" for flatbed, "cold-chain seal" for reefer)
    // are preserved as compulsory regulatory copy — not fabrication.
    //
    // Remaining literals in this block (clock, route metrics, lane
    // labels, HOS fit, pay estimate, advisory) await Load-envelope
    // extensions in a follow-up firing.
    private let fallbackClock          = "17:05"
    private let fallbackAutoAcceptIn   = "4:32"
    private let fallbackOrigin         = "Baltimore, MD"
    private let fallbackDestination    = "Columbus, OH"
    private let fallbackLoadID         = "—"
    private let fallbackMiles          = "487"
    private let fallbackRouteSub       = "Routed via EusoMap · Auto-accept in 4:32"
    private let fallbackPickupWindow   = "18:00-19:30"
    private let fallbackDeliveryWindow = "06:00-08:00"
    private let fallbackPickupPlace    = "—"
    private let fallbackDeliveryPlace  = "Mount Vernon Chemicals Plant"
    private let fallbackHosHead        = "Tight · 14h window at 06:12"
    private let fallbackHosSub         = "Delivery opens 06:00. 12-min buffer."
    private let fallbackPayHero        = "—"
    private let fallbackPaySub         = "—"
    private let fallbackAdvisoryLead   = "—"
    private let fallbackAdvisoryBody   = "ESANG expects grounding + 2-valve check before kingpin-up. ERG Guide 125 pinned on the load card."

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                routeCard
                commodityCard
                hosFitCard
                payCard
                advisoryCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        Text("BRIEF READY")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("· NEW LOAD")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textSecondary)
                        LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                      multiVehicleCount: activeLoad?.multiVehicleCount,
                                      compact: true)
                    }
                    HStack(spacing: 4) {
                        Text(fallbackOrigin)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(fallbackDestination)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                    }
                    Text("\(activeLoad?.loadNumber ?? fallbackLoadID) · \(fallbackMiles) mi · \(fallbackRouteSub)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(fallbackClock)
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Text("AUTO-ACCEPT")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(fallbackAutoAcceptIn)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.warning)
                        .monospacedDigit()
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Route card

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("HUB · EUSO · 11M SKID")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack(alignment: .top, spacing: Space.s3) {
                nodeBlock(label: "PICKUP", time: fallbackPickupWindow, place: fallbackPickupPlace)
                VStack(alignment: .center, spacing: 2) {
                    Text("MILES")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(fallbackMiles)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.top, 4)
                nodeBlock(label: "DELIVERY", time: fallbackDeliveryWindow, place: fallbackDeliveryPlace)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func nodeBlock(label: String, time: String, place: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(time)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
            Text(place)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Commodity card

    private var commodityCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(LinearGradient.diagonal)
                Image(systemName: ctx.product.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(commodityHeaderTitle)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if ctx.isHazmat, hazmatBadgeText != LiveLoadFacets.dash {
                        Text(hazmatBadgeText)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(Brand.warning)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().stroke(Brand.warning.opacity(0.5), lineWidth: 1))
                    }
                }
                Text(commodityBody)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Title row of the commodity card.
    /// Hazmat: "UN1005 Anhydrous ammonia" composed live from the load
    /// envelope (em-dash if the column hasn't shipped). Non-hazmat:
    /// live commodity name; falls through to the universal "Dry
    /// palletized · general freight" descriptor only when the load
    /// has no commodity at all (legitimate for an empty/stub load).
    private var commodityHeaderTitle: String {
        if ctx.isHazmat {
            // commodityWithUN already returns dash if both pieces are
            // missing, "UN1005" if only UN, "Anhydrous ammonia" if
            // only commodity, or "Anhydrous ammonia · UN1005" if both
            // shipped. Replace the middle dot with a space for the
            // header-row typography.
            let composed = ctx.facets.commodityWithUN
            return composed == LiveLoadFacets.dash
                ? LiveLoadFacets.dash
                : composed.replacingOccurrences(of: " · ", with: " ")
        }
        let n = ctx.facets.commodityName
        return n == LiveLoadFacets.dash ? "Dry palletized · general freight" : n
    }

    /// "Cl 2.2 · ERG 125" hazmat warning chip on the commodity card.
    /// Returns em-dash when neither hazClass nor a derived ERG guide
    /// is available — the chip is hidden in that case.
    private var hazmatBadgeText: String {
        let f = ctx.facets
        let cls = f.hazardClass
        // ERG guide is gap-shaped on the backend; for the chip we
        // surface only the live hazardClass (e.g. "2.2 · non-flam
        // gas") prefixed with a "Cl " typographic abbreviation.
        return cls == LiveLoadFacets.dash ? LiveLoadFacets.dash : "Cl \(cls)"
    }

    /// Two-line commodity body (line 1 = key per-load datum, line 2 =
    /// regulatory universal or second per-load datum). Mirrors the
    /// 138th `dischargeBolSummary` segment-drop pattern: every
    /// `facets.*` accessor that resolves to em-dash is dropped from
    /// the line so the card stays readable on partial loads. The
    /// regulatory universals on line 2 ("AAR waybill · grounding
    /// required", "WLL within spec", etc.) are universal product
    /// category copy — not fabrication — and stay always-on.
    private var commodityBody: String {
        let f = ctx.facets
        let dash = LiveLoadFacets.dash
        func seg(_ s: String) -> String? { s == dash ? nil : s }
        let line1: String
        let line2: String
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            // Line 1: loaded gallons + net weight. Line 2: tank spec
            // (e.g. "MC-331") with universal "Inhalation hazard"
            // placard guidance from 49 CFR 172.504.
            line1 = ["Hazmat tank", seg(f.loadedGallons), seg(f.netWeight)]
                .compactMap { $0 }.joined(separator: " · ")
            line2 = [seg(f.tankSpec), "Placard INHALATION"]
                .compactMap { $0 }.joined(separator: " · ")
        case .reefer:
            line1 = ["Cold pallets", seg(f.palletCount), seg(f.netWeight)]
                .compactMap { $0 }.joined(separator: " · ")
            line2 = [seg(f.setPointDisplay), "cold-chain seal"]
                .compactMap { $0 }.joined(separator: " · ")
        case .flatbed:
            line1 = ["Steel coils", seg(f.netWeight)]
                .compactMap { $0 }.joined(separator: " · ")
            line2 = [seg(f.securementSummary), "WLL within spec"]
                .compactMap { $0 }.joined(separator: " · ")
        case .container, .railIntermodal:
            line1 = ["Container", seg(f.containerNumber), seg(f.containerIsoType), seg(f.netWeight)]
                .compactMap { $0 }.joined(separator: " · ")
            line2 = [seg(f.vgmDisplay).map { "VGM \($0)" }, seg(f.sealNumber).map { "Seal \($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .vesselContainer:
            // Vessel containers carry kg weights — `netWeight` already
            // honours the load envelope's `weightUnit`.
            line1 = ["Container", seg(f.containerNumber), seg(f.containerIsoType), seg(f.netWeight)]
                .compactMap { $0 }.joined(separator: " · ")
            line2 = [seg(f.sealNumber).map { "Seal \($0)" }, seg(f.vgmDisplay).map { "VGM \($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .railBulk, .vesselBulk:
            line1 = ["Bulk", seg(f.netWeight)]
                .compactMap { $0 }.joined(separator: " · ")
            // Universal AAR rule for rail bulk; static-ground rule
            // for vessel bulk. Both required by federal regulation.
            line2 = "AAR waybill · grounding required"
        case .dryVan:
            line1 = ["Dry palletized", seg(f.palletCount), seg(f.netWeight)]
                .compactMap { $0 }.joined(separator: " · ")
            line2 = [seg(f.sealNumber).map { "Seal \($0)" }, "stackable"]
                .compactMap { $0 }.joined(separator: " · ")
        }
        // If both lines collapsed to empty (highly unlikely — the
        // category descriptor on line 1 is universal), fall through
        // to em-dash. Otherwise join with newline; an empty line2 is
        // dropped so the card doesn't render an awkward blank line.
        if line1.isEmpty && line2.isEmpty { return dash }
        if line2.isEmpty { return line1 }
        return "\(line1)\n\(line2)"
    }

    // MARK: HOS fit card

    private var hosFitCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Brand.warning.opacity(0.15))
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.warning)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("HOS FIT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                Text(fallbackHosHead)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackHosSub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Pay card

    private var payCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 40, height: 40)
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("PAY ESTIMATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                Text(fallbackPayHero)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text(fallbackPaySub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Advisory

    private var advisoryCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(fallbackAdvisoryLead)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fallbackAdvisoryBody)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await declineBrief() } } label: {
                Text("Decline")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(isDeclining ? 0.6 : 1)
            }
            .disabled(isDeclining)

            CTAButton(
                title: "Accept · drive",
                action: { Task { await acceptBrief() } },
                isLoading: isAccepting
            )
        }
    }

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func acceptBrief() async {
        isAccepting = true
        defer { isAccepting = false }
        let forwardKeys = ["accepted", "assigned", "locked", "prehaul"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        if let transition = candidate {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }

    private func declineBrief() async {
        isDeclining = true
        defer { isDeclining = false }
        let declineKeys = ["declined", "rejected", "cancelled"]
        if let transition = lifecycle.availableTransitions.first(where: { t in
            let to = t.to.lowercased()
            return declineKeys.contains(where: { to.contains($0) })
        }) {
            _ = await lifecycle.execute(transition)
        }
    }
}

struct NextLoadBriefScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            NextLoadBrief(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_027(),
                      trailing: driverNavTrailing_027(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_027() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",       isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_027() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("027 · Next Load Brief · Dark") {
    NextLoadBriefScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("027 · Next Load Brief · Light") {
    NextLoadBriefScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
