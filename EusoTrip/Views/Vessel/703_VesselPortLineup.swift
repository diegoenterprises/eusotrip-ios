//
//  703_VesselPortLineup.swift
//  EusoTrip — Vessel Operator · Port Lineup.
//
//  Faithful port of "703 Vessel Port Lineup.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline).
//  Role VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) with the SHIPMENTS slot inked.
//
//  ARCHETYPE: BOARD — the subject is fitting hulls into finite quay, so the screen is DIMENSIONAL,
//  not ranked. The previous build was a ladder of percentage rails: two vessels contending for the
//  same window were distinguishable only by an annotation bracket, and nothing on the screen carried
//  a metre. Here the quay is drawn to scale from portBerths.lengthMeters, every hull is drawn to
//  vessels.lengthMeters, and the question "does the next arrival fit?" is answered geometrically.
//
//  LIVE FUSION: the quay plan, the anchorage shelf, the berth-metre budget bar and the lineup rows
//  are four faces of ONE state. berths + fleet + windows + schedules re-reason together off load():
//  a berth flipping to occupied moves the committed metres, shrinks the open run, re-scales the ghost
//  block, and re-tags the rows in the same tick. Degraded provider state surfaces an explicit error
//  card, never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(300s) — the database reads (getPortDetails / getBerthSchedule /
//  getVesselFleet) are live; the MarineTraffic position enrichment behind getVesselsAtPort is a 300 s
//  cache and the WeatherKit marine read a 600 s cache. Staleness is made visibly distinct: the hero
//  header carries an amber, dash-underlined "CACHED · <age>" caption sourced from the last completed
//  load, so a stale read never renders like a fresh one.
//
//  Data / wiring (every line opened first-hand 2026-08-11):
//    vesselShipments.getPortDetails    (EXISTS vesselShipments.ts:1981 · vesselProcedure ·
//      input {portId:number} · returns the ports row spread with berths: portBerths[] ·
//      P0-READ-TENANCY: the query is ({input}) at :1983, portId is caller-supplied, no ownership check)
//      -> the quay segments AND their metre lengths. REAL columns: portBerths.lengthMeters
//         drizzle/schema.ts:11935, portBerths.depthMeters :11936. No metre is invented; a berth whose
//         lengthMeters is null renders an explicit "length not published" segment, never a guess.
//    vesselShipments.getBerthSchedule  (EXISTS vesselShipments.ts:2005 · vesselProcedure ·
//      input {portId:number, berthId?:number} · returns vesselBerthAssignments rows (SELECT at :2019)
//      spread at :2044 with craneWindLimitKt / craneWindLimitBasis / forecastGustKt /
//      gustExceedsCraneLimit / windowWeatherAvailable / windowWeatherFeedConfigured /
//      windowWeatherSource at :2046-2052 · P0-READ-TENANCY at :2007) -> berth occupancy + the windows.
//    vesselShipments.getVesselFleet    (EXISTS vesselShipments.ts:2193 · vesselProcedure ·
//      returns {vessels,total}; the vessels table carries lengthMeters / beamMeters / draftMeters /
//      teuCapacity at drizzle/schema.ts:11784-11787 · P0-READ-TENANCY at :2201, no ctx —
//      vessels.operatorId exists at schema.ts:11790 and is indexed at :11801, unused)
//      -> the LOA that scales every hull footprint and every anchorage tick.
//    multiModal.getVesselSchedules     (EXISTS multiModal.ts:635 · protectedProcedure · per-shipment
//      rows mapped through scheduleStatusMap :693-699, applied at :719 · P0-READ-TENANCY at :641; the
//      where clause falls back to sql`1=1` at :670 so the read is ALL-TENANT, limit 50 at :672)
//      -> the closest thing to a lineup ROW; joined to the fleet on IMO for LOA / draft / TEU.
//    multiModal.getPortOperations      (EXISTS multiModal.ts:576 · protectedProcedure ·
//      input {portCode?} · per-port counts assembled :605-623, congestion threshold
//      vesselCount > 15 at :619 · P0-READ-TENANCY at :578, all-tenant aggregate) -> lineup counts.
//    vesselShipments.getPortConditions (EXISTS vesselShipments.ts:2944 · vesselProcedure ·
//      input {portId:string}) -> a real reason a berth window is unusable (gust over crane limit,
//      pilotage visibility hold). Best-effort overlay: enterprise-gated, hidden when unavailable.
//    vesselShipments.getVesselsAtPort  (EXISTS vesselShipments.ts:2673 · vesselProcedure ·
//      input {portId:string} · a MarineTraffic getVesselsByPort passthrough with a 300 s cache at
//      :2680). The payload shape is NOT owned by this repo, so NOTHING is decoded out of it — it is
//      probed for REACHABILITY only, and that probe is what the amber cached caption reports. No
//      metre, no hull, no ETB on this screen ever comes from it.
//    vesselShipments.getPorts          (EXISTS vesselShipments.ts:3913 · vesselProcedure · optional input
//      {limit, offset, country, search, portType} · returns ports rows including id and unlocode, SELECT
//      at :3934) -> resolves the numeric portId when none is threaded, matched against the busiest
//      unlocode from getPortOperations. If nothing matches, the empty state renders; no id is guessed.
//    STUB · named-gap portLineup: there is NO backing procedure for a lineup queue. Grepping `lineup`
//      across server/routers/ returns only railShipments.getServiceLineup at railShipments.ts:1315,
//      a railProcedure and the wrong mode. Proposed shape:
//        vesselShipments.getPortLineup({ portId: number }) -> Array<{ vessel: string, loaMeters: number,
//          draftMeters: number, teu: number, etb: string, berthId: number | null, waitMinutes: number }>
//        ordered by etb.
//      Until it lands the queue is assembled CLIENT-SIDE from the four reads above and the screen says
//      so in a visible gap notice, including the all-tenant caveat that comes with it.
//    CHAIN-OPEN: assign berth — there is NO writer for vesselBerthAssignments anywhere in
//      server/routers (the only reference is the SELECT at vesselShipments.ts:2019), and
//      WS_EVENTS.VESSEL_BERTH_ASSIGNED (shared/websocket-events.ts:437) is referenced only inside the
//      eventMap of emitVesselPortEvent (server/_core/websocket.ts:1767, map entry :1769), which has
//      ZERO callers. A berth assignment can therefore neither be persisted nor reach a counter-party.
//      The primary CTA is a real Button that renders exactly that notice; it never claims a write.
//    CHAIN: every call on this screen is a READ. No mutation, no blockchainAuditTrail row, no emit.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. File-scoped types are suffixed 703 to
//  avoid cross-file private collisions.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselPortLineupScreen: View {
    let theme: Theme.Palette
    /// Port the lineup is scoped to. 0 (registry / zero-arg use) means "no port threaded":
    /// the loader resolves the busiest port from multiModal.getPortOperations rather than
    /// guessing an id, and renders the bespoke empty state if that read comes back empty.
    var portId: Int = 0

    init(theme: Theme.Palette, portId: Int = 0) {
        self.theme = theme; self.portId = portId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselPortLineupBody703(portId: portId)
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

// MARK: - Wire shapes (mirror the procedures' return rows EXACTLY)

/// SQL decimals arrive as String OR Double depending on the driver path.
private struct FlexDouble703: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

/// `portBerths` row (drizzle/schema.ts:11930-11940) as returned inside getPortDetails.
private struct Berth703: Decodable, Identifiable {
    let id: Int
    let berthNumber: String?
    let berthType: String?
    let lengthMeters: FlexDouble703?
    let depthMeters: FlexDouble703?
    let craneCount: Int?
    let currentVesselId: Int?
    let status: String?
}

/// `vesselShipments.getPortDetails` -> { ...ports row, berths: portBerths[] }.
private struct Port703: Decodable {
    let id: Int?
    let name: String?
    let unlocode: String?
    let country: String?
    let totalBerths: Int?
    let maxDraft: FlexDouble703?
    let berths: [Berth703]?
}

/// `vesselShipments.getBerthSchedule` row — the vesselBerthAssignments row plus the crane-wind seam.
private struct BerthWindow703: Decodable, Identifiable {
    let id: Int
    let vesselId: Int?
    let berthId: Int?
    let scheduledArrival: String?
    let scheduledDeparture: String?
    let status: String?
    let pilotRequired: Bool?
    let craneWindLimitKt: Double?
    let forecastGustKt: Double?
    let gustExceedsCraneLimit: Bool?
    let windowWeatherAvailable: Bool?
}

/// `vessels` row from getVesselFleet — the source of every metre on this screen.
private struct VesselRow703: Decodable, Identifiable {
    let id: Int
    let name: String?
    let imoNumber: String?
    let ownerCompany: String?
    let lengthMeters: FlexDouble703?
    let beamMeters: FlexDouble703?
    let draftMeters: FlexDouble703?
    let teuCapacity: Int?
    let status: String?
}
private struct FleetEnvelope703: Decodable { let vessels: [VesselRow703]; let total: Int? }

/// `multiModal.getVesselSchedules` enriched row (multiModal.ts:701-724).
private struct SchedulePort703: Decodable { let code: String?; let name: String? }
private struct ScheduleRow703: Decodable, Identifiable {
    let id: String
    let vesselName: String?
    let imo: String?
    let shippingLine: String?
    let port: SchedulePort703?
    let eta: String?
    let etd: String?
    let status: String?
    let voyage: String?
    let containers: Int?
    let teuCapacity: Int?
}
private struct ScheduleEnvelope703: Decodable { let vessels: [ScheduleRow703]; let total: Int? }

/// `multiModal.getPortOperations` -> { ports: [...], total, alerts } (multiModal.ts:605-627).
private struct PortOps703: Decodable, Identifiable {
    let code: String?
    let name: String?
    let status: String?
    let vesselCount: Int?
    let vesselsAtBerth: Int?
    let vesselsApproaching: Int?
    let vesselsDeparted: Int?
    let totalBerths: Int?
    let containerCapacityTEU: Int?
    var id: String { code ?? name ?? "port" }
}
private struct PortOpsEnvelope703: Decodable { let ports: [PortOps703]; let total: Int? }

/// `vesselShipments.getPorts` row (vesselShipments.ts:3913, SELECT at :3934) — used only to turn a
/// UN/LOCODE into the numeric portId the detail reads require.
private struct PortIndexRow703: Decodable, Identifiable {
    let id: Int
    let name: String?
    let unlocode: String?
    let country: String?
}

/// `vesselShipments.getVesselsAtPort` (vesselShipments.ts:2673) — a MarineTraffic passthrough whose
/// shape this repo does not own. Nothing is read out of it: the decoder records only whether a
/// payload arrived, which is exactly what the staleness caption is entitled to claim.
private struct AISProbe703: Decodable {
    let reachable: Bool
    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer(), c.decodeNil() { reachable = false }
        else { reachable = true }
    }
}

