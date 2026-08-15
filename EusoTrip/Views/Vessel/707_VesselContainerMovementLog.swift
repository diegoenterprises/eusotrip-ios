//
//  707_VesselContainerMovementLog.swift
//  EusoTrip — Vessel Operator · Container Movement Log.
//
//  Faithful port of "707 Vessel Container Movement Log.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline). Role
//  VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — a terminal move log is an operations surface.
//
//  ARCHETYPE: LOG — a terminal writes hundreds of container moves a day. The retired composition showed
//  FIVE rows in a 360-tall card with no time axis and no move-type distribution, so "what happened today"
//  could not be answered at all. This is a 24-hour SWIMLANE EVENT RASTER (4 lanes, one zero-duration tick
//  per move) over a MOVE-TYPE TALLY over a dense reverse-chronological MONO LEDGER at pitch 34.
//
//  LIVE FUSION: the raster, the tally bar and the ledger are three faces of ONE state — the `events`
//  array returned by a SINGLE containerTimeline.timeline call. Lane bucketing, the 24h window filter and
//  the tally arithmetic are all derived from that one array, so a new move re-reasons all three organs at
//  once off load(). The lane filter drives all three together for the same reason. Degraded provider state
//  surfaces an explicit error card, never a frozen number.
//
//  OFFLINE POLICY: QUEUE(vessel_container_move) — reads are live only; a Record move that fails on an
//  unreachable network is held in the queue and replayed at the head of the next load(). Made visible, not
//  claimed: the dashed QUEUE n chip beside the ledger label is always on screen, and a queued move renders
//  as a dashed-outline row pinned ABOVE the live ledger with its own QUEUED chip so it can never be read as
//  a stamped move. HONEST SHORTFALL: Services/OfflineQueue.swift has no container-move case in QueuedAction
//  today, so this buffer is screen-scoped and does not survive a cold launch — proposed lane
//  enqueueContainerMove(containerId, eventType, portId, ts).
//
//  Data / wiring (line numbers read first-hand 2026-08-11 against
//  server/routers/containerTimeline.ts md5 cf32344941f7c5844053ec8a344826d7, 153 lines, and
//  server/routers/vesselShipments.ts md5 1e4186fb365acaa7cac76303ee502dbd, 4328 lines):
//    containerTimeline.timeline (EXISTS containerTimeline.ts:19 · vesselProcedure query · input
//      {containerId?, shipmentId? coerce, containerNumber?, limit 1...500 default 100} · explicit selects
//      :32-42 and :48-54, merged and sorted DESC :60-70 · returns {events:[{source,id,containerId,
//      shipmentId,eventType,location,portId,temperature,humidity,timestamp,metadata,notes}], total} :72 ·
//      mounted routers.ts:3381, imported routers.ts:39). ONE call feeds raster + tally + ledger.
//    vesselShipments.getContainerTracking (EXISTS vesselShipments.ts:1442 · vesselProcedure query ·
//      {containerNumber?, containerId?} -> {container, movements desc by timestamp}). Used ONLY to resolve
//      the real ISO 6346 containerNumber for the visible rows — timeline returns containerId, not the
//      number. Best-effort and bounded to 8 ids; a failure leaves the honest CTR-<id> title in place.
//    vesselShipments.recordContainerMovement (EXISTS vesselShipments.ts:1468 · vesselProcedure MUTATION ·
//      {containerId, shipmentId? coerce, eventType, portId?, location?, temperature?, humidity?} ->
//      {success:true}). Wired to the Record move CTA.
//    AUDIT: YES — recordContainerMovement inserts containerTracking at vesselShipments.ts:1482-1490 and
//      blockchainAuditTrail at :1495-1507 (eventType "vessel.container_movement_recorded", eventData
//      {shipmentId, containerId, movementEventType, portId, actorUserId, transportMode VESSEL, ts}),
//      best-effort inside try/catch (logger.warn :1508).
//    CHAIN-OPEN: record container move — vesselShipments.recordContainerMovement:1468 writes and audits but
//      does NOT broadcast. WS_CHANNELS.VESSEL_CONTAINER (shared/websocket-events.ts:629) is reachable only
//      from emitVesselBookingStatus (_core/websocket.ts:1670, container fan-out :1706), a booking-status
//      path, never a container-move path; WS_EVENTS.VESSEL_GATE_IN_CONFIRMED (:426) and
//      VESSEL_CONTAINER_RELEASED (:425) have ZERO emitters, while the receiver is already built and waiting
//      at client/src/hooks/useRealtimeEvents.ts:1154 (subscribe :1160). Systemic fault S1. The success
//      copy on this screen therefore says the move was stamped and audited and states plainly that the
//      counter-party was not notified. One-line fix: emitVesselContainerMove(...) beside the audit insert.
//    P0-READ-TENANCY (severe): containerTimeline.ts has ZERO ctx references in all 153 lines
//      (grep -c ctx = 0), and getContainerTracking:1442 destructures ({input}) only at :1444 — either call
//      reads any tenant's move log, reefer temperature included.
//    P0-WRITE-SCOPE (most serious finding here): recordContainerMovement:1468 touches ctx ONLY for
//      ctx.user.id in the audit payload (:1494); the insert at :1482-1490 never checks that
//      input.containerId / input.shipmentId belong to the caller, so any vessel-mode user can forge a
//      discharge or gate-out onto ANY container and it lands in blockchainAuditTrail as authoritative.
//    vesselProcedure (_core/trpc.ts:268) is a MODE gate only — no tenant and no role-within-mode scoping.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. There are no seed arrays in this file.
//  File-scoped types are suffixed 707 to avoid cross-file private collisions.
//
//  transportMode = vessel · country is content: the gate-in stamp this ledger records starts the free-time
//  and per-diem clock, priced by the terminal regime — US LBCT under the MTO tariff filed per FMC/OSRA
//  46 CFR 541 in USD, CAVAN VFPA under CTA carrier tariff plus VFPA storage in CAD, MXZLO API Manzanillo
//  under SAT/API estadias in MXN.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselContainerMovementLogScreen: View {
    let theme: Theme.Palette

    /// Vessel shipment the log is scoped to. 0 (registry / zero-arg use) means "no shipment threaded":
    /// containerTimeline.timeline is then called WITHOUT containerId/shipmentId, which returns the most
    /// recent containerTracking rows terminal-wide — exactly what a duty officer's move log wants, and
    /// exactly the P0-READ-TENANCY hole named in the header. Real rows or the honest empty state, never seeds.
    var shipmentId: Int = 0

    init(theme: Theme.Palette, shipmentId: Int = 0) {
        self.theme = theme
        self.shipmentId = shipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselContainerMovementLogBody707(shipmentId: shipmentId)
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

// MARK: - Lane vocabulary

/// The four terminal move lanes the raster and the tally are cut into. `classify` is a pure read of the
/// live `eventType` string — anything that does not match stays UNLANED and is reported honestly rather
/// than being forced into a lane it does not belong to.
private enum MoveLane707: Int, CaseIterable, Hashable {
    case discharge = 0
    case load      = 1
    case gateIn    = 2
    case gateOut   = 3

    var index: Int { rawValue }

    var label: String {
        switch self {
        case .discharge: return "DISCH"
        case .load:      return "LOAD"
        case .gateIn:    return "GATE-IN"
        case .gateOut:   return "GATE-OUT"
        }
    }

    var chip: String {
        switch self {
        case .discharge: return "DISC"
        case .load:      return "LOAD"
        case .gateIn:    return "GT-IN"
        case .gateOut:   return "GT-OUT"
        }
    }

    var code: String {
        switch self {
        case .discharge: return "UV · DISCHARGE"
        case .load:      return "LV · LOAD"
        case .gateIn:    return "GI · GATE-IN"
        case .gateOut:   return "GO · GATE-OUT"
        }
    }

    /// The eventType this lane writes back through recordContainerMovement. Vocabulary lifted verbatim
    /// from the vessel status enum at server/routers/vesselShipments.ts:168-169 so the write and the read
    /// speak the same language.
    var wireEventType: String {
        switch self {
        case .discharge: return "discharged"
        case .load:      return "loaded_on_vessel"
        case .gateIn:    return "gate_in"
        case .gateOut:   return "gate_out"
        }
    }

    var tint: Color {
        switch self {
        case .discharge: return Brand.success
        case .load:      return Brand.magenta
        case .gateIn:    return Brand.info
        case .gateOut:   return Brand.rail
        }
    }

    static func classify(_ eventType: String?) -> MoveLane707? {
        guard let raw = eventType?.lowercased(), !raw.isEmpty else { return nil }
        let t = raw.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        if t.contains("gate_out") || t.contains("gateout") || t.contains("out_gate") { return .gateOut }
        if t.contains("gate_in")  || t.contains("gatein")  || t.contains("in_gate")  { return .gateIn }
        if t.contains("disch") || t.contains("unload") || t.contains("offload")      { return .discharge }
        if t.contains("load") { return .load }
        return nil
    }
}

// MARK: - Wire shapes (mirror containerTimeline.timeline exactly)

/// SQL decimals (containerTracking.temperature / .humidity) arrive as String on the wire and as Double
/// from some drivers. Decode both without throwing.
private struct FlexDouble707: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self)    { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

/// `location` is a JSON column typed {lat,lng,description?} on containerTracking, but the merged
/// shipment_event branch (containerTimeline.ts:52) can hand back a bare string on legacy rows. Accept both.
private struct FlexLocation707: Decodable {
    var lat: Double?
    var lng: Double?
    var label: String?
    private enum K: String, CodingKey { case lat, lng, description }
    init(from decoder: Decoder) throws {
        if let obj = try? decoder.container(keyedBy: K.self) {
            lat   = (try? obj.decodeIfPresent(Double.self, forKey: .lat)) ?? nil
            lng   = (try? obj.decodeIfPresent(Double.self, forKey: .lng)) ?? nil
            label = (try? obj.decodeIfPresent(String.self, forKey: .description)) ?? nil
        } else if let sv = try? decoder.singleValueContainer(), let s = try? sv.decode(String.self) {
            label = s
        }
    }
}

/// One row of `containerTimeline.timeline` -> events[]. Field-for-field with the explicit selects at
/// containerTimeline.ts:32-42 (tracking branch) and :48-54 (shipment_event branch). `metadata` is an
/// untyped JSON column and is deliberately NOT declared — nothing on this screen reads it.
private struct MoveEvent707: Decodable, Identifiable {
    let source: String?
    let rowId: Int?
    let containerId: Int?
    let shipmentId: Int?
    let eventType: String?
    let location: FlexLocation707?
    let portId: Int?
    let temperature: FlexDouble707?
    let humidity: FlexDouble707?
    let timestamp: String?
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case source, containerId, shipmentId, eventType, location, portId
        case temperature, humidity, timestamp, notes
        case rowId = "id"
    }

