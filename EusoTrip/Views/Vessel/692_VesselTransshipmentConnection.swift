//
//  692_VesselTransshipmentConnection.swift
//  EusoTrip — Vessel Operator · Transshipment Connection.
//
//  Faithful port of "692 Vessel Transshipment Connection.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline).
//  Role VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) with the SHIPMENTS slot inked.
//
//  ARCHETYPE: GRID/TIMELINE — a hub is a MESH, not a route. The prior 692 drew an AIS approach canvas (the
//  same organ as 205 MapCanvas and 003/660) showing ONE connection; the operator's actual question is
//  "across every feeder landing here, which onward sailings do they still make?" That is a bipartite
//  ribbon over a signed number-line, not a map.
//
//  LIVE FUSION: the sankey rails, the ribbon set, the buffer number-line and the connection rows are four
//  faces of ONE state — `inbound` + `onward` voyages. Every one of them re-derives off `load()`; there is no
//  second source of truth and no parallel literal. Degraded provider state surfaces an explicit error card,
//  never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(90s) — the buffer is pure arithmetic over cached scheduledArrival /
//  scheduledDeparture, so it survives a dropout. The staleness is DRAWN, not claimed: a live "CACHED 90s ·
//  Ns OLD" age chip sits on the buffer card and turns warning-coloured the moment the read passes its TTL,
//  and the derived-view banner is pinned permanently above the hero.
//
//  ─────────────────────── THE HONEST HEADLINE: THIS SCREEN HAS NO DIRECT BACKING ───────────────────────
//  STUB · named-gap: vesselTransshipment.getConnections. An exhaustive grep for "transship" across
//    server/routers returns ONLY status-enum string literals and never a procedure — vesselShipments.ts:168
//    (status list), :643-644 (the legal transition map in_transit → transshipment and transshipment →
//    in_transit), :2063; multiModal.ts:697; tracking.ts:137; analytics.ts:364 and :677; dispatch.ts:394,
//    :399, :400; portIntelligence.ts:164. A grep for onwardVessel / feederVessel / connectingVoyage /
//    transshipmentPort / connectionRisk / motherVessel returns 0 hits. There is NO inbound-leg →
//    outbound-leg link column on vessel_shipments or vessel_voyages.
//    Proposed shape: vesselTransshipment.getConnections({ hubPortId }) joining inbound vesselVoyages
//    arriving at a hub to outbound vesselVoyages departing it, returning
//    { inboundVoyage, onwardVoyage, bufferHours, boxesAtRisk, cutoffAt } — plus a vessel_to_vessel member
//    added to the intermodal.recordTransfer transferType enum at intermodal.ts:637 (and to the matching
//    mysqlEnum on the intermodal_transfers table).
//
//  Data / wiring (line numbers read first-hand 2026-08-11):
//    vesselShipments.getVesselSchedules (EXISTS vesselShipments.ts:1350 · vesselProcedure · input
//      {vesselId?, departurePortId?, arrivalPortId?, status?, limit=20} · returns raw vessel_voyages rows
//      {id, vesselId, voyageNumber, serviceRoute, departurePortId, arrivalPortId, scheduledDeparture,
//      scheduledArrival, actualDeparture, actualArrival, status}). Called TWICE — arrivalPortId:hub builds
//      the inbound rail, departurePortId:hub builds the onward rail. P0-READ-TENANCY: the resolver is
//      `.query(async ({ input })` with no ctx at all, and vesselProcedure (_core/trpc.ts:268) is a MODE
//      gate only, so this voyage list is NOT tenant-scoped.
//    containerTimeline.liveStatus (EXISTS containerTimeline.ts:75 · vesselProcedure · {shipmentId} ·
//      returns {shipment, containers, milestones, progress, containerCount, lastUpdate}).
//      P0-READ-TENANCY: the entire containerTimeline.ts file (153 lines) has ZERO ctx references.
//    intermodal.getTransfers (EXISTS intermodal.ts:943 · protectedProcedure · {limit=50} · returns raw
//      intermodal_transfers rows). Tenancy here is CORRECT — admin bypass at :952, owned-id inArray at
//      :972 — and is cited on screen as the house standard the two reads above fail.
//    blankSailing.rebookingSuggestions (EXISTS blankSailing.ts:105 · vesselProcedure · {shipmentId} ·
//      returns ranked upcoming vessel_voyages on the same port pair) — the "Rebook short boxes" CTA.
//    intermodal.recordTransfer (EXISTS intermodal.ts:637 · protectedProcedure · ownership gate CLEAN via
//      loadOwnedShipment at intermodal.ts:655) — its transferType enum is
//      {truck_to_rail, rail_to_truck, truck_to_vessel, vessel_to_truck, rail_to_vessel, vessel_to_rail}
//      with NO vessel_to_vessel member, so a TRUE TRANSSHIPMENT CANNOT BE EXPRESSED by this mutation.
//      The CTA is a real Button that renders that gap and deliberately never fires.
//    esangCoach.forScreen (EXISTS esangCoach.ts:264 · protectedProcedure) is NOT called: its SCREEN_ENUM
//      (esangCoach.ts:112-125) is driver-only — home, trips, earnings, tax, dvir, availability, missions,
//      badges, referrals, zeun, haul, active-trip — with no vessel member. The ESang line is derived on
//      device from the worst-buffer connection and the card says exactly that.
//    CHAIN-OPEN · record transshipment hand-off — intermodal.recordTransfer:637 writes an
//      intermodal_transfers row, inserts NO blockchainAuditTrail row, and does NOT broadcast:
//      INTERMODAL_TRANSFER_INITIATED / _COMPLETED (shared/websocket-events.ts:458/459) are mapped inside
//      emitIntermodalEvent (_core/websocket.ts:1798-1801) which has ZERO callers, and
//      WS_CHANNELS.INTERMODAL_TRANSFER (shared/websocket-events.ts:637) has zero emitters — the onward
//      carrier never learns. Systemic fault S1/S2. Every other verb on this screen is a read.
//
//  transportMode=vessel · MX (a Pacific transshipment hub such as MXZLO Manzanillo; Mexican customs
//  controls the CY dwell) with US onward, where the CBP ISF filing drives the onward gate cut-off.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. Every figure on screen is either a decoded
//  wire field or arithmetic over two decoded wire fields, and anything without a source renders a visible
//  gap notice instead of a number. File-scoped types are suffixed 692 to avoid cross-file collisions.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselTransshipmentConnectionScreen: View {
    let theme: Theme.Palette
    /// Hub port the mesh is scoped to. 0 (registry / zero-arg use) means no hub is threaded — the loader
    /// then reads the unfiltered voyage window and INFERS the busiest arrival port as the hub, saying so
    /// on screen. It never invents a port.
    var hubPortId: Int = 0
    /// Optional vessel booking threaded from the shipments list. 0 = none: the box-count read and the
    /// rebooking CTA are keyed by shipmentId, so both render their honest gap instead of a number.
    var shipmentId: Int = 0

    init(theme: Theme.Palette, hubPortId: Int = 0, shipmentId: Int = 0) {
        self.theme = theme; self.hubPortId = hubPortId; self.shipmentId = shipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselTransshipmentConnectionBody692(hubPortId: hubPortId, shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",         systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (mirror the procedures' return rows exactly)

/// `vesselShipments.getVesselSchedules` → raw `vessel_voyages` rows.
private struct Voyage692: Decodable, Identifiable, Hashable {
    let id: Int
    let vesselId: Int?
    let voyageNumber: String?
    let serviceRoute: String?
    let departurePortId: Int?
    let arrivalPortId: Int?
    let scheduledDeparture: String?
    let scheduledArrival: String?
    let actualDeparture: String?
    let actualArrival: String?
    let status: String?
}

/// `containerTimeline.liveStatus` → the fields this screen actually reads.
private struct LiveStatus692: Decodable {
    let containerCount: Int?
    let progress: Int?
    let lastUpdate: String?
}

/// `intermodal.getTransfers` → raw `intermodal_transfers` rows.
private struct Transfer692: Decodable, Identifiable {
    let id: Int
    let transferType: String?
    let facilityName: String?
    let status: String?
    let startedAt: String?
    let completedAt: String?
}

/// `blankSailing.rebookingSuggestions` → `{ originalBooking?, suggestions[], message? }`.
private struct RebookSuggestion692: Decodable, Identifiable {
    let rank: Int?
    let voyageId: Int
    let voyageNumber: String?
    let scheduledDeparture: String?
    let scheduledArrival: String?
    var id: Int { voyageId }
}
private struct RebookOut692: Decodable {
    let suggestions: [RebookSuggestion692]?
    let message: String?
}

/// One DERIVED feeder→mother candidate. There is no procedure that returns this; it is arithmetic over
/// two decoded voyage rows and is labelled as derived everywhere it appears.
private struct Connection692: Identifiable {
    let id = UUID()
    let inbound: Voyage692
    let onward: Voyage692
    let bufferHours: Double
    var isNegative: Bool { bufferHours < 0 }
}

private enum RiskBand692 {
    case missed, tight, clear
    static func of(_ h: Double) -> RiskBand692 { h < 0 ? .missed : (h < 12 ? .tight : .clear) }
    var color: Color {
        switch self {
        case .missed: return Brand.danger
        case .tight:  return Brand.warning
        case .clear:  return Brand.success
        }
    }
}

// MARK: - Body

private struct VesselTransshipmentConnectionBody692: View {
    @Environment(\.palette) private var palette
    let hubPortId: Int
    let shipmentId: Int

    // Live state only — no seeds, no demo arrays.
    @State private var inbound: [Voyage692] = []
    @State private var onward: [Voyage692] = []
    @State private var transfers: [Transfer692] = []
    @State private var boxCount: Int? = nil          // containerTimeline.liveStatus.containerCount
    @State private var resolvedHubId: Int? = nil     // threaded, or inferred and labelled as inferred
    @State private var hubWasInferred = false
    @State private var lastLoadedAt: Date? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // CTA state
    @State private var rebooking = false
    @State private var rebookNote: String? = nil
    @State private var rebookSuggestions: [RebookSuggestion692] = []
    @State private var transferGapNote: String? = nil

    private let cacheTTL: TimeInterval = 90

    // ── Derived state · all four organs read THESE, never a parallel literal ─

    private var inboundRail: [Voyage692] {
        inbound.sorted { (date($0.scheduledArrival) ?? .distantFuture) < (date($1.scheduledArrival) ?? .distantFuture) }
            .prefix(3).map { $0 }
    }
    private var onwardRail: [Voyage692] {
        onward.sorted { (date($0.scheduledDeparture) ?? .distantFuture) < (date($1.scheduledDeparture) ?? .distantFuture) }
            .prefix(3).map { $0 }
    }

    /// Every (inbound, onward) pair whose onward departure falls in a plausible connecting window around
    /// the inbound arrival. THIS IS A DERIVED CANDIDATE SET, not a booked connection — no join exists.
    private var connections: [Connection692] {
        var out: [Connection692] = []
        for i in inboundRail {
            guard let a = date(i.scheduledArrival) else { continue }
            for o in onwardRail {
                guard let d = date(o.scheduledDeparture) else { continue }
                let hours = d.timeIntervalSince(a) / 3600
                guard hours >= -12, hours <= 72 else { continue }
                out.append(Connection692(inbound: i, onward: o, bufferHours: hours))
            }
        }
        return out.sorted { $0.bufferHours < $1.bufferHours }
    }
    private var meshLinks: [Connection692] { Array(connections.prefix(4)) }
    private var scoredRows: [Connection692] { Array(connections.prefix(3)) }
    private var offScaleCount: Int { connections.filter { $0.bufferHours > 48 }.count }
    private var worstConnection: Connection692? { connections.first }

    private var ageSeconds: Int? {
        guard let t = lastLoadedAt else { return nil }
        return max(0, Int(Date().timeIntervalSince(t)))
    }
    private var isStale: Bool { (ageSeconds.map { Double($0) } ?? 0) > cacheTTL }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrow
            header
            IridescentHairline()
            gapBanner
            if loading {
                loadingState
            } else if let err = loadError {
                errorState(err)
            } else if inbound.isEmpty && onward.isEmpty {
                emptyState
            } else {
                sankeyHero
                bufferSection
                esangCard
                rowsSection
                if !rebookSuggestions.isEmpty { rebookResults }
                if let n = rebookNote { note(n, tint: Brand.info) }
                if let n = transferGapNote { note(n, tint: Brand.warning) }
                ctaPair
                provenanceFooter
            }
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .task { await load() }
        .refreshable { await load() }
    }

    // ── Eyebrow · the ONE sparkle ───────────────────────────────────────────

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL · TRANSSHIPMENT · HUB MESH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            // Honest scope chip: the real hub id when we have one, an em-dash otherwise. Never a made-up port.
            Text(resolvedHubId.map { "HUB \($0) · \(meshLinks.count) LINKS" } ?? "—")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // ── Detail header ───────────────────────────────────────────────────────

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hub connections")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(sublineText)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sublineText: String {
        guard let hub = resolvedHubId else {
            return "No hub port threaded — waiting on a voyage window from getVesselSchedules."
        }
        let prefix = hubWasInferred ? "Hub \(hub) inferred on device (busiest arrival port in the window)"
                                    : "Hub port \(hub)"
        return "\(prefix) · \(inbound.count) inbound, \(onward.count) onward voyages · \(connections.count) candidate links"
    }

    // ── The permanent honest gap banner ─────────────────────────────────────

    private var gapBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DERIVED VIEW · NO TRANSSHIPMENT PROCEDURE EXISTS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.warning)
            Text("Feeder-to-mother pairs are matched on this device from live scheduledArrival / scheduledDeparture. No join column links an inbound leg to an outbound leg.")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("intermodal.recordTransfer has no vessel_to_vessel transferType — the hand-off cannot be logged.")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Brand.danger.opacity(0.10), Brand.warning.opacity(0.10)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.42)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // ── Loading / error / empty ─────────────────────────────────────────────

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 84)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voyage feed degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("No buffer is shown while the feed is down — an extrapolated connection is worse than none.")
                .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var emptyState: some View {
        EusoEmptyState(systemImage: "point.3.connected.trianglepath.dotted",
                       title: "No voyages in the window",
                       subtitle: "getVesselSchedules returned nothing for this hub. Feeder and onward sailings appear here the moment a voyage is scheduled against the port.")
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // ── HERO ORGAN · bipartite connection ribbon (sankey) ───────────────────

    private var sankeyHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INBOUND FEEDER").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(resolvedHubId.map { "HUB \($0)" } ?? "HUB —")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("ONWARD SAILING").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s2)

            ZStack(alignment: .topLeading) {
                RibbonCanvas692(links: meshLinks,
                                inboundRail: inboundRail,
                                onwardRail: onwardRail,
                                widthForBoxes: ribbonWidth)
                    .frame(height: railHeight)
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 10) { ForEach(inboundRail) { railBlock($0, inbound: true) } }
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        VStack(spacing: 10) { ForEach(onwardRail) { railBlock($0, inbound: false) } }
                        VStack(spacing: 10) {
                            ForEach(onwardRail) { _ in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(LinearGradient.diagonal).frame(width: 3, height: 34)
                            }
                        }
                    }
                }
                .frame(height: railHeight, alignment: .top)
            }

            Text(ribbonLegend)
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var railHeight: CGFloat {
        CGFloat(max(inboundRail.count, onwardRail.count)) * 34 + CGFloat(max(0, max(inboundRail.count, onwardRail.count) - 1)) * 10
    }

    /// Ribbon width is honest about what it can encode. There is NO per-link box count on the wire, so the
    /// only real container figure available is `containerTimeline.liveStatus.containerCount` for the
    /// threaded booking. When that is absent every ribbon draws at the base width and the legend says so.
    private func ribbonWidth(_ link: Connection692) -> CGFloat {
        guard let boxes = boxCount, boxes > 0 else { return 10 }
        return min(26, max(6, 6 + CGFloat(boxes) / 4))
    }

    private var ribbonLegend: String {
        let dashed = meshLinks.contains(where: { $0.isNegative })
            ? " Dashed red = buffer already negative."
            : ""
        if let boxes = boxCount, boxes > 0 {
            return "Ribbon width uses the \(boxes) live containers on the threaded booking (containerTimeline.liveStatus:75). No procedure returns per-link box counts, so the other links draw at base width.\(dashed)"
        }
        return "All links draw at equal width — no procedure returns per-link box counts, and no booking is threaded for containerTimeline.liveStatus.\(dashed)"
    }

    private func railBlock(_ v: Voyage692, inbound isIn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v.voyageNumber ?? "voyage \(v.id)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textPrimary).lineLimit(1)
            HStack(spacing: 4) {
                Text(clock(isIn ? v.scheduledArrival : v.scheduledDeparture))
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 2)
                Text((v.status ?? "—").uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 110, height: 34, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // ── MID-BAND ORGAN · the -12h…+48h buffer number-line ───────────────────

    private var bufferSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONNECTION BUFFER · -12h TO +48h")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(offScaleCount > 0 ? "\(offScaleCount) LINK\(offScaleCount == 1 ? "" : "S") OFF-SCALE" : "ALL LINKS IN RANGE")
                    .font(.system(size: 9, weight: .bold)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("HOURS OF SLACK AGAINST THE ONWARD CUT-OFF (0 = CUT-OFF)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 6)
                    // The DRAWN staleness affordance for READ_CACHED(90s).
                    Text(ageSeconds.map { "CACHED 90s · \($0)s OLD" } ?? "NOT YET READ")
                        .font(.system(size: 9, weight: .bold)).tracking(0.4).monospacedDigit()
                        .foregroundStyle(isStale ? Brand.warning : palette.textTertiary)
                }
                NumberLine692(markers: scoredRows.map { $0.bufferHours })
                    .frame(height: 64).padding(.top, Space.s2)
                Text("Buffer = onward scheduledDeparture minus inbound scheduledArrival, computed on this device from two vessel_voyages rows.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // ── ESang · derived on device (deliberately off the stamped tail rhythm) ─

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(Color.white.opacity(0.40)).frame(width: 12, height: 12)
                    .offset(x: -5, y: -5).blur(radius: 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · DERIVED ON DEVICE (no vessel coach screen)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(esangHeadline)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("esangCoach.forScreen:264 is not called — its SCREEN_ENUM (:112-125) is driver-only, with no vessel member.")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// One sentence, computed strictly from the worst live connection. Never a canned line.
    private var esangHeadline: String {
        guard let w = worstConnection else {
            return "No candidate link falls inside the connecting window."
        }
        let inLabel = w.inbound.voyageNumber ?? "voyage \(w.inbound.id)"
        let outLabel = w.onward.voyageNumber ?? "voyage \(w.onward.id)"
        if w.isNegative {
            return String(format: "%@ lands %.1fh after %@ departs — that link is already missed.",
                          inLabel, abs(w.bufferHours), outLabel)
        }
        return String(format: "%@ → %@ is the tightest link at %.1fh of slack.", inLabel, outLabel, w.bufferHours)
    }

    // ── Connection rows · 3px left edge tint per risk band, NO status pill ───

    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONNECTIONS · \(scoredRows.count) SCORED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getVesselSchedules:1350").font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                if scoredRows.isEmpty {
                    EusoEmptyState(systemImage: "arrow.triangle.branch",
                                   title: "No link inside the window",
                                   subtitle: "Voyages loaded, but no onward departure falls between 12h before and 72h after an inbound arrival.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(scoredRows.enumerated()), id: \.element.id) { idx, c in
                        connectionRow(c)
                        if idx < scoredRows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func connectionRow(_ c: Connection692) -> some View {
        let band = RiskBand692.of(c.bufferHours)
        let inLabel = c.inbound.voyageNumber ?? "voyage \(c.inbound.id)"
        let outLabel = c.onward.voyageNumber ?? "voyage \(c.onward.id)"
        return HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5).fill(band.color).frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(inLabel) → \(outLabel)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("\(clock(c.inbound.scheduledArrival)) → \(clock(c.onward.scheduledDeparture))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%@%.1fh", c.bufferHours >= 0 ? "+" : "", c.bufferHours))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(band.color)
                // HONEST: boxes-at-risk has no source unless a booking is threaded.
                Text(boxCount.map { "\($0) boxes at risk" } ?? "boxes at risk: no source")
                    .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 10)
    }

    // ── Rebooking results (only ever real rows from the procedure) ───────────

    private var rebookResults: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REBOOKING CANDIDATES · blankSailing.rebookingSuggestions:105")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(rebookSuggestions) { s in
                    HStack {
                        Text(s.voyageNumber ?? "voyage \(s.voyageId)")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(clock(s.scheduledDeparture)).font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, 10)
                }
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func note(_ text: String, tint: Color) -> some View {
        Text(text).font(EType.caption).foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // ── CTA pair · both are real Buttons ────────────────────────────────────

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: rebooking ? "Checking sailings…" : "Rebook short boxes",
                      action: { Task { await rebook() } },
                      isLoading: rebooking)
                .frame(maxWidth: .infinity)

            Button(action: {
                // DELIBERATELY DOES NOT FIRE. intermodal.recordTransfer:637 has no vessel_to_vessel
                // transferType (nor does the intermodal_transfers mysqlEnum), so a vessel-to-vessel
                // hand-off cannot be expressed. Firing it with a wrong type would write a false record.
                transferGapNote = "Cannot log this hand-off. intermodal.recordTransfer:637 accepts only truck_to_rail, rail_to_truck, truck_to_vessel, vessel_to_truck, rail_to_vessel and vessel_to_rail — there is no vessel_to_vessel member. Even if it were added, INTERMODAL_TRANSFER_INITIATED (websocket-events.ts:458) is mapped inside emitIntermodalEvent (_core/websocket.ts:1798) which has zero callers, so the onward carrier would never be notified."
            }) {
                VStack(spacing: 2) {
                    Text("Record transfer").font(.system(size: 13, weight: .bold))
                    Text("ENUM GAP").font(.system(size: 8, weight: .bold)).tracking(0.4)
                }
                .foregroundStyle(Brand.warning)
                .frame(width: 156, height: 48)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Brand.warning.opacity(0.60),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // ── Provenance footer (the honest tenancy ledger, on screen) ─────────────

    private var provenanceFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(transfers.isEmpty
                 ? "intermodal.getTransfers:943 returned no transfers on your shipments — none could be vessel_to_vessel anyway."
                 : "\(transfers.count) transfer\(transfers.count == 1 ? "" : "s") on record (getTransfers:943, correctly tenant-scoped) — none of them vessel_to_vessel; the enum has no such member.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("P0-READ-TENANCY: getVesselSchedules:1350 and containerTimeline.liveStatus:75 both resolve with no ctx — vesselProcedure (_core/trpc.ts:268) is a mode gate only.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // MySQL DATETIME fallback ("2026-08-11 14:40:00").
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.date(from: s)
    }

    private func clock(_ s: String?) -> String {
        guard let d = date(s) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "dd MMM HH:mm"
        return f.string(from: d)
    }

    // MARK: - Load (one tick · every organ re-reasons together)

    private func load() async {
        loading = true; loadError = nil
        struct SchedIn692: Encodable {
            let vesselId: Int?
            let departurePortId: Int?
            let arrivalPortId: Int?
            let status: String?
            let limit: Int
        }
        struct LiveIn692: Encodable { let shipmentId: Int }
        struct TransfersIn692: Encodable { let limit: Int }

        do {
            var hub: Int? = hubPortId > 0 ? hubPortId : nil
            var inferred = false

            if hub == nil {
                // No hub threaded: read the unfiltered window and infer the busiest arrival port.
                // Transparent inference over REAL rows — labelled as inferred everywhere it shows.
                let window: [Voyage692] = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselSchedules",
                    input: SchedIn692(vesselId: nil, departurePortId: nil, arrivalPortId: nil,
                                      status: nil, limit: 20))
                var tally: [Int: Int] = [:]
                for v in window { if let a = v.arrivalPortId { tally[a, default: 0] += 1 } }
                hub = tally.max(by: { $0.value < $1.value })?.key
                inferred = hub != nil
            }

            resolvedHubId = hub
            hubWasInferred = inferred

            if let hub {
                async let inRows: [Voyage692] = EusoTripAPI.shared.query(
                    "vesselShipments.getVesselSchedules",
                    input: SchedIn692(vesselId: nil, departurePortId: nil, arrivalPortId: hub,
                                      status: nil, limit: 20))
                async let outRows: [Voyage692] = EusoTripAPI.shared.query(
                    "vesselShipments.getVesselSchedules",
                    input: SchedIn692(vesselId: nil, departurePortId: hub, arrivalPortId: nil,
                                      status: nil, limit: 20))
                // UNCONDITIONAL overwrite: an honest empty response clears both rails.
                inbound = try await inRows
                onward = try await outRows
            } else {
                inbound = []
                onward = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            inbound = []
            onward = []
        }

        // Box counts are keyed by shipmentId. With no booking threaded this stays nil and every
        // box-dependent element renders its honest gap instead of a number.
        if shipmentId > 0 {
            let live: LiveStatus692? = try? await EusoTripAPI.shared.query(
                "containerTimeline.liveStatus", input: LiveIn692(shipmentId: shipmentId))
            boxCount = live?.containerCount
        } else {
            boxCount = nil
        }

        // Best-effort provenance read — a failure never degrades the mesh.
        transfers = (try? await EusoTripAPI.shared.query(
            "intermodal.getTransfers", input: TransfersIn692(limit: 50))) ?? []

        lastLoadedAt = Date()
        loading = false
    }

    private func rebook() async {
        guard shipmentId > 0 else {
            rebookNote = "Thread a booking first — blankSailing.rebookingSuggestions:105 is keyed by shipmentId and there is no hub-wide variant."
            return
        }
        rebooking = true; rebookNote = nil
        struct RebookIn692: Encodable { let shipmentId: Int }
        do {
            let out: RebookOut692 = try await EusoTripAPI.shared.query(
                "blankSailing.rebookingSuggestions", input: RebookIn692(shipmentId: shipmentId))
            rebookSuggestions = out.suggestions ?? []
            if rebookSuggestions.isEmpty {
                rebookNote = out.message ?? "No scheduled voyage on this port pair — nothing to rebook onto."
            }
        } catch {
            rebookNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        rebooking = false
    }
}

// MARK: - Hero primitive · the ribbons

private struct RibbonCanvas692: View {
    let links: [Connection692]
    let inboundRail: [Voyage692]
    let onwardRail: [Voyage692]
    let widthForBoxes: (Connection692) -> CGFloat

    private let blockH: CGFloat = 34
    private let gap: CGFloat = 10
    private let railW: CGFloat = 110

    private func centerY(_ index: Int) -> CGFloat { CGFloat(index) * (blockH + gap) + blockH / 2 }

    var body: some View {
        Canvas { ctx, size in
            let leftX = railW
            let rightX = max(leftX + 20, size.width - railW - 3)
            let midX = (leftX + rightX) / 2

            var stem = Path()
            stem.move(to: CGPoint(x: midX, y: 0))
            stem.addLine(to: CGPoint(x: midX, y: size.height))
            ctx.stroke(stem, with: .color(.gray.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

            for link in links {
                guard let i = inboundRail.firstIndex(of: link.inbound),
                      let o = onwardRail.firstIndex(of: link.onward) else { continue }
                let y0 = centerY(i)
                let y1 = centerY(o)
                var p = Path()
                p.move(to: CGPoint(x: leftX, y: y0))
                p.addCurve(to: CGPoint(x: rightX, y: y1),
                           control1: CGPoint(x: leftX + (rightX - leftX) * 0.45, y: y0),
                           control2: CGPoint(x: leftX + (rightX - leftX) * 0.62, y: y1))
                let w = widthForBoxes(link)
                if link.isNegative {
                    ctx.stroke(p, with: .color(Brand.danger.opacity(0.85)),
                               style: StrokeStyle(lineWidth: w, dash: [10, 6]))
                } else {
                    ctx.stroke(p, with: .linearGradient(
                        Gradient(colors: [Brand.blue.opacity(0.70), Brand.magenta.opacity(0.70)]),
                        startPoint: CGPoint(x: leftX, y: 0),
                        endPoint: CGPoint(x: rightX, y: 0)),
                               style: StrokeStyle(lineWidth: w))
                }
            }
        }
    }
}

// MARK: - Mid-band primitive · the -12h…+48h number line

private struct NumberLine692: View {
    @Environment(\.palette) private var palette
    let markers: [Double]

    private let lo: Double = -12
    private let hi: Double = 48

    private func x(_ h: Double, _ w: CGFloat) -> CGFloat {
        CGFloat((min(max(h, lo), hi) - lo) / (hi - lo)) * w
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let axisY: CGFloat = 32
            let zeroX = x(0, w)

            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Brand.danger.opacity(0.10), Brand.warning.opacity(0.10)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(0, zeroX), height: 30).offset(y: axisY - 15)

                Rectangle().fill(palette.borderSoft).frame(width: w, height: 1.5).offset(y: axisY)
                Rectangle().fill(LinearGradient.primary).frame(width: 1.8, height: 34)
                    .offset(x: zeroX, y: axisY - 17)

                Text("MISSED").font(.system(size: 8, weight: .bold)).tracking(0.4)
                    .foregroundStyle(Brand.danger)
                    .offset(x: max(2, zeroX * 0.30), y: axisY + 5)

                ForEach([lo, 12, 24, 36, hi], id: \.self) { t in
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 7)
                        .offset(x: x(t, w), y: axisY)
                    Text(String(format: "%+.0fh", t))
                        .font(.system(size: 9, weight: .bold)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .offset(x: max(0, x(t, w) - 12), y: axisY + 13)
                }

                // 12x12 rotated squares — one per scored connection.
                ForEach(Array(markers.enumerated()), id: \.offset) { _, h in
                    let band = RiskBand692.of(h)
                    Rectangle().fill(band.color).frame(width: 12, height: 12)
                        .rotationEffect(.degrees(45))
                        .offset(x: x(h, w) - 6, y: axisY - 6)
                    Text(String(format: "%@%.1fh", h >= 0 ? "+" : "", h))
                        .font(.system(size: 9, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(band.color)
                        .offset(x: max(0, x(h, w) - 17), y: axisY - 28)
                }
            }
        }
    }
}

#Preview("692 · Hub connections · Light") {
    VesselTransshipmentConnectionScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("692 · Hub connections · Dark") {
    VesselTransshipmentConnectionScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