/// `vesselShipments.getPortConditions` (vesselShipments.ts:2944) — best-effort overlay.
private struct PortConditions703: Decodable {
    let available: Bool?
    let reason: String?
    let craneWindLimitKt: Double?
    let forecastGustKt: Double?
    let gustExceedsCraneLimit: Bool?
    let pilotageHold: Bool?
    let source: String?
}

// MARK: - Derived view models (computed from live state only)

private struct QuaySegment703: Identifiable {
    let id: Int
    let label: String
    let lengthMeters: Double?      // nil -> the metre gap is rendered, never guessed
    let depthMeters: Double?
    let occupantName: String?
    let occupantLOA: Double?
    let occupantDraft: Double?
    var isOpen: Bool { occupantName == nil }
}

private struct AnchorTick703: Identifiable {
    let id: String
    let name: String
    let loaMeters: Double?
    let draftMeters: Double?
}

private struct LineupRow703: Identifiable {
    let id: String
    let vesselName: String
    let loaMeters: Double?
    let draftMeters: Double?
    let teu: Int?
    let etb: Date?
    let berthLabel: String?        // nil -> DASHED EMPTY tag
}

// MARK: - Body

private struct VesselPortLineupBody703: View {
    @Environment(\.palette) private var palette
    let portId: Int