    /// Stable across renders: the two branches can collide on `id`, so the source and timestamp
    /// discriminate.
    var id: String { "\(source ?? "e")-\(rowId ?? -1)-\(timestamp ?? "")" }

    var lane: MoveLane707? { MoveLane707.classify(eventType) }
    var at: Date? { TS707.parse(timestamp) }
    var sourceTag: String { (source == "tracking") ? "TRK" : "EVT" }
}

private struct TimelineOut707: Decodable {
    let events: [MoveEvent707]
    let total: Int?
}

/// `vesselShipments.getContainerTracking` -> {container, movements}. Only `containerNumber` is read here;
/// every other column is ignored on purpose so a schema addition cannot break this decode.
private struct ContainerRow707: Decodable {
    let id: Int?
    let containerNumber: String?
}
private struct ContainerTrackingOut707: Decodable {
    let container: ContainerRow707?
}

private struct MutationAck707: Decodable { let success: Bool? }

// MARK: - A move held because the network was unreachable (OFFLINE POLICY affordance)

private struct QueuedMove707: Identifiable {
    let id = UUID()
    let containerId: Int
    let shipmentId: Int
    let title: String
    let lane: MoveLane707
    let stampedAt: Date
}

// MARK: - Timestamp parsing

private enum TS707 {
    static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let sql: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        if let d = isoFrac.date(from: s) { return d }
        if let d = iso.date(from: s)     { return d }
        if let d = sql.date(from: s)     { return d }
        if let n = Double(s) { return Date(timeIntervalSince1970: n > 3_000_000_000 ? n / 1000 : n) }
        return nil
    }

    static func hhmm(_ d: Date?) -> String { d.map { clock.string(from: $0) } ?? "--:--" }
}

