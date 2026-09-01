//
//  710_RailConductorTrainOrders.swift
//  EusoTrip — 05 Rail · 710 Rail Conductor Train Orders and Track Warrants.
//  CONDUCTOR SIDE (RAIL_CONDUCTOR) · nav tab COMPLIANCE.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/710 Rail Conductor Train Orders and
//  Track Warrants.svg" — same sections, same order, same device:
//    eyebrow → headline → state chips → iridescent hairline → CURRENT AUTHORITY
//    hero → MILE-RANGE AUTHORITY CHART (one shared axis, every order a range
//    bar) → AUTHORITY AS OF (read-cached) strip → tri-country band → CTA pair.
//
//  ─── WIRING MANIFEST ─────────────────────────────────────────────────────────
//    railShipments.getRailShipments        EXISTS server/routers/railShipments.ts:421
//        → the conductor's rail shipment (the anchor; no shipment → honest empty)
//    railShipments.getRoutePlan EXISTS railShipments.ts:2882
//        → {shipmentId, routeDescription, legs[{road,from,to,miles,interchangeOut,ptcOk}],
//           ptcComplete, confirmed, confirmedAt} — the operating limits by name
//    railShipments.getRailCompliance       EXISTS server/routers/railShipments.ts:1788
//        → {inspections[], hazmatPermits[], status, totalInspections, failedCount}
//    railShipments.getFRASafetyCompliance  EXISTS server/routers/railShipments.ts:2118
//        → FRASafetyCompliance | null (enterprise feed; null → note stays hidden)
//    trackAuthority.getForTrain            STUB · named-gap RAIL-CDR-710-TRACK-WARRANTS
//    trackAuthority.repeatBack             STUB · named-gap RAIL-CDR-710-WARRANT-REPEAT-BACK
//
//  RBAC:    railReadProcedure (railShipments.ts:94) · RAIL_CONDUCTOR (server/_core/trpc.ts:33)
//  WS:      repeatBack (when built) broadcasts WS_EVENTS.RAIL_TRACKING_UPDATE
//           (shared/websocket-events.ts:412) on WS_CHANNELS.RAIL_DISPATCH (:623)
//  OFFLINE: READ_CACHED(15 min). Track authority is safety-of-life: past TTL the
//           hero, the in-force lane and the countdown all drop to the neutral
//           token and the screen reads "authority as of HH:MM · verify with
//           dispatcher". An expired cache never renders as in-force.
//
//  0 stubs in the view layer · 0 mock arrays · 0 placeholders. Every value on
//  screen is decoded from a procedure above or derived from decoded state; the
//  warrant lane is drawn in its honest NOT-WIRED state until the gap is filled.
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI
import Combine

// MARK: - Screen

struct RailConductorTrainOrdersScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConductorTrainOrdersBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decoded server shapes

/// railShipments.getRailShipments row (railShipments.ts:421) — the anchor.
private struct CdrRailShipment: Decodable, Identifiable {
    let id: String
    let railRef: String?
    let origin: String?
    let destination: String?
    let status: String?
    let carrier: String?
    let numberOfCars: Int?
}

/// railShipments.getRoutePlan (railShipments.ts:2882).
private struct CdrRoutePlan: Decodable {
    let shipmentId: Int?
    let routeDescription: String?
    let legs: [CdrRouteLeg]?
    let ptcComplete: Bool?
    let confirmed: Bool?
    let confirmedAt: String?
}

private struct CdrRouteLeg: Decodable, Identifiable {
    var id: String { "\(road ?? "-")|\(from ?? "-")|\(to ?? "-")" }
    let road: String?
    let from: String?
    let to: String?
    let miles: Double?
    let interchangeOut: String?
    let ptcOk: Bool?
}

/// railShipments.getRailCompliance (railShipments.ts:1788).
private struct CdrRailCompliance: Decodable {
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
    let inspections: [CdrInspection]?
}

private struct CdrInspection: Decodable, Identifiable {
    let id: Int
    let inspectionType: String?
    let result: String?
    let inspectionDate: String?
}