    // Live state — no seeds anywhere.
    @State private var port: Port703? = nil
    @State private var berths: [Berth703] = []
    @State private var windows: [BerthWindow703] = []
    @State private var fleet: [VesselRow703] = []
    @State private var schedules: [ScheduleRow703] = []
    @State private var ops: PortOps703? = nil
    @State private var conditions: PortConditions703? = nil
    /// The portId actually read from — the threaded one, or the one getPorts resolved.
    @State private var activePortId: Int = 0
    /// Did the 300 s-cached AIS passthrough answer on this tick? Drives the staleness caption.
    @State private var aisReachable: Bool? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var lastTick: Date? = nil
    @State private var assignNotice: String? = nil
    @State private var showWindows = false

    // MARK: Derived — every organ reads THIS state, never a parallel literal

    private var vesselById: [Int: VesselRow703] {
        Dictionary(fleet.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var vesselByIMO: [String: VesselRow703] {
        Dictionary(fleet.compactMap { v in v.imoNumber.map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
    }
    private var berthById: [Int: Berth703] {
        Dictionary(berths.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A berth is occupied when the row says so, or when a live window is berthed on it.
    private func occupantVesselId(for berth: Berth703) -> Int? {
        if let v = berth.currentVesselId { return v }
        if let w = windows.first(where: { $0.berthId == berth.id && ($0.status ?? "") == "berthed" }) {
            return w.vesselId
        }
        if (berth.status ?? "") == "occupied" { return nil }
        return nil
    }

    private var segments: [QuaySegment703] {
        berths.map { b in
            let v = occupantVesselId(for: b).flatMap { vesselById[$0] }
            let occupied = v != nil || (b.status ?? "") == "occupied"
            return QuaySegment703(
                id: b.id,
                label: b.berthNumber ?? "—",
                lengthMeters: b.lengthMeters?.value,
                depthMeters: b.depthMeters?.value,
                occupantName: v?.name ?? (occupied ? "occupied" : nil),
                occupantLOA: v?.lengthMeters?.value,
                occupantDraft: v?.draftMeters?.value
            )
        }
    }

    /// Total published quay. Berths with no published length are EXCLUDED and counted separately
    /// so the plan never silently absorbs an unknown into a drawn metre.
    private var totalQuayMeters: Double { segments.compactMap { $0.lengthMeters }.reduce(0, +) }
    private var undimensionedBerths: [QuaySegment703] { segments.filter { $0.lengthMeters == nil } }

    private var committedMeters: Double {
        segments.filter { !$0.isOpen }.compactMap { $0.lengthMeters }.reduce(0, +)
    }
    private var openMeters: Double {
        segments.filter { $0.isOpen }.compactMap { $0.lengthMeters }.reduce(0, +)
    }
    /// The contiguous run that actually matters — you cannot moor across two berths.
    private var longestOpenRun: Double? {
        segments.filter { $0.isOpen }.compactMap { $0.lengthMeters }.max()
    }
    private var longestOpenBerthLabel: String? {
        guard let run = longestOpenRun else { return nil }
        return segments.first(where: { $0.isOpen && $0.lengthMeters == run })?.label
    }

    /// The lineup: approaching shipments at this port, by ETA, joined to the fleet on IMO.
    private var lineup: [LineupRow703] {
        let approaching = schedules.filter { ($0.status ?? "") == "approaching" }
        let scoped: [ScheduleRow703]
        if let code = port?.unlocode, !code.isEmpty {
            let atPort = approaching.filter { ($0.port?.code ?? "") == code }
            scoped = atPort.isEmpty ? approaching : atPort
        } else {
            scoped = approaching
        }
        let rows: [LineupRow703] = scoped.map { s in
            let v = s.imo.flatMap { vesselByIMO[$0] }
            let berthLabel: String? = {
                guard let vid = v?.id else { return nil }
                guard let w = windows.first(where: { $0.vesselId == vid && ($0.status ?? "") != "departed" && ($0.status ?? "") != "cancelled" }),
                      let bid = w.berthId else { return nil }
                return berthById[bid]?.berthNumber
            }()
            return LineupRow703(
                id: s.id,
                vesselName: s.vesselName ?? v?.name ?? "Unnamed vessel",
                loaMeters: v?.lengthMeters?.value,
                draftMeters: v?.draftMeters?.value,
                teu: v?.teuCapacity ?? s.teuCapacity,
                etb: Self.parseISO(s.eta),
                berthLabel: berthLabel
            )
        }
        return rows.sorted { (a, b) in
            switch (a.etb, b.etb) {
            case let (x?, y?): return x < y
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return a.vesselName < b.vesselName
            }
        }
    }

    /// The anchorage shelf: every vessel in the line drawn to its true LOA, in ETB order.
    private var anchorTicks: [AnchorTick703] {
        lineup.prefix(5).map {
            AnchorTick703(id: $0.id, name: $0.vesselName.uppercased(),
                          loaMeters: $0.loaMeters, draftMeters: $0.draftMeters)
        }
    }

    private var nextVessel: LineupRow703? { lineup.first }

    /// Overhang of the next arrival against the longest open run. Positive = it does not fit.
    private var overhangMeters: Double? {
        guard let loa = nextVessel?.loaMeters, let run = longestOpenRun else { return nil }
        return loa - run
    }

    /// The first vessel in the line that actually fits the longest open run — derived on device.
    private var firstFittingVessel: LineupRow703? {
        guard let run = longestOpenRun else { return nil }
        return lineup.first(where: { ($0.loaMeters ?? .greatestFiniteMagnitude) <= run })
    }

    private var hasAnything: Bool { !berths.isEmpty || !lineup.isEmpty }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.vertical, Space.s1)

                if loading && !hasAnything {
                    loadingCard
                } else if let loadError {
                    errorCard(loadError)
                } else if !hasAnything {
                    emptyCard
                } else {
                    heroQuayPlan
                    budgetSection
                    lineupSection
                    derivedMoveRow
                    countryFooter
                    ctaPair
                    if showWindows { windowsPanel }
                    if let assignNotice { GapNotice703(title: "Berth assignment is not wired", body: assignNotice) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL · PORT LINEUP · QUAY PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text(port?.unlocode ?? (activePortId > 0 ? "PORT \(activePortId)" : "—"))
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Port Lineup")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let status = ops?.status {
                    StatusPill(text: status, kind: status == "congested" ? .warning : .success)
                }
            }
            Text(sublineText)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var sublineText: String {
        var parts: [String] = []
        if let n = port?.name, !n.isEmpty { parts.append([port?.unlocode, n].compactMap { $0 }.joined(separator: " ")) }
        if !berths.isEmpty { parts.append("\(berths.count) berths") }
        if totalQuayMeters > 0 { parts.append("\(Self.m(totalQuayMeters)) of quay") }
        parts.append("\(lineup.count) in the line")
        return parts.joined(separator: " · ")
    }

    // MARK: HERO · to-scale quay plan + anchorage shelf

    private var heroQuayPlan: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Header
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(totalQuayMeters > 0 ? Self.m(totalQuayMeters) : "—")
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("of quay · \(berths.count) berths")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(occupancyLine)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("TO SCALE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    // OFFLINE AFFORDANCE — a cached read never renders like a fresh one.
                    Text(cacheLabel)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.warning)
                        .overlay(alignment: .bottom) {
                            DashRule703()
                                .stroke(Brand.warning.opacity(0.85),
                                        style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(height: 1)
                                .offset(y: 3)
                        }
                }
            }

            // Quay plan
            GeometryReader { geo in
                quayPlan(width: geo.size.width)
            }
            .frame(height: 92)

            if !undimensionedBerths.isEmpty {
                GapNotice703(
                    title: "Berth length not published",
                    body: undimensionedNotice
                )
            }

            Divider().overlay(palette.borderFaint)

            // Anchorage shelf
            HStack {
                Text("AT ANCHOR · ETB ORDER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let run = longestOpenRun, let label = longestOpenBerthLabel {
                    Text(freeRunLabel(label, run))
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.warning)
                }
            }
            if anchorTicks.isEmpty {
                Text("No vessel is waiting on this port in the live feed.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                GeometryReader { geo in
                    anchorShelf(width: geo.size.width)
                }
                .frame(height: CGFloat(anchorTicks.count) * 15 + 2)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    /// One metre is the same number of points in the plan and in the shelf.
    private func pxPerMeter(_ width: CGFloat) -> CGFloat {
        let usable = max(width - CGFloat(max(segments.count - 1, 0)) * 3, 1)
        return totalQuayMeters > 0 ? usable / CGFloat(totalQuayMeters) : 0
    }

    @ViewBuilder
    private func quayPlan(width: CGFloat) -> some View {
        let ppm = pxPerMeter(width)
        HStack(alignment: .top, spacing: 3) {
            ForEach(segments) { seg in
                let w: CGFloat = seg.lengthMeters.map { CGFloat($0) * ppm } ?? 44
                VStack(spacing: 0) {
                    // metre dimension
                    Text(seg.lengthMeters.map { Self.m($0) } ?? "— m")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .monospacedDigit()
                        .foregroundStyle(seg.lengthMeters == nil ? Brand.warning : palette.textSecondary)
                        .frame(height: 10)
                    DimensionRule703().stroke(palette.textTertiary.opacity(0.55), lineWidth: 1)
                        .frame(height: 6)
                    // quay wall
                    ZStack {
                        Rectangle().fill(palette.textPrimary.opacity(0.10))
                        Text(seg.label)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(height: 12)
                    .padding(.top, 4)
                    // water + hull footprint
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Brand.info.opacity(0.06))
                        if seg.isOpen {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                .foregroundStyle(Brand.warning)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Brand.warning.opacity(0.08)))
                                .frame(width: w, height: 16)
                                .overlay {
                                    Text(seg.lengthMeters.map { Self.m($0) } ?? "OPEN")
                                        .font(.system(size: 8, weight: .heavy)).monospacedDigit()
                                        .foregroundStyle(Brand.warning)
                                }
                        } else if let loa = seg.occupantLOA {
                            HullFootprint703()
                                .fill(LinearGradient.diagonal)
                                .frame(width: min(CGFloat(loa) * ppm, w), height: 16)
                                .overlay(alignment: .leading) {
                                    Text(Self.m(loa))
                                        .font(.system(size: 8, weight: .heavy)).monospacedDigit()
                                        .foregroundStyle(.white)
                                        .frame(width: min(CGFloat(loa) * ppm, w))
                                }
                        } else {
                            // Occupied, but the occupant's LOA is not published — say so, do not draw.
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(palette.textTertiary.opacity(0.20))
                                .frame(width: w, height: 16)
                                .overlay {
                                    Text("LOA —").font(.system(size: 8, weight: .heavy))
                                        .foregroundStyle(palette.textSecondary)
                                }
                        }
                    }
                    .frame(height: 22)
                    .padding(.top, 4)
                    // captions
                    Text(seg.isOpen ? "AVAILABLE" : Self.upper(seg.occupantName))
                        .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(seg.isOpen ? Brand.warning : palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(height: 11)
                        .padding(.top, 3)
                    Text(depthOrDraft(seg))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: w)
            }
        }
    }

    @ViewBuilder
    private func anchorShelf(width: CGFloat) -> some View {
        let ppm = pxPerMeter(width)
        let runX: CGFloat? = longestOpenRun.map { CGFloat($0) * ppm }
        ZStack(alignment: .topLeading) {
            if let runX {
                // the open-run question, drawn once, measured against every hull in the line
                DashRule703(vertical: true)
                    .stroke(Brand.warning, style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                    .frame(width: 2, height: CGFloat(anchorTicks.count) * 15)
                    .offset(x: runX)
            }
            VStack(spacing: 4) {
                ForEach(anchorTicks) { t in
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            if let loa = t.loaMeters {
                                Capsule()
                                    .fill((runX != nil && CGFloat(loa) * ppm > (runX ?? 0)) ? Brand.warning : Brand.success)
                                    .frame(width: max(CGFloat(loa) * ppm, 2), height: 5)
                            } else {
                                Capsule()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    .foregroundStyle(palette.textTertiary)
                                    .frame(width: 40, height: 5)
                            }
                        }
                        .frame(width: max((runX ?? 60) + 30, 90), alignment: .leading)
                        Text(t.name)
                            .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 4)
                        Text(tickSpec(t))
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(height: 11)
                }
            }
        }
    }

    // MARK: MID-BAND · berth-metre budget

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                sectionTick
                Text("BERTH-METRE BUDGET · NEXT BY ETB")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let run = longestOpenRun {
                    Text("OPEN RUN \(Self.m(run))")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                }
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Self.m(committedMeters)) committed")
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(openLine)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if totalQuayMeters > 0 {
                    GeometryReader { geo in
                        budgetBar(width: geo.size.width)
                    }
                    .frame(height: 40)
                } else {
                    GapNotice703(
                        title: "No published quay metres",
                        body: "Every portBerths.lengthMeters on this port is null, so the budget bar has nothing real to divide. Fill the column and the bar draws itself."
                    )
                }
                HStack(alignment: .firstTextBaseline) {
                    if let n = nextVessel {
                        Text(nextVsRunLine(n))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Text("Nothing inbound in the live feed.")
                            .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    if let over = overhangMeters {
                        Text(over > 0 ? "+\(Self.m(over)) over" : "fits by \(Self.m(-over))")
                            .font(.system(size: 11, weight: .bold)).monospacedDigit()
                            .foregroundStyle(over > 0 ? Brand.danger : Brand.success)
                    } else if nextVessel != nil {
                        Text("LOA not published")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    @ViewBuilder
    private func budgetBar(width: CGFloat) -> some View {
        // The bar is inset so an overhanging ghost has somewhere real to overhang INTO.
        let barW = max(width - 20, 1)
        let ppm = totalQuayMeters > 0 ? barW / CGFloat(totalQuayMeters) : 0
        let committedW = CGFloat(committedMeters) * ppm
        let ghostW: CGFloat? = nextVessel?.loaMeters.map { min(CGFloat($0) * ppm, barW - committedW + 20) }
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.borderFaint)
                .frame(width: barW, height: 16)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient.primary)
                .frame(width: max(committedW, 0), height: 16)
            // the end of the quay — what the ghost is measured against
            DashRule703(vertical: true)
                .stroke(Brand.danger.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 1, height: 38)
                .offset(x: barW)
            if let ghostW {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .foregroundStyle((overhangMeters ?? 0) > 0 ? Brand.danger : Brand.success)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(((overhangMeters ?? 0) > 0 ? Brand.danger : Brand.success).opacity(0.08))
                    )
                    .frame(width: max(ghostW, 4), height: 14)
                    .offset(x: committedW, y: 22)
            }
        }
    }

    // MARK: THE LINE

    private var lineupSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                sectionTick
                Text("THE LINE · BY ETB")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(waitingLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                if lineup.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No vessel is approaching this port")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text("No voyage is showing an approaching status for this port. Nothing is invented to fill the board.")
                            .font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(lineup.prefix(8).enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        lineupRow(row)
                    }
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)

            GapNotice703(
                title: "This queue is not reported — it is assembled here",
                body: "There is no port lineup read. This board is assembled on this device by crossing the vessel schedule, the fleet list and the berth schedule — and the schedule it starts from is not filtered to your company and stops at 50 rows. Treat it as a working picture: it can show vessels that are not yours, and it can be missing arrivals past that cap. Confirm the order with the port office before you commit a berth."
            )
        }
    }

    private func lineupRow(_ row: LineupRow703) -> some View {
        HStack(alignment: .center, spacing: Space.s2) {
            BerthTag703(label: row.berthLabel)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.vesselName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(specLine(row))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(row.etb.map { Self.hhmm($0) } ?? "ETB —")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(row.etb.map { "wait \(Self.waitLabel($0))" } ?? "no ETB on the wire")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func specLine(_ row: LineupRow703) -> String {
        var parts: [String] = []
        parts.append(row.loaMeters.map { "LOA \(Self.m($0))" } ?? "LOA —")
        parts.append(row.draftMeters.map { "draft \(Self.m1($0))" } ?? "draft —")
        parts.append(row.teu.map { "\(Self.thousands($0)) TEU" } ?? "TEU —")
        return parts.joined(separator: " · ")
    }

    // MARK: Derived move (computed on device from the loaded rows — no coach procedure is called)

    @ViewBuilder
    private var derivedMoveRow: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(derivedMoveTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(derivedMoveDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var derivedMoveTitle: String {
        guard let berth = longestOpenBerthLabel else { return "No open berth to give" }
        guard let fit = firstFittingVessel else {
            return "Nothing in the line fits \(berth)"
        }
        if let first = nextVessel, first.id != fit.id {
            return "Give \(berth) to \(fit.vesselName), not \(first.vesselName)"
        }
        return "\(fit.vesselName) takes \(berth)"
    }

    private var derivedMoveDetail: String {
        guard let run = longestOpenRun else {
            return "Worked out on this device from the rows above, not from a coaching feed."
        }
        guard let fit = firstFittingVessel, let loa = fit.loaMeters else {
            if let over = overhangMeters, over > 0, let n = nextVessel {
                return "\(n.vesselName) is \(Self.m(over)) too long for the \(Self.m(run)) run. Derived on device."
            }
            return "Worked out on this device from the rows above, not from a coaching feed."
        }
        return "\(Self.m(loa)) fits the \(Self.m(run)) run. Derived on device from the loaded rows."
    }

    // MARK: Berth windows (real rows from getBerthSchedule, revealed by the secondary CTA)

    private var windowsPanel: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BERTH WINDOWS · SCHEDULED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if windows.isEmpty {
                Text("No berth window is scheduled on this port.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(windows.prefix(6)) { w in
                    HStack(spacing: Space.s2) {
                        BerthTag703(label: w.berthId.flatMap { berthById[$0]?.berthNumber })
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.vesselId.flatMap { vesselById[$0]?.name } ?? "Vessel —")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text(Self.windowSpan(w))
                                .font(EType.mono(.micro))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 4)
                        if w.gustExceedsCraneLimit == true, let g = w.forecastGustKt, let l = w.craneWindLimitKt {
                            StatusPill(text: Self.gustLabel(gust: g, limit: l), kind: .warning)
                        } else if w.windowWeatherAvailable == false {
                            Text("no gust feed").font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .padding(.vertical, Space.s2)
                }
            }
            if let c = conditions, c.available == true, c.pilotageHold == true {
                GapNotice703(title: "Pilotage hold at this port",
                             body: "Port conditions report a visibility pilotage hold — no window on this quay is workable until it clears.")
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Country footer (small — content inside the screen, never a separate file)

    private var countryFooter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Divider().overlay(palette.borderFaint)
            HStack(spacing: Space.s5) {
                countryPlate("US", "USCG · CBP", active: (port?.country ?? "US") == "US")
                countryPlate("CA", "TC · CBSA", active: (port?.country ?? "") == "CA")
                countryPlate("MX", "SEMAR · SAT", active: (port?.country ?? "") == "MX")
                Spacer(minLength: 0)
            }
        }
    }

    private func countryPlate(_ code: String, _ regime: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(code)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Brand.blue : palette.textTertiary)
                .frame(width: 20, height: 13)
                .background(RoundedRectangle(cornerRadius: 3)
                    .fill(active ? Brand.blue.opacity(0.14) : palette.tintNeutral))
            Text(active ? "\(regime) · active" : regime)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(active ? Brand.blue : palette.textTertiary)
        }
    }

    // MARK: CTA pair (widths deliberately off the 244+148 stamp)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: assignTitle,
                action: {
                    // CHAIN-OPEN, stated plainly. No mutation exists to fire.
                    assignNotice = "Berth assignment is not available yet — this platform can read a berth schedule but cannot write one. The assignment was not saved and it reached neither the terminal, the pilot, nor the shipper. Nothing was sent. Confirm the berth over the radio."
                },
                subtitle: "berth assignment is not available yet"
            )
            .frame(maxWidth: .infinity)

            Button {
                showWindows.toggle()
            } label: {
                VStack(spacing: 2) {
                    Text(showWindows ? "Hide windows" : "Berth schedule")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(windowCountLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderSoft))
            }
            .frame(width: 150)
        }
    }

    private var assignTitle: String {
        if let berth = longestOpenBerthLabel, let fit = firstFittingVessel {
            return "Assign \(berth) · \(fit.vesselName.split(separator: " ").last.map { String($0) } ?? fit.vesselName)"
        }
        return "Assign a berth"
    }

    // MARK: Small parts

    private var sectionTick: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(LinearGradient.primary)
            .frame(width: 3, height: 10)
    }

    private var loadingCard: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Reading the quay…").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The port read failed")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.danger)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("No metre is shown while the read is down — a stale quay plan is worse than none.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No quay to draw")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(activePortId > 0
                 ? "getPortDetails returned no berths for this port and no vessel is approaching it."
                 : "No port is threaded, and getPortOperations plus getPorts could not resolve one. Nothing is drawn from a guessed id.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var cacheLabel: String {
        guard let t = lastTick else { return "AWAITING FIRST TICK" }
        if aisReachable == false { return "AIS FEED DOWN · DB ONLY" }
        let mins = max(0, Int(Date().timeIntervalSince(t) / 60))
        return mins < 1 ? "AIS CACHED 300s · JUST NOW" : "AIS CACHED 300s · \(mins) MIN"
    }

    // MARK: Copy helpers (hoisted so no Text body carries a nested interpolation)

    private var occupancyLine: String {
        let berthed = segments.filter { !$0.isOpen }.count
        let open = segments.filter { $0.isOpen }.count
        return "\(berthed) berthed · \(open) open"
    }
    private var openLine: String {
        let where_ = longestOpenBerthLabel ?? ""
        let suffix = where_.isEmpty ? "" : " · " + where_
        return Self.m(openMeters) + " open" + suffix
    }
    private var waitingLabel: String { "\(lineup.count) WAITING" }
    private var windowCountLabel: String {
        let n = windows.count
        return "live · \(n) " + (n == 1 ? "window" : "windows")
    }
    private var undimensionedNotice: String {
        let names = undimensionedBerths.map { $0.label }.joined(separator: ", ")
        return "portBerths.lengthMeters is null for " + names
            + ". Those segments are drawn undimensioned — the plan will not invent a metre."
    }
    private func freeRunLabel(_ berth: String, _ run: Double) -> String {
        berth + " FREE RUN " + Self.m(run)
    }
    private func nextVsRunLine(_ n: LineupRow703) -> String {
        let loa = n.loaMeters.map { Self.m($0) } ?? "LOA —"
        let run = longestOpenRun.map { Self.m($0) } ?? "— m"
        return n.vesselName.uppercased() + " · " + loa + " vs " + run + " run"
    }
    private func tickSpec(_ t: AnchorTick703) -> String {
        let loa = t.loaMeters.map { Self.m($0) } ?? "— m"
        let dr = t.draftMeters.map { Self.m1($0) } ?? "—"
        return loa + " · " + dr + " draft"
    }
    private func waitCell(_ row: LineupRow703) -> String {
        guard let etb = row.etb else { return "no ETB on the wire" }
        return "wait " + Self.waitLabel(etb)
    }
    private func depthOrDraft(_ seg: QuaySegment703) -> String {
        if seg.isOpen { return seg.depthMeters.map { Self.m1($0) + " deep" } ?? "depth —" }
        return seg.occupantDraft.map { Self.m1($0) + " draft" } ?? "draft —"
    }
    private static func upper(_ s: String?) -> String { (s ?? "OCCUPIED").uppercased() }
    private static func gustLabel(gust: Double, limit: Double) -> String {
        "gust \(Int(gust)) kt · limit \(Int(limit)) kt"
    }
    private static func windowSpan(_ w: BerthWindow703) -> String {
        let a = parseISO(w.scheduledArrival).map { hhmm($0) }
        let d = parseISO(w.scheduledDeparture).map { hhmm($0) }
        return [a, d].compactMap { $0 }.joined(separator: " → ")
    }

    // MARK: Load (one tick · all four organs re-reason together)

    private func load() async {
        loading = true; loadError = nil
        var resolvedPortId = portId
        var resolvedCode: String? = nil

        struct PortCodeIn703: Encodable { let portCode: String? }
        struct PortIdIn703: Encodable { let portId: Int }
        struct PortIdStrIn703: Encodable { let portId: String }
        struct FleetIn703: Encodable { let limit: Int; let offset: Int }
        struct SchedIn703: Encodable { let portCode: String? }
        struct PortsIn703: Encodable { let search: String?; let limit: Int; let offset: Int }

        // 1) Port operations — the all-tenant counts, and the fallback that resolves a port
        //    when none is threaded (never a guessed id).
        do {
            let env: PortOpsEnvelope703 = try await EusoTripAPI.shared.query(
                "multiModal.getPortOperations", input: PortCodeIn703(portCode: nil))
            let ranked = env.ports.sorted { ($0.vesselCount ?? 0) > ($1.vesselCount ?? 0) }
            ops = ranked.first
            resolvedCode = ops?.code
        } catch {
            ops = nil
        }

        // 1b) No port threaded: resolve the numeric id by READING the ports index for the busiest
        //     unlocode. Never a guessed id — an unmatched code leaves resolvedPortId at 0 and the
        //     screen renders its empty state.
        if resolvedPortId == 0, let code = resolvedCode, !code.isEmpty {
            do {
                let rows: [PortIndexRow703] = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPorts", input: PortsIn703(search: code, limit: 5, offset: 0))
                if let exact = rows.first(where: { $0.unlocode == code }) {
                    resolvedPortId = exact.id
                } else if let first = rows.first {
                    resolvedPortId = first.id
                }
            } catch {
                resolvedPortId = 0
            }
        }

        // 2) Port details — the quay segments and their REAL metres.
        if resolvedPortId > 0 {
            do {
                let p: Port703? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPortDetails", input: PortIdIn703(portId: resolvedPortId))
                port = p                              // unconditional overwrite
                berths = p?.berths ?? []
                if let code = p?.unlocode { resolvedCode = code }
            } catch {
                loadError = error.eusoUserCopy
                port = nil; berths = []
            }
        } else {
            // No port threaded: there is no id to read details for. Say so rather than invent one.
            port = nil; berths = []
        }

        // 3) Berth windows — occupancy + the crane-wind seam.
        if resolvedPortId > 0 {
            do {
                windows = try await EusoTripAPI.shared.query(
                    "vesselShipments.getBerthSchedule", input: PortIdIn703(portId: resolvedPortId))
            } catch {
                windows = []
            }
        } else {
            windows = []
        }

        // 4) Fleet — the LOA / draft / TEU that scale every hull on this screen.
        do {
            let env: FleetEnvelope703 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn703(limit: 50, offset: 0))
            fleet = env.vessels
        } catch {
            fleet = []
        }

        // 5) The nearest thing to a lineup row. ALL-TENANT by construction (multiModal.ts:670).
        do {
            let env: ScheduleEnvelope703 = try await EusoTripAPI.shared.query(
                "multiModal.getVesselSchedules", input: SchedIn703(portCode: resolvedCode))
            schedules = env.vessels
        } catch {
            schedules = []
        }

        // 6) Marine conditions — best-effort overlay, enterprise-gated. A failure never
        //    degrades the quay plan; the pilotage-hold notice simply stays hidden.
        if resolvedPortId > 0 {
            conditions = try? await EusoTripAPI.shared.query(
                "vesselShipments.getPortConditions", input: PortIdStrIn703(portId: String(resolvedPortId)))
        } else {
            conditions = nil
        }

        // 7) AIS reachability probe. Enrichment only — nothing is decoded out of the passthrough,
        //    it just tells the header whether the 300 s-cached position feed answered.
        if resolvedPortId > 0 {
            let probe: AISProbe703? = try? await EusoTripAPI.shared.query(
                "vesselShipments.getVesselsAtPort", input: PortIdStrIn703(portId: String(resolvedPortId)))
            aisReachable = probe?.reachable ?? false
        } else {
            aisReachable = nil
        }

        activePortId = resolvedPortId
        lastTick = Date()
        loading = false
    }

    // MARK: Formatters

    private static func m(_ v: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal; n.maximumFractionDigits = 0; n.groupingSeparator = ","
        return (n.string(from: NSNumber(value: v)) ?? "\(Int(v))") + " m"
    }
    private static func m1(_ v: Double) -> String { String(format: "%.1f m", v) }
    private static func thousands(_ v: Int) -> String {
        let n = NumberFormatter(); n.numberStyle = .decimal; n.groupingSeparator = ","
        return n.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    private static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
    private static func hhmm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private static func waitLabel(_ etb: Date) -> String {
        let mins = Int(etb.timeIntervalSinceNow / 60)
        if mins <= 0 { return "now" }
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }
}