// MARK: - Body

private struct VesselContainerMovementLogBody707: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    // Live state only — no seeds anywhere in this file.
    @State private var events: [MoveEvent707] = []
    @State private var numbers: [Int: String] = [:]        // containerId -> real ISO 6346 number
    @State private var total: Int = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var lastSync: Date? = nil

    // Lane filter — drives the raster, the tally AND the ledger together (one state, three organs).
    @State private var filter: MoveLane707? = nil

    // Record-move flow
    @State private var selected: MoveEvent707? = nil
    @State private var recorderOpen = false
    @State private var recordLane: MoveLane707 = .gateIn
    @State private var stamping = false
    @State private var stampNotice: String? = nil
    @State private var stampFailed = false

    // OFFLINE POLICY: QUEUE(vessel_container_move)
    @State private var queued: [QueuedMove707] = []

    private let ledgerWindow: Int = 8          // rows visible at pitch 34 before the list scrolls on
    private let fetchLimit: Int = 200          // timeline caps at 500 (containerTimeline.ts:23)

    // MARK: Derived reads — every organ reads THIS state, never a parallel literal

    private var windowEnd: Date { lastSync ?? Date() }
    private var windowStart: Date { windowEnd.addingTimeInterval(-86_400) }

    /// Events inside the 24h raster window that classify into one of the four lanes.
    private var lanedEvents: [(lane: MoveLane707, frac: Double)] {
        let start = windowStart
        let active = filter
        return events.compactMap { e -> (lane: MoveLane707, frac: Double)? in
            guard let lane = e.lane, let at = e.at else { return nil }
            if let f = active, f != lane { return nil }
            let dt = at.timeIntervalSince(start)
            guard dt >= 0, dt <= 86_400 else { return nil }
            return (lane: lane, frac: dt / 86_400)
        }
    }

    private var laneCounts: [MoveLane707: Int] {
        var out: [MoveLane707: Int] = [:]
        for t in lanedEvents { out[t.lane, default: 0] += 1 }
        return out
    }

    private var windowTotal: Int { lanedEvents.count }

    /// Rows inside the window whose eventType matches none of the four lanes. Reported, never hidden.
    private var unlanedInWindow: Int {
        events.filter { e in
            guard let at = e.at else { return false }
            let dt = at.timeIntervalSince(windowStart)
            return dt >= 0 && dt <= 86_400 && e.lane == nil
        }.count
    }

    /// The ledger shows everything the call returned (including rows older than the raster window and
    /// unlaned rows), newest first, subject to the same lane filter.
    private var ledgerRows: [MoveEvent707] {
        let base = filter == nil ? events : events.filter { $0.lane == filter }
        return base.sorted { (a, b) in
            let ta = a.at ?? Date.distantPast
            let tb = b.at ?? Date.distantPast
            return ta > tb
        }
    }

    private var nowFraction: Double {
        let dt = windowEnd.timeIntervalSince(windowStart)
        return min(1, max(0, dt / 86_400))
    }

    private func title(for e: MoveEvent707) -> String {
        if let cid = e.containerId {
            if let n = numbers[cid], !n.isEmpty { return n }
            return "CTR-\(cid)"
        }
        return "SHPMT-\(e.shipmentId ?? 0)"
    }

    /// The 11-tertiary tail: actor / equipment / position, strictly from live fields.
    private func tail(for e: MoveEvent707) -> String {
        if let t = e.temperature?.value {
            return String(format: "%.1f°C plug", t)
        }
        if let l = e.location?.label, !l.isEmpty { return l }
        if let n = e.notes, !n.isEmpty { return n }
        if let p = e.portId { return "port \(p)" }
        if let raw = e.eventType, !raw.isEmpty { return raw }
        return "no position"
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                heroRaster
                tallyBand
                ledger
                footerStrip
                if recorderOpen { recorder }
                ctaPair
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s7)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .eusoRefreshTask { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                EusoTripEyebrow(verbatim: "VESSEL · SHIPMENTS · MOVE LOG")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("USLGB · LBCT PIER E")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Movement log")
                .font(EType.h1).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("One timeline call feeds the raster, tally and ledger.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            IridescentHairline().padding(.top, Space.s1)
        }
    }

    // MARK: Hero organ — 24h swimlane event raster

    private var heroRaster: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("MOVE RASTER · 24H · LBCT PIER E")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(loadError == nil ? Brand.success : Brand.danger)
                        .frame(width: 6, height: 6)
                    Text(loadError == nil ? "LIVE · \(windowTotal)" : "FEED DOWN")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .monospacedDigit()
                        .foregroundStyle(loadError == nil ? Brand.success : Brand.danger)
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill((loadError == nil ? Brand.success : Brand.danger).opacity(0.12)))
            }

            if loading && events.isEmpty {
                RasterSkeleton707()
            } else {
                MoveRaster707(ticks: lanedEvents, nowFraction: nowFraction, dim: palette.borderFaint)
                HStack(spacing: 0) {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                        Text(String(format: "%02d", h))
                            .font(.system(size: 8, weight: .bold)).tracking(0.4)
                            .monospacedDigit()
                            .foregroundStyle(palette.textTertiary)
                        if h != 24 { Spacer(minLength: 0) }
                    }
                }
                .padding(.leading, 52)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.xl)
    }

    // MARK: Mid-band organ — move-type tally bar

    private var tallyBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("MOVE-TYPE TALLY · TERMINAL CODES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(windowTotal) MOVES · 24H")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                if windowTotal == 0 {
                    Text(loading ? "Loading the 24-hour window…"
                                 : "No moves classified into a lane in the last 24 hours.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(MoveLane707.allCases, id: \.self) { lane in
                                let n = laneCounts[lane] ?? 0
                                let w = geo.size.width * CGFloat(Double(n) / Double(max(1, windowTotal)))
                                ZStack {
                                    Rectangle().fill(lane.tint)
                                    if w > 18 {
                                        Text("\(n)")
                                            .font(.system(size: 9, weight: .heavy))
                                            .monospacedDigit()
                                            .foregroundStyle(Color.white)
                                    }
                                }
                                .frame(width: w)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .frame(height: 12)

                    HStack(spacing: 0) {
                        ForEach(MoveLane707.allCases, id: \.self) { lane in
                            Text(lane.code)
                                .font(.system(size: 8, weight: .bold)).tracking(0.4)
                                .foregroundStyle(lane == .load ? Brand.magenta : palette.textTertiary)
                                .frame(maxWidth: .infinity,
                                       alignment: lane == .gateOut ? .trailing : .leading)
                        }
                    }
                }

                if unlanedInWindow > 0 {
                    Text("\(unlanedInWindow) move\(unlanedInWindow == 1 ? "" : "s") in this window carry an eventType outside the four lanes — listed in the ledger, excluded from the raster and tally.")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    // MARK: Row grammar — mono ledger, reverse chronological, pitch 34

    private var ledger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text("MOVE LEDGER · NEWEST FIRST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(min(ledgerRows.count, ledgerWindow)) OF \(max(total, ledgerRows.count))")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                // OFFLINE POLICY affordance — always on screen, dashed on purpose.
                Text("QUEUE \(queued.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .monospacedDigit()
                    .foregroundStyle(queued.isEmpty ? palette.textTertiary : Brand.warning)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(
                        Capsule().strokeBorder(
                            (queued.isEmpty ? palette.textTertiary : Brand.warning).opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
            }

            VStack(spacing: 0) {
                // Queued moves pin ABOVE the live ledger, dashed, so they read as not-yet-stamped.
                ForEach(queued) { q in
                    QueuedRow707(move: q)
                    Divider().overlay(palette.borderFaint)
                }

                if let err = loadError {
                    ErrorCard707(message: err) { Task { await load() } }
                } else if loading && events.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        LedgerSkeletonRow707()
                        Divider().overlay(palette.borderFaint)
                    }
                } else if ledgerRows.isEmpty {
                    EmptyLedger707(filtered: filter != nil) { filter = nil }
                } else {
                    ForEach(Array(ledgerRows.enumerated()), id: \.element.id) { idx, e in
                        Button {
                            selected = (selected?.id == e.id) ? nil : e
                            stampNotice = nil
                            Task { await resolveNumber(for: e) }
                        } label: {
                            LedgerRow707(
                                time: TS707.hhmm(e.at),
                                sourceTag: e.sourceTag,
                                lane: e.lane,
                                title: title(for: e),
                                tail: tail(for: e),
                                newest: idx == 0,
                                isSelected: selected?.id == e.id
                            )
                        }
                        .buttonStyle(.plain)
                        if idx < ledgerRows.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
            }
            .padding(.vertical, Space.s2)
            .eusoCard(radius: Radius.xl)
        }
    }

    // MARK: Footer strip — dwell advisory + tri-country regime (small country footer)

    private var footerStrip: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Gate-in stamps start free time.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("US LBCT active · per-diem in USD")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            HStack(spacing: Space.s3) {
                CountryTile707(code: "USLGB", active: true)
                CountryTile707(code: "CAVAN", active: false)
                CountryTile707(code: "MXZLO", active: false)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Recorder (opens only when a row supplies a REAL containerId)

    private var recorder: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("STAMP A MOVE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if let e = selected, let cid = e.containerId {
                Text(title(for: e))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)

                HStack(spacing: Space.s2) {
                    ForEach(MoveLane707.allCases, id: \.self) { lane in
                        Button { recordLane = lane } label: {
                            Text(lane.chip)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(recordLane == lane ? Color.white : lane.tint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .fill(recordLane == lane ? lane.tint : lane.tint.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Writes containerTracking and a blockchainAuditTrail row. It does NOT broadcast — no counter-party is notified by this action (CHAIN-OPEN).")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)

                CTAButton(title: stamping ? "Stamping…" : "Stamp \(recordLane.label)",
                          action: { Task { await stamp(containerId: cid, shipmentId: e.shipmentId ?? shipmentId) } },
                          isLoading: stamping)
            } else {
                Text("Tap a move row first. Stamping a move has to be tied to a specific container, and this screen will not guess one for you.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if let n = stampNotice {
                Text(n)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(stampFailed ? Brand.warning : Brand.success)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: CTA pair (236 + 156 — off the 260+132 stamp)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: recorderOpen ? "Close recorder" : "Record move",
                      action: {
                          if selected?.containerId == nil {
                              recorderOpen = true
                              stampFailed = true
                              stampNotice = "Tap a move row to pick the container this stamp belongs to."
                          } else {
                              recorderOpen.toggle()
                          }
                      },
                      leadingIcon: recorderOpen ? "xmark" : "plus")
                .frame(maxWidth: .infinity)

            Button {
                filter = nextFilter(after: filter)
            } label: {
                Text(filter.map { "Lane · \($0.chip)" } ?? "Filter lanes")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                            .fill(palette.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                                    .strokeBorder(palette.borderSoft)
                            )
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 156)
        }
    }

    private func nextFilter(after current: MoveLane707?) -> MoveLane707? {
        switch current {
        case nil:         return .discharge
        case .discharge?: return .load
        case .load?:      return .gateIn
        case .gateIn?:    return .gateOut
        case .gateOut?:   return nil
        }
    }

    // MARK: Loaders — real calls only

    private func load() async {
        loading = true
        loadError = nil

        // OFFLINE POLICY: flush the queue at the head of every load. Successes leave the queue; a move
        // that still cannot reach the server stays queued and stays visibly dashed on screen.
        await flushQueue()

        struct TimelineIn707: Encodable {
            let shipmentId: Int?
            let limit: Int
        }
        do {
            let out: TimelineOut707 = try await EusoTripAPI.shared.query(
                "containerTimeline.timeline",
                input: TimelineIn707(shipmentId: shipmentId > 0 ? shipmentId : nil, limit: fetchLimit))
            // UNCONDITIONAL overwrite — an honest empty response empties the screen.
            events = out.events
            total = out.total ?? out.events.count
            lastSync = Date()
        } catch {
            loadError = error.eusoUserCopy
        }

        // Best-effort: resolve the real ISO 6346 numbers for the visible rows. timeline hands back
        // containerId only, so without this the titles stay at the honest CTR-<id> form. Bounded to the
        // ledger window so this never becomes an N+1 storm, and never allowed to fail the screen.
        var seen: [Int] = []
        for e in ledgerRows.prefix(ledgerWindow) {
            if let cid = e.containerId, numbers[cid] == nil, !seen.contains(cid) { seen.append(cid) }
        }
        for cid in seen {
            if let n = await fetchNumber(cid) { numbers[cid] = n }
        }

        loading = false
    }

    private func fetchNumber(_ containerId: Int) async -> String? {
        struct TrackIn707: Encodable { let containerId: Int }
        let out: ContainerTrackingOut707? = try? await EusoTripAPI.shared.query(
            "vesselShipments.getContainerTracking", input: TrackIn707(containerId: containerId))
        return out?.container?.containerNumber
    }

    private func resolveNumber(for e: MoveEvent707) async {
        guard let cid = e.containerId, numbers[cid] == nil else { return }
        if let n = await fetchNumber(cid) { numbers[cid] = n }
    }

    private struct RecordIn707: Encodable {
        let containerId: Int
        let shipmentId: Int?
        let eventType: String
    }

    private func stamp(containerId: Int, shipmentId sid: Int) async {
        stamping = true
        stampNotice = nil
        stampFailed = false
        let lane = recordLane
        do {
            let ack: MutationAck707 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.recordContainerMovement",
                input: RecordIn707(containerId: containerId,
                                   shipmentId: sid > 0 ? sid : nil,
                                   eventType: lane.wireEventType))
            if ack.success == true {
                // Honest copy: stamped + audited, and explicitly NOT broadcast. See CHAIN-OPEN in the header.
                stampNotice = "\(lane.label) stamped and written to the audit trail. No counter-party was notified."
                stampFailed = false
                await load()
            } else {
                stampFailed = true
                stampNotice = "The stamp was not confirmed. Nothing was recorded — stamp it again."
            }
        } catch {
            if OfflineQueue.isNetworkUnreachable(error) {
                queued.append(QueuedMove707(containerId: containerId,
                                            shipmentId: sid,
                                            title: numbers[containerId] ?? "CTR-\(containerId)",
                                            lane: lane,
                                            stampedAt: Date()))
                stampFailed = true
                stampNotice = "Network unreachable — the move is QUEUED and will be replayed on the next refresh. It is not stamped yet."
            } else {
                stampFailed = true
                stampNotice = error.eusoUserCopy
            }
        }
        stamping = false
    }

    private func flushQueue() async {
        guard !queued.isEmpty else { return }
        var survivors: [QueuedMove707] = []
        for q in queued {
            let ack: MutationAck707? = try? await EusoTripAPI.shared.mutation(
                "vesselShipments.recordContainerMovement",
                input: RecordIn707(containerId: q.containerId,
                                   shipmentId: q.shipmentId > 0 ? q.shipmentId : nil,
                                   eventType: q.lane.wireEventType))
            if ack?.success != true { survivors.append(q) }
        }
        queued = survivors
    }
}

// MARK: - Hero organ view

/// The swimlane raster. Four lanes at h22 / pitch 26, one 3x14 zero-duration tick per move coloured by
/// lane, hour gridlines at 00/06/12/18/24, and a 1.5-wide NOW stem crossing all four lanes. Ticks, not
/// bars — a container move has no duration.
private struct MoveRaster707: View {
    let ticks: [(lane: MoveLane707, frac: Double)]
    let nowFraction: Double
    let dim: Color

    private let shoulder: CGFloat = 52
    private let laneH: CGFloat = 22
    private let pitch: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let axisW = max(1, geo.size.width - shoulder)
            ZStack(alignment: .topLeading) {
                ForEach(MoveLane707.allCases, id: \.self) { lane in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(lane.tint.opacity(0.08))
                        .frame(height: laneH)
                        .offset(y: CGFloat(lane.index) * pitch)
                    Text(lane.label)
                        .font(.system(size: 8, weight: .bold)).tracking(0.4)
                        .foregroundStyle(lane.tint)
                        .offset(x: 4, y: CGFloat(lane.index) * pitch + 6)
                }

                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Rectangle()
                        .fill(dim)
                        .frame(width: 1, height: pitch * 3 + laneH)
                        .offset(x: shoulder + axisW * CGFloat(Double(h) / 24.0) - 1)
                }

                ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(t.lane.tint)
                        .frame(width: 3, height: 14)
                        .offset(x: shoulder + axisW * CGFloat(t.frac) - 1.5,
                                y: CGFloat(t.lane.index) * pitch + 4)
                }

                RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 1.5, height: pitch * 3 + laneH + 12)
                    .offset(x: shoulder + axisW * CGFloat(nowFraction) - 0.75, y: -6)
            }
        }
        .frame(height: pitch * 3 + laneH)
    }
}