/// railShipments.getFRASafetyCompliance (railShipments.ts:2118) → FRASafetyCompliance | null.
private struct CdrFRASafety: Decodable {
    let railroadCode: String?
    let railroadName: String?
    let complianceRate: Double?
    let overallRating: String?
    let totalViolations: Int?
}

// MARK: - Body

private struct RailConductorTrainOrdersBody: View {
    @Environment(\.palette) private var palette

    // Decoded state
    @State private var shipment: CdrRailShipment? = nil
    @State private var plan: CdrRoutePlan? = nil
    @State private var compliance: CdrRailCompliance? = nil
    @State private var fra: CdrFRASafety? = nil

    // Lifecycle
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Real client-side read timestamp — the only source of the cache age. Nil
    /// until a read completes, so the staleness line can never be fabricated.
    @State private var readAt: Date? = nil
    @State private var now = Date()

    /// OFFLINE: READ_CACHED(15 min) — declared in the SVG <desc>.
    private let cacheTTL: TimeInterval = 15 * 60

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: Derived state

    private var legs: [CdrRouteLeg] { plan?.legs ?? [] }

    private var cacheAgeSeconds: TimeInterval? {
        guard let readAt else { return nil }
        return max(0, now.timeIntervalSince(readAt))
    }
    private var cacheExpired: Bool {
        guard let age = cacheAgeSeconds else { return true }
        return age > cacheTTL
    }
    private var cacheAgeLabel: String {
        guard let age = cacheAgeSeconds else { return "no read yet" }
        let m = Int(age / 60)
        return m < 1 ? "under a minute old" : "\(m) min old"
    }
    private var readAtLabel: String {
        guard let readAt else { return "—:—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: readAt)
    }

    /// The authority verdict. There is NO warrant feed (STUB
    /// RAIL-CDR-710-TRACK-WARRANTS), so this NEVER returns an in-force state —
    /// the screen refuses to assert authority it cannot read.
    private var authorityVerdict: (label: String, color: Color) {
        if cacheExpired { return ("AUTHORITY UNVERIFIED · CACHE EXPIRED", Brand.neutral) }
        return ("AUTHORITY UNAVAILABLE · VERIFY WITH DISPATCHER", Brand.warning)
    }

    /// Restriction context that IS real: failed / out-of-service inspections on
    /// file for the caller's company (getRailCompliancerailShipments.ts:1788).
    /// NIL when the compliance read has not resolved or carried no count. An
    /// unknown restriction count is NEVER coerced to zero on a track-authority
    /// screen — "unknown" and "none on file" are different facts.
    private var failedInspections: Int? { compliance?.failedCount }

    /// The denominator behind the failed count, nil for the same reason.
    private var totalInspections: Int? { compliance?.totalInspections }

    /// The compliance read has three states the screen must keep apart:
    ///   · `.reading`     — the read is still in flight; nothing is known yet
    ///   · `.unavailable` — the read errored or returned no inspection count
    ///   · `.reported(n)` — the server actually served a count
    /// Only `.reported(0)` may ever wear the success token.
    private enum RestrictionState {
        case reading
        case unavailable
        case reported(Int)
    }

    private var restrictionState: RestrictionState {
        if loading { return .reading }
        if loadError != nil { return .unavailable }
        guard let failed = failedInspections else { return .unavailable }
        return .reported(failed)
    }

    /// Chip face. The file's chip vocabulary is UNVERIFIED for a state not yet
    /// verified and UNAVAILABLE for a read that returned nothing; neither ever
    /// prints a zero, because a zero would be a fabricated clearance.
    private var restrictionChipText: String {
        switch restrictionState {
        case .reading:     return "RESTRICTIONS UNVERIFIED"
        case .unavailable: return "RESTRICTIONS UNAVAILABLE"
        case .reported(let n):
            return n == 0 ? "0 restrictions" : "\(n) restriction\(n == 1 ? "" : "s")"
        }
    }

    private var restrictionChipColor: Color {
        switch restrictionState {
        case .reading, .unavailable: return Brand.warning
        case .reported(let n):       return n == 0 ? Brand.success : Brand.danger
        }
    }

    private var subline: String {
        if let d = plan?.routeDescription, !d.isEmpty { return d }
        if let s = shipment {
            let ref = s.railRef ?? "Shipment \(s.id)"
            if let o = s.origin, let d = s.destination { return "\(ref) · \(o) → \(d)" }
            return ref
        }
        return "no rail shipment on file"
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                Text(subline).font(EType.caption).foregroundStyle(palette.textSecondary)
                stateChips
                IridescentHairline().accessibilityHidden(true)

                if loading {
                    LifecycleCard { Text("Reading track authority…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text("Authority feed unavailable").font(EType.bodyStrong).foregroundStyle(Brand.danger)
                        Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                        Text("Do not move on this screen — call the dispatcher.")
                            .font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Authority feed unavailable. \(err). Do not move on this screen — call the dispatcher.")
                } else {
                    currentAuthorityHero
                    sectionLabel("AUTHORITY CHART · SHARED MILEPOST AXIS",
                                 trailing: legs.isEmpty ? "no legs on file" : "\(legs.count) leg\(legs.count == 1 ? "" : "s")")
                    authorityChart
                    sectionLabel("AUTHORITY AS OF · READ-CACHED", trailing: "TTL 15 min")
                    cacheStrip
                    if let f = fra { fraNote(f) }
                    triCountryBand
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .onReceive(clock) { now = $0 }
    }

    // MARK: Eyebrow · headline · chips

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                .accessibilityHidden(true)
            Text("RAIL CONDUCTOR · TRACK AUTHORITY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("GCOR 14.1")
                .font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rail conductor, track authority. Rule book GCOR 14.1.")
        .accessibilityAddTraits(.isHeader)
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Track authority").font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // Decorative only — the glyph carries no menu and no receiver.
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
        }
    }

    private var stateChips: some View {
        HStack(spacing: Space.s2) {
            chip(cacheExpired ? "UNVERIFIED" : "UNAVAILABLE", cacheExpired ? Brand.neutral : Brand.warning)
            chip(restrictionChipText, restrictionChipColor)
            chip("cached \(readAtLabel)", cacheExpired ? Brand.danger : Brand.warning)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stateChipsAccessibilityLabel)
    }

    /// One statement instead of three loose tokens. It restates exactly what the
    /// chips render — VoiceOver must never disagree with the screen.
    private var stateChipsAccessibilityLabel: String {
        var bits: [String] = []
        bits.append(cacheExpired
                    ? "Authority unverified, the cached read has expired."
                    : "Authority unavailable.")
        bits.append(restrictionSpoken)
        bits.append(readAt == nil ? "No read yet." : "Cached \(readAtLabel), \(cacheAgeLabel).")
        return bits.joined(separator: " ")
    }

    /// The restriction chip said in words. The three states are spoken as three
    /// different things, so VoiceOver can never hear a clearance the screen is
    /// not rendering — and never hears a zero the server did not send.
    private var restrictionSpoken: String {
        switch restrictionState {
        case .reading:
            return "Restrictions unverified — the compliance read has not returned yet."
        case .unavailable:
            return "Restrictions unavailable — the compliance read returned no inspection count. This is not zero."
        case .reported(let n):
            return n == 0
                ? "0 restrictions reported."
                : "\(n) restriction\(n == 1 ? "" : "s") reported."
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(palette.bgCard)
            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(Capsule())
    }

    private func sectionLabel(_ text: String, trailing: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(text).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(trailing).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text). \(trailing).")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: HERO · the current authority
    //
    // The SVG hero carries warrant number, exact limits, issue time and expiry
    // countdown. Those four values live behind RAIL-CDR-710-TRACK-WARRANTS, so
    // this hero renders the honest not-wired verdict plus the limits the server
    // DOES know by name (getRoutePlan legs) — never a fabricated MP range and
    // never a green in-force band.

    private var currentAuthorityHero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(authorityVerdict.label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(authorityVerdict.color)
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let first = legs.first, let last = legs.last,
                           let from = first.from, let to = last.to {
                            Text("\(from) → \(to)")
                                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("no authorized limits on file")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Brand.neutral)
                        }
                        Text(limitsSubline)
                            .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXPIRES").font(.system(size: 9, weight: .bold)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                        Text("—:—")
                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Brand.neutral)
                        Text("unavailable")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.neutral)
                    }
                    .frame(width: 92, alignment: .leading)
                }
                Text("Track-warrant details are unavailable. Confirm the warrant number, limits, issue time, and expiration with the dispatcher before movement.")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroAccessibilityLabel)
    }

    /// The hero read as one statement. The expiry is announced as unavailable
    /// rather than as the em-dash placeholder, and no in-force state is ever
    /// spoken — the screen has no warrant feed to assert one from.
    private var heroAccessibilityLabel: String {
        var bits: [String] = [
            cacheExpired
                ? "Authority unverified, the cached read has expired."
                : "Authority unavailable. Verify with the dispatcher."
        ]
        if let first = legs.first, let last = legs.last,
           let from = first.from, let to = last.to {
            bits.append("Route plan limits \(from) to \(to).")
        } else {
            bits.append("No authorized limits on file.")
        }
        bits.append("\(limitsSubline).")
        bits.append("Expires: unavailable.")
        bits.append("Track-warrant details are unavailable. Confirm the warrant number, limits, issue time, and expiration with the dispatcher before movement.")
        return bits.joined(separator: " ")
    }

    /// Every fragment here is decoded — road, leg count, PTC verdict, confirmation.
    private var limitsSubline: String {
        var parts: [String] = []
        if let road = legs.first?.road { parts.append(road) }
        if !legs.isEmpty { parts.append("\(legs.count) leg\(legs.count == 1 ? "" : "s")") }
        let mileage = legs.compactMap { $0.miles }.reduce(0, +)
        if mileage > 0 { parts.append("\(mileage.formatted(.number.precision(.fractionLength(0...1)))) mi") }
        if let c = plan?.confirmed { parts.append(c ? "routing confirmed" : "routing unconfirmed") }
        if let p = plan?.ptcComplete { parts.append(p ? "PTC complete" : "PTC incomplete") }
        return parts.isEmpty ? "route plan carries no legs" : parts.joined(separator: " · ")
    }

    // MARK: THE DEVICE · mile-range authority chart
    //
    // One shared axis, every order drawn as a horizontal range bar against it.
    // The domain is the route the server actually reports: when getRoutePlan
    // returns per-leg mileage the axis is mileage-proportional, otherwise the
    // legs divide the axis evenly and the chart says so. The AUTHORITY lane is
    // drawn empty and dashed because no warrant feed exists — the shape of the
    // gap is visible instead of hidden.

    private struct ChartLane: Identifiable {
        let id: Int
        let gutter: String
        let start: Double        // 0…1 of the shared axis
        let end: Double          // 0…1
        let color: Color
        let dashed: Bool
        let onBar: String?
        let caption: String?
    }

    /// Cumulative 0…1 boundaries of each leg on the shared axis.
    private var legBounds: [(lo: Double, hi: Double)] {
        guard !legs.isEmpty else { return [] }
        let miles = legs.map { max($0.miles ?? 0, 0) }
        let total = miles.reduce(0, +)
        if total > 0 {
            var acc = 0.0
            return miles.map { m in
                let lo = acc / total; acc += m
                return (lo, acc / total)
            }
        }
        let step = 1.0 / Double(legs.count)
        return (0..<legs.count).map { (Double($0) * step, Double($0 + 1) * step) }
    }

    private var lanes: [ChartLane] {
        var out: [ChartLane] = []
        // Lane 0 — the authority itself. Always drawn, always empty until wired.
        out.append(ChartLane(id: 0, gutter: "TW —", start: 0, end: 1,
                             color: Brand.neutral, dashed: true, onBar: nil,
                             caption: "no warrant on file"))
        // One lane per decoded route leg, coloured by the server's PTC verdict.
        for (i, leg) in legs.enumerated() {
            let b = legBounds[i]
            let ptc = leg.ptcOk
            let color: Color = ptc == true ? Brand.success : (ptc == false ? Brand.danger : Brand.info)
            let onBar: String? = (b.hi - b.lo) > 0.32 ? [leg.from, leg.to].compactMap { $0 }.joined(separator: " → ") : nil
            var caption = ptc == true ? "PTC qualified" : (ptc == false ? "PTC not qualified" : "PTC unverified")
            if let ic = leg.interchangeOut { caption += " · interchange \(ic)" }
            out.append(ChartLane(id: i + 1, gutter: leg.road ?? "—",
                                 start: b.lo, end: b.hi, color: color, dashed: false,
                                 onBar: onBar, caption: caption))
        }
        return out
    }

    private var authorityChart: some View {
        VStack(alignment: .leading, spacing: 0) {
            if legs.isEmpty {
                // Degraded, exactly as declared in the SVG <desc>.
                VStack(alignment: .leading, spacing: 6) {
                    axisFrame(labels: [])
                    Text("no authority on file — do not move")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.danger)
                    Text("No route legs or track-warrant details are available. Do not use this screen as movement authority; confirm limits with the dispatcher.")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No authority on file — do not move. No route legs or track-warrant details are available. Do not use this screen as movement authority; confirm limits with the dispatcher.")
            } else {
                axisFrame(labels: axisLabels)
                VStack(spacing: 10) {
                    ForEach(lanes) { laneRow($0) }
                }
                .padding(.top, 10)
                Divider().overlay(palette.borderFaint).padding(.vertical, 10)
                    .accessibilityHidden(true)
                conflictNote
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Axis boundary names — real place names from the decoded legs.
    private var axisLabels: [String] {
        guard let first = legs.first else { return [] }
        var out: [String] = [first.from ?? "—"]
        for leg in legs { out.append(leg.to ?? "—") }
        return out
    }

    private func axisFrame(labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ORDER").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 58, alignment: .leading)
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { idx, name in
                        Text(name)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity,
                                   alignment: idx == 0 ? .leading : (idx == labels.count - 1 ? .trailing : .center))
                    }
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 58, height: 1)
                Rectangle().fill(palette.borderFaint).frame(height: 1)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(axisAccessibilityLabel(labels))
    }

    /// The shared axis read as one statement. Boundary names are the decoded
    /// place names only; an empty axis says so rather than reading em-dashes.
    private func axisAccessibilityLabel(_ labels: [String]) -> String {
        if labels.isEmpty { return "Order axis. No milepost boundaries on file." }
        return "Order axis, left to right: " + labels.joined(separator: ", ")
    }

    private func laneRow(_ lane: ChartLane) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(lane.gutter)
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(lane.color)
                    .lineLimit(1)
                    .frame(width: 58, alignment: .leading)
                GeometryReader { geo in
                    let w = geo.size.width
                    let x = w * lane.start
                    let bw = max(6, w * (lane.end - lane.start))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(palette.bgCardSoft)
                            .frame(height: 18)
                        Group {
                            if lane.dashed {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(lane.color.opacity(0.55),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(lane.color.opacity(0.10)))
                            } else {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(lane.color)
                            }
                        }
                        .frame(width: bw, height: 18)
                        .offset(x: x)
                        if let onBar = lane.onBar {
                            Text(onBar)
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(width: bw, height: 18)
                                .offset(x: x)
                        }
                    }
                }
                .frame(height: 18)
            }
            if let caption = lane.caption {
                HStack {
                    Spacer().frame(width: 58)
                    Text(caption)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(lane.color)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(laneAccessibilityLabel(lane))
    }

    /// A lane is a gutter mark, an optional span name and a verdict caption laid
    /// out across a chart. VoiceOver reads it as one sentence.
    private func laneAccessibilityLabel(_ lane: ChartLane) -> String {
        var bits: [String] = [lane.gutter]
        if let onBar = lane.onBar { bits.append(onBar) }
        if let caption = lane.caption { bits.append(caption) }
        return bits.joined(separator: ". ") + "."
    }

    /// The SVG's overlap note. Here it carries the only restriction fact the
    /// server actually serves: failed / out-of-service inspections on file.
    private var conflictNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(conflictDotColor).frame(width: 8, height: 8).padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(conflictHeadline)
                    .font(.system(size: 10.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text(conflictDetail)
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conflictHeadline). \(conflictDetail)")
    }

    /// The success token is reserved for a zero the server actually reported.
    /// A count that has not arrived, or that the read could not return, carries
    /// the warning token — never the green one.
    private var conflictDotColor: Color {
        switch restrictionState {
        case .reading, .unavailable: return Brand.warning
        case .reported(let n):       return n > 0 ? Brand.danger : Brand.success
        }
    }

    private var conflictHeadline: String {
        switch restrictionState {
        case .reading:         return "Inspection record unverified"
        case .unavailable:     return "Inspection record unavailable"
        case .reported(let n): return n > 0 ? "Restrictions on file for this company" : "No failed inspections on file"
        }
    }

    private var conflictDetail: String {
        let tail = " — track-warrant details are unavailable, so these inspections cannot be matched to authorized limits. Confirm restrictions with the dispatcher."
        switch restrictionState {
        case .reading:
            return "The compliance read has not returned yet, so the number of failed inspections on file is not yet known" + tail
        case .unavailable:
            return "The compliance read returned no inspection count, so the number of failed inspections on file is unknown — it is not zero" + tail
        case .reported(let n):
            let status = compliance?.status ?? "unknown"
            let counted: String
            if let total = totalInspections {
                counted = "\(n) of \(total) inspections failed"
            } else {
                counted = "\(n) inspection\(n == 1 ? "" : "s") failed · total not reported"
            }
            return counted + " · compliance \(status)" + tail
        }
    }

    // MARK: OFFLINE · READ_CACHED(15 min)

    private var cacheStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(cacheExpired ? "CACHE EXPIRED · NOT AUTHORITY" : "CACHED AUTHORITY · NOT A LIVE READ")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(cacheExpired ? Brand.danger : Brand.warning)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(readAtLabel)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text("· \(cacheAgeLabel)")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text("VERIFY DS")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(cacheExpired ? Brand.danger : Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill((cacheExpired ? Brand.danger : Brand.warning).opacity(0.14)))
            }
            Text("An expired cache is not authority. Verify with the dispatcher before you enter or foul the limits.")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder((cacheExpired ? Brand.danger : Brand.warning).opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cacheStripAccessibilityLabel)
    }

    /// The read-cached strip as one statement. "VERIFY DS" is a status token on
    /// the strip, not a control — it is spoken as part of the sentence, never
    /// announced as a button, because nothing backs a dispatcher call.
    private var cacheStripAccessibilityLabel: String {
        var bits: [String] = [
            cacheExpired ? "Cache expired — not authority." : "Cached authority — not a live read."
        ]
        bits.append(readAt == nil
                    ? "No read yet."
                    : "Read at \(readAtLabel), \(cacheAgeLabel).")
        bits.append("Verify with the dispatcher.")
        bits.append("An expired cache is not authority. Verify with the dispatcher before you enter or foul the limits.")
        return bits.joined(separator: " ")
    }

    /// Enterprise FRA feed — honestly hidden when the procedure returns null.
    private func fraNote(_ f: CdrFRASafety) -> some View {
        LifecycleCard {
            HStack {
                Text("OPERATING ROAD · FRA")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                if let r = f.overallRating {
                    Text(r).font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(r.uppercased() == "SATISFACTORY" ? Brand.success : Brand.warning)
                }
            }
            Text([f.railroadName, f.railroadCode].compactMap { $0 }.joined(separator: " · "))
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(fraDetail(f)).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fraAccessibilityLabel(f))
    }

    /// Reads the FRA note as one statement. Only fields the feed carried are
    /// named; an absent rating is simply not spoken, never rendered as a pass.
    private func fraAccessibilityLabel(_ f: CdrFRASafety) -> String {
        var bits: [String] = ["Operating road, FRA."]
        let road = [f.railroadName, f.railroadCode].compactMap { $0 }.joined(separator: " · ")
        if !road.isEmpty { bits.append("\(road).") }
        if let r = f.overallRating { bits.append("Overall rating \(r).") }
        bits.append("\(fraDetail(f)).")
        return bits.joined(separator: " ")
    }

    private func fraDetail(_ f: CdrFRASafety) -> String {
        var parts: [String] = []
        if let c = f.complianceRate { parts.append("compliance \(c.formatted(.number.precision(.fractionLength(0...1))))%") }
        if let v = f.totalViolations { parts.append("\(v) violations") }
        return parts.isEmpty ? "feed carried no rated fields" : parts.joined(separator: " · ")
    }

    // MARK: Tri-country band · the authority instrument varies

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            countryTile("US · GCOR", "TWC · Rule 14", active: true)
            countryTile("CA · CROR", "OCS · Rule 564", active: false)
            countryTile("MX · ARTF", "SICT · km", active: false)
        }
    }

    private func countryTile(_ top: String, _ bottom: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Brand.info : palette.textSecondary)
            Text(bottom).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Brand.info : palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(top), \(bottom)\(active ? ", active regime" : "")")
    }

    // MARK: CTA pair

    /// Both controls are real Buttons held disabled, not styled text wrapped in
    /// `.allowsHitTesting(false)`. Neither receiver exists:
    ///   · "Repeat back" → trackAuthority.repeatBack is a named gap
    ///     (RAIL-CDR-710-WARRANT-REPEAT-BACK); nothing can record a repeat-back.
    ///   · "Call DS"     → no procedure on this screen serves a dispatcher
    ///     contact, so there is no number to dial. It is NOT invented.
    /// Both carry the same 0.45 disabled treatment, and each states its own
    /// reason to VoiceOver so a disabled control is never silently inert.
    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                Button {} label: {
                    Text("Repeat back")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(LinearGradient.primary.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityLabel("Repeat back")
                .accessibilityValue("Unavailable — repeat-back recording is not served.")
                .accessibilityHint("Confirm the authority directly with the dispatcher.")

                Button {} label: {
                    Text("Call DS")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 132).frame(height: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .opacity(0.45)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityLabel("Call DS")
                .accessibilityValue("Unavailable — no dispatcher contact is served to this screen.")
            }
            Text("Repeat-back recording is unavailable. Confirm the authority directly with the dispatcher.")
                .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Data

    private struct RoutePlanInput: Encodable { let shipmentId: Int }
    private struct FRAInput: Encodable { let railroadCode: String }

    private func load() async {
        loading = true; loadError = nil
        do {
            // 1. Anchor on the conductor's own rail shipment (railShipments.ts:290).
            let ships: [CdrRailShipment] = try await EusoTripAPI.shared.queryNoInput("railShipments.getRailShipments")
            self.shipment = ships.first

            // 2. Operating limits by name (railShipments.ts:2621). No shipment → no call.
            if let idStr = ships.first?.id, let sid = Int(idStr) {
                self.plan = try await EusoTripAPI.shared.query("railShipments.getRoutePlan",
                                                               input: RoutePlanInput(shipmentId: sid))
            } else {
                self.plan = nil
            }

            // 3. Restriction / inspection context (railShipments.ts:1527).
            self.compliance = try await EusoTripAPI.shared.queryNoInput("railShipments.getRailCompliance")

            self.readAt = Date()
            self.now = Date()
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false

        // 4. Enterprise FRA rating for the operating road. Soft-fail: a dark feed
        //    must never break the authority screen, and it stays hidden.
        await loadFRA()
    }

    private func loadFRA() async {
        guard let road = plan?.legs?.first?.road, !road.isEmpty else { self.fra = nil; return }
        self.fra = try? await EusoTripAPI.shared.query("railShipments.getFRASafetyCompliance",
                                                       input: FRAInput(railroadCode: road))
    }
}

#Preview("710 · Conductor Track Authority · Night") {
    RailConductorTrainOrdersScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("710 · Conductor Track Authority · Light") {
    RailConductorTrainOrdersScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