// MARK: - File-scoped parts (suffixed 703 — no new global tokens)

/// Plan-view hull footprint: parallel body, pointed bow to seaward.
private struct HullFootprint703: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let bow = min(12, rect.width * 0.30)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - bow, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - bow, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A single dashed rule — the staleness underline, the open-run reference, the quay-end marker.
private struct DashRule703: Shape {
    var vertical: Bool = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if vertical {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return p
    }
}

/// A dimension rule with end ticks — the metre callout under each berth segment.
private struct DimensionRule703: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// The berth tag that replaces the status pill. Unassigned reads as a dashed, EMPTY tag —
/// the absence is the message.
private struct BerthTag703: View {
    let label: String?
    @Environment(\.palette) private var palette
    var body: some View {
        ZStack {
            if let label {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)],
                                         startPoint: .leading, endPoint: .trailing))
                Text(label)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.blue)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    .foregroundStyle(palette.textTertiary.opacity(0.6))
            }
        }
        .frame(width: 34, height: 20)
        .accessibilityLabel(label.map { "Berth \($0)" } ?? "No berth assigned")
    }
}

/// The honest gap notice. A section with no backing procedure says so here rather than
/// rendering a plausible number.
private struct GapNotice703: View {
    let title: String
    let body_: String
    @Environment(\.palette) private var palette
    init(title: String, body: String) { self.title = title; self.body_ = body }
    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(body_)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Brand.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(Brand.warning.opacity(0.30)))
    }
}

// MARK: - Previews

#Preview("703 Port Lineup · Light") {
    VesselPortLineupScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#Preview("703 Port Lineup · Dark") {
    VesselPortLineupScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