private struct RasterSkeleton707: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(MoveLane707.allCases, id: \.self) { lane in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(lane.tint.opacity(0.06))
                    .frame(height: 22)
            }
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: - Ledger row

private struct LedgerRow707: View {
    @Environment(\.palette) private var palette
    let time: String
    let sourceTag: String
    let lane: MoveLane707?
    let title: String
    let tail: String
    let newest: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(time)
                .font(EType.mono(.caption)).tracking(0.3)
                .monospacedDigit()
                .foregroundStyle(palette.textTertiary)
                .frame(width: 56, alignment: .trailing)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(lane?.tint ?? palette.textTertiary)
                .frame(width: 3, height: 14)
                .padding(.leading, 6)

            Text(sourceTag)
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 32, alignment: .leading)
                .padding(.leading, 9)

            Text(lane?.chip ?? "OTHER")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(lane?.tint ?? palette.textSecondary)
                .frame(width: 44, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill((lane?.tint ?? palette.textSecondary).opacity(0.14))
                )
                .padding(.leading, 8)

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(newest ? AnyShapeStyle(LinearGradient.primary)
                                        : AnyShapeStyle(palette.textPrimary))
                .lineLimit(1)
                .padding(.leading, 8)

            Spacer(minLength: Space.s2)

            Text(tail)
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(height: 34)
        .padding(.horizontal, Space.s4)
        .background(isSelected ? palette.bgCardSoft : Color.clear)
        .contentShape(Rectangle())
    }
}

private struct QueuedRow707: View {
    @Environment(\.palette) private var palette
    let move: QueuedMove707

    var body: some View {
        HStack(spacing: 0) {
            Text(TS707.hhmm(move.stampedAt))
                .font(EType.mono(.caption)).tracking(0.3)
                .monospacedDigit()
                .foregroundStyle(Brand.warning)
                .frame(width: 56, alignment: .trailing)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(move.lane.tint.opacity(0.5))
                .frame(width: 3, height: 14)
                .padding(.leading, 6)

            Text("QUE")
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundStyle(Brand.warning)
                .frame(width: 32, alignment: .leading)
                .padding(.leading, 9)

            Text(move.lane.chip)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.warning)
                .frame(width: 44, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                )
                .padding(.leading, 8)

            Text(move.title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .padding(.leading, 8)

            Spacer(minLength: Space.s2)

            Text("QUEUED · not stamped")
                .font(.system(size: 11))
                .foregroundStyle(Brand.warning)
                .lineLimit(1)
        }
        .frame(height: 34)
        .padding(.horizontal, Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(.horizontal, Space.s3)
        )
    }
}

private struct LedgerSkeletonRow707: View {
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 3).fill(palette.borderFaint).frame(width: 44, height: 10)
            RoundedRectangle(cornerRadius: 4).fill(palette.borderFaint).frame(width: 44, height: 16)
            RoundedRectangle(cornerRadius: 3).fill(palette.borderFaint).frame(width: 96, height: 10)
            Spacer()
            RoundedRectangle(cornerRadius: 3).fill(palette.borderFaint).frame(width: 64, height: 10)
        }
        .frame(height: 34)
        .padding(.horizontal, Space.s4)
        .redacted(reason: .placeholder)
    }
}

// MARK: - Empty / error

private struct EmptyLedger707: View {
    @Environment(\.palette) private var palette
    let filtered: Bool
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(filtered ? "No moves in this lane." : "No container moves on record.")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(filtered
                 ? "The lane filter is hiding every row the call returned."
                 : "containerTimeline.timeline returned an empty event list for this scope. Nothing is being withheld and nothing is being invented.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            if filtered {
                Button("Show every lane", action: clear)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
    }
}

private struct ErrorCard707: View {
    @Environment(\.palette) private var palette
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                Text("Move feed unavailable")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Text("The raster and the tally hold at zero rather than show a stale count as live.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Button("Retry", action: retry)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintDanger)
        )
        .padding(.horizontal, Space.s3)
    }
}

// MARK: - Tri-country footer tile

private struct CountryTile707: View {
    @Environment(\.palette) private var palette
    let code: String
    let active: Bool

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(width: 22, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(active ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.borderSoft),
                                      lineWidth: active ? 1.5 : 1)
                )
                .opacity(active ? 1 : 0.6)
            Text(code)
                .font(.system(size: 8, weight: active ? .heavy : .bold))
                .foregroundStyle(active ? palette.textPrimary : palette.textTertiary)
        }
    }
}

// MARK: - Previews

#Preview("707 Container Movement Log · Light") {
    VesselContainerMovementLogScreen(theme: Theme.light)
        .environment(\.palette, Theme.light)
}

#Preview("707 Container Movement Log · Dark") {
    VesselContainerMovementLogScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
