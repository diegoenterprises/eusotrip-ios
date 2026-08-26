//
//  009_RailIntermodalJourney.swift
//  EusoTrip — Rail · Shipper · Intermodal Journey (brick 009).
//
//  PURPOSE (one line): the whole door-to-door intermodal chain — every dray,
//  every line-haul, every ramp lift — on one screen, so the shipper can see
//  which leg is actually moving, which seam is next, and what the move costs.
//
//  Verbatim port of 05 Rail/Light-SVG/009 Rail Intermodal Journey.svg (Light + Dark).
//
//  ── ARCHETYPE · TIMELINE (multi-leg journey) ───────────────────────────────
//  Not DETAIL. An intermodal move is a CHAIN with a mode change at every seam:
//  dray -> ramp -> rail line-haul -> ramp -> dray. The SVG draws that chain
//  twice on purpose and this port keeps both faces:
//    · the CHAIN BAND (spatial) — ordered stops, per-leg mode colour, the live
//      container fix riding the active leg;
//    · the JOURNEY LEDGER (temporal + financial) — one spine, one row per real
//      segment with its real timestamps and rate, and a SEAM row for every real
//      intermodal_transfers row that joins two legs, carrying its facility,
//      dwell and lift cost.
//  A detail card cannot express a mode change. A board cannot express order.
//  Only a timeline does both, which is why the SVG's spine is the load-bearing
//  element and the cost roll-up hangs off its foot.
//
//  ── WIRING MANIFEST (every line re-confirmed in the real router this fire) ──
//   CHAIN BAND + LEDGER rows + container caption
//     intermodal.getIntermodalShipmentDetail  EXISTS intermodal.ts:537 (query)
//       in  { id: Int }
//       out { ...intermodal_shipments row, segments[], transfers[], containers[] } | null
//   LIVE fix · active segment · next-ramp ETA · ramp dwell · streamflow flag
//     intermodal.getIntermodalTracking        EXISTS intermodal.ts:747 (query)
//       in  { intermodalShipmentId: Int }
//       out { segments[], containers[], currentMode, activeSegmentId,
//             nextRampEta, rampDwell, floodImpact }
//       TRAP: on the no-db and UNOWNED paths (intermodal.ts:751 and :756) it
//             returns ONLY { segments, containers, currentMode } — the other
//             four keys are ABSENT, not null. Every one of them is Optional in
//             Tracking009 below or the decode would hard-throw on exactly the
//             tenant-gate case this screen must survive.
//   COST roll-up + the "Cost detail" sheet
//     intermodal.getIntermodalCostBreakdown   EXISTS intermodal.ts:802 (query)
//       out { intermodalNumber, segments[{legNumber,mode,rate,status}],
//             transfers[{transferType,cost,facilityName}], totalSegmentCost,
//             totalTransferCost, grandTotal, currency } | null
//       NOTE: `currency` is HARDCODED "USD" server-side (intermodal.ts:844).
//             It is NOT live multi-currency. The screen labels the roll-up with
//             that server-fixed code and cross-checks it against the shipment
//             row's real `currency` column, flagging a disagreement rather than
//             implying a conversion that never happened.
//   Resolve a journey when the caller passes no id (shipper's own tenant only)
//     intermodal.getIntermodalShipments       EXISTS intermodal.ts:504 (query)
//   NOT WIRED, deliberately:
//     intermodal.advanceSegment               EXISTS intermodal.ts:561 (mutation)
//       The rail<->truck seam advance is a CARRIER/DISPATCH act. This SVG draws
//       no advance affordance on the shipper vantage and the shipper must not
//       be able to declare a leg complete. Left off the screen entirely.
//     intermodal.rebookingOptions             EXISTS intermodal.ts:891 (query)
//       Returns two options whose `etaDeltaHrs` (12 / 6), option titles and
//       tradeoff strings are HARDCODED server constants (intermodal.ts:918-937).
//       Dressing those as a savings claim would be fabrication. Not called.
//     esangCoach.forScreen                    EXISTS esangCoach.ts:264 (query)
//       WRONG ENTITY for this screen — its `screen` input is a DRIVER-only enum
//       (esangCoach.ts:112: home|trips|earnings|tax|dvir|availability|missions|
//       badges|referrals|zeun|haul|active-trip; no shipper or intermodal key) and
//       it returns a single <=80-char in-cab driver tip {mode,tip,linkRoute,
//       confidence,generatedAt}. Calling it would 400 on the enum or return the
//       wrong entity. The RUN PLAN card is therefore computed from the decoded
//       tracking + cost payload and says so on screen (RULE-BASED tag).
//       Named gap + proposed TS shape are in the fire report.
//   STALE HEADERS KILLED: the replaced mockup cited intermodal.ts:161 / :269 /
//   :295 for these three procedures. All three line numbers are wrong; the SVG
//   <desc> repeats them and is also wrong. The real router wins.
//
//  DB WRITES / AUDIT / SOCKETS: NONE. Every call on this screen is a `.query`.
//  This screen writes no DB row, appends no `blockchainAuditTrail` row (the only
//  intermodal procedure that does is applyModeChoice, intermodal.ts:720, which is
//  not called here) and broadcasts no `WS_EVENTS.*` (the INTERMODAL_* events at
//  _core/websocket.ts:1798-1806 are emitted by carrier-side writes, never by a
//  read). Freshness comes from pull-to-refresh and the explicit live-fix CTA.
//
//  RBAC: protectedProcedure on all four calls, tenant-gated by
//  `loadOwnedShipment` (intermodal.ts) — shipper-of-record OR same companyId OR
//  ADMIN/SUPER_ADMIN. An unowned id reads as honest-empty (null / []), never as
//  another tenant's freight. The screen renders that as "no journey on this id".
//
//  transportMode = rail. The two dray legs are truck-mode CHILDREN of the same
//  chain — one screen, not a truck fork.
//  COUNTRY IS CONTENT: the regulator band (STB / FRA · Transport Canada Rail ·
//  ARTF / SICT), the ramp free-time regime (US + CA 48h vs MX 24h) and the border
//  authority (CBP · CBSA · Aduanas-VUCEM) all render from JourneyRegime009,
//  selected by the shipment's REAL `currency` column (USD | CAD | MXN). That is
//  a derivation, not a country field: `intermodal_shipments` carries no country
//  column at all (drizzle/schema.ts). The screen states the derivation on the
//  band itself and the gap is filed in the report.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(10m) for the chain band, the
//  journey ledger and the cost roll-up — the last decoded payload keeps
//  rendering when a refresh fails, and the monospaced 10pt staleness line in the
//  header right register names its age and flips to Brand.warning past 10m or
//  the moment a refresh errors while stale data is on screen. Cached, live and
//  failed states are always visibly distinct — and so is OFFLINE, which outranks
//  all three: when OfflineReachabilityHub reports no reachability the register
//  reads "OFFLINE · CACHED NM AGO", a warning band above the chain says the whole
//  screen is frozen, and a COLD offline entry says there is no cached chain at
//  all instead of rendering an empty state that reads as "this journey does not
//  exist". Stale means old; offline means unrefreshable. NOTHING here can queue: the six
//  offline-eligible paths (Services/EusoTripAPI.swift:1684 — hos.changeStatus,
//  messages.sendMessage, pod.submitPOD, loadLifecycle.executeTransition,
//  drivers.acceptLoad, location.telemetry.geofenceEvent) contain no rail or
//  intermodal path, so the live-fix CTA disables with an explicit stated reason
//  instead of pretending to enqueue. This screen is read-only: it moves no money
//  and commits no award, so there is nothing to gate ONLINE_ONLY beyond the read.
//
//  HOW THIS MAKES THE JOB EASIER: the shipper stops phoning two drayage desks
//  and a ramp to find out where the box is — the moving leg, the next lift and
//  the door-to-door number are one screen, in one order.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import Foundation
import SwiftUI

// MARK: - Decimal parse boundary
//
// MySQL `decimal` columns (rate, transferCost, dwellTimeHours, totalRate,
// weightKg) serialize as JSON STRINGS today. A future server change to emit
// them as numbers must not silently blank a figure, so every one decodes
// through this string-OR-number box.

private struct Decimal009: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else { value = nil }
    }
}

// MARK: - Decoded server shapes
//
// Field-for-field against drizzle/schema.ts. Every field Optional except `id`.

private struct Geo009: Decodable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

/// intermodal_segments row.
private struct Segment009: Decodable, Identifiable {
    let id: Int
    let intermodalShipmentId: Int?
    let legNumber: Int?
    let mode: String?                  // "TRUCK" | "RAIL" | "VESSEL"
    let truckShipmentId: Int?
    let railShipmentId: Int?
    let vesselShipmentId: Int?
    let originDescription: String?
    let destinationDescription: String?
    let carrierId: Int?
    let rate: Decimal009?
    let estimatedHours: Decimal009?
    let actualHours: Decimal009?
    let status: String?                // pending|booked|in_transit|completed|cancelled
    let departedAt: String?
    let arrivedAt: String?
}

/// intermodal_transfers row — the mode-change seam.
private struct Transfer009: Decodable, Identifiable {
    let id: Int
    let intermodalShipmentId: Int?
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let transferType: String?          // truck_to_rail | rail_to_truck | ...
    let facilityName: String?
    let facilityType: String?          // intermodal_ramp | rail_yard | ...
    let location: Geo009?
    let scheduledAt: String?
    let startedAt: String?
    let completedAt: String?
    let dwellTimeHours: Decimal009?
    let transferCost: Decimal009?
    let status: String?                // scheduled|in_progress|completed|delayed|cancelled
    let notes: String?
}

/// intermodal_containers row — carries the live fix.
private struct Container009: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?
    let sealNumber: String?
    let weightKg: Decimal009?
    let currentMode: String?
    let currentSegmentId: Int?
    let currentLocation: Geo009?
    let status: String?
    let updatedAt: String?
}

/// getIntermodalShipmentDetail — the shipment row spread + three nested arrays.
private struct Journey009: Decodable {
    let id: Int
    let intermodalNumber: String?
    let shipperId: Int?
    let originType: String?
    let destinationType: String?
    let originLocation: Geo009?
    let destinationLocation: Geo009?
    let commodity: String?
    let hazmatClass: String?
    let totalWeight: Decimal009?
    let numberOfSegments: Int?
    let status: String?
    let totalRate: Decimal009?
    let currency: String?
    let estimatedTransitDays: Int?
    let actualTransitDays: Int?
    let companyId: Int?
    let segments: [Segment009]?
    let transfers: [Transfer009]?
    let containers: [Container009]?
}

/// getIntermodalShipments — used only to resolve a journey when no id is passed.
private struct JourneyPage009: Decodable {
    let shipments: [Journey009]?
    let total: Int?
}

/// getIntermodalTracking · floodImpact.flags[]
private struct FloodFlag009: Decodable, Identifiable {
    let transferId: Int
    let facilityName: String?
    let facilityType: String?
    let floodSeverity: String?
    let floodHeadline: String?
    let precipAccumulationIn: Double?
    let streamflowRising: Bool?
    let dwellDeltaHours: Double?
    var id: Int { transferId }
}

/// getIntermodalTracking · floodImpact (USGS streamflow at the next crossing).
private struct FloodImpact009: Decodable {
    let available: Bool?
    let enterprise: Bool?
    let reason: String?
    let source: String?
    let computedAt: String?
    let nextRampTransferId: Int?
    let scheduledRampEta: String?
    let nextRampEta: String?
    let scheduledRampDwellHours: Double?
    let rampDwell: Double?
    let dwellDeltaHours: Double?
    let streamflowRisk: Bool?
    let flags: [FloodFlag009]?
}

/// getIntermodalTracking return.
private struct Tracking009: Decodable {
    let segments: [Segment009]?
    let containers: [Container009]?
    let currentMode: String?
    let activeSegmentId: Int?
    let nextRampEta: String?
    let rampDwell: Double?
    let floodImpact: FloodImpact009?
}

/// getIntermodalCostBreakdown · segments[]
private struct CostLeg009: Decodable, Identifiable {
    let legNumber: Int?
    let mode: String?
    let rate: Double?
    let status: String?
    var id: String { "leg-\(legNumber ?? 0)-\(mode ?? "")" }
}

/// getIntermodalCostBreakdown · transfers[]
private struct CostLift009: Decodable, Identifiable {
    let transferType: String?
    let cost: Double?
    let facilityName: String?
    var id: String { "lift-\(transferType ?? "")-\(facilityName ?? "")-\(cost ?? 0)" }
}

/// getIntermodalCostBreakdown return.
private struct Cost009: Decodable {
    let intermodalNumber: String?
    let segments: [CostLeg009]?
    let transfers: [CostLift009]?
    let totalSegmentCost: Double?
    let totalTransferCost: Double?
    let grandTotal: Double?
    let currency: String?
}

// MARK: - Regime band (country is content, never a file fork)
//
// `intermodal_shipments` has NO country column (drizzle/schema.ts). The only
// jurisdiction-bearing real column on the row is `currency`, so the band is
// selected from it and the screen SAYS SO on the band. Regime content — the
// regulator, the ramp free-time clock and the border authority — is constant
// per country, not server data.

private enum JourneyRegime009: String {
    case us = "USD"
    case ca = "CAD"
    case mx = "MXN"

    static func from(currency: String?) -> JourneyRegime009 {
        JourneyRegime009(rawValue: (currency ?? "USD").uppercased()) ?? .us
    }

    /// Rail regulator whose rules govern the line-haul leg.
    var regulator: String {
        switch self {
        case .us: return "STB · FRA"
        case .ca: return "Transport Canada Rail"
        case .mx: return "ARTF · SICT"
        }
    }

    /// Dangerous-goods rulebook cited on a hazmat chain.
    var dangerousGoods: String {
        switch self {
        case .us: return "49 CFR"
        case .ca: return "TDG"
        case .mx: return "NOM"
        }
    }

    /// Ramp free time before storage starts running on the box.
    var freeTimeHours: Int {
        switch self {
        case .us, .ca: return 48
        case .mx:      return 24
        }
    }

    /// Border authority for a cross-border chain.
    var borderAuthority: String {
        switch self {
        case .us: return "CBP"
        case .ca: return "CBSA"
        case .mx: return "Aduanas · VUCEM"
        }
    }
}

// MARK: - Chain view-model (built only from decoded rows)

private enum LegState009 { case done, active, pending, stopped }

private struct ChainLeg009: Identifiable {
    let id: Int
    let legNumber: Int
    let mode: String
    let kicker: String        // "LEG 2 · LINE-HAUL · RAIL"
    let lane: String
    let subline: String
    let statusWord: String
    let state: LegState009
    let rate: Double?
}

private struct ChainSeam009: Identifiable {
    let id: Int
    let kicker: String        // "SEAM · TRUCK -> RAIL"
    let facility: String
    let subline: String
    let statusWord: String
    let state: LegState009
    let cost: Double?
    let floodNote: String?
}

private enum ChainRow009: Identifiable {
    case leg(ChainLeg009)
    case seam(ChainSeam009)
    var id: String {
        switch self {
        case .leg(let l):  return "L\(l.id)"
        case .seam(let s): return "S\(s.id)"
        }
    }
}

private struct ChainPoint009 {
    let lat: Double
    let lng: Double
}

/// One node on the spatial band: origin, each seam facility, destination.
private struct ChainStop009: Identifiable {
    let id: Int               // index
    let label: String
    let point: ChainPoint009?
    let state: LegState009
}

/// One drawn edge on the spatial band.
private struct ChainEdge009: Identifiable {
    let id: Int               // segment id
    let mode: String
    let state: LegState009
}

// MARK: - Screen root

struct RailIntermodalJourney_009: View {
    let theme: Theme.Palette
    let intermodalShipmentId: Int

    init(theme: Theme.Palette = Theme.dark, intermodalShipmentId: Int = 0) {
        self.theme = theme
        self.intermodalShipmentId = intermodalShipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            RailIntermodalJourneyBody009(requestedId: intermodalShipmentId)
        } nav: {
            // Rail SHIPPER band (001-010) — mirrors Views/Rail/002_RailShipmentDetail.swift
            // so a rail load reads as the SAME Shipper app, never a separate product.
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailIntermodalJourneyBody009: View {
    @Environment(\.palette) private var palette
    /// READ_CACHED(10m) is only half an honesty claim on its own: an age stamp
    /// can say the chain is old, never that the device cannot refresh it at all.
    /// This screen is read-only — nothing to gate, nothing to queue — so the
    /// reachability read exists purely to make offline visibly distinct from
    /// merely stale.
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    let requestedId: Int

    @State private var journey: Journey009? = nil
    @State private var tracking: Tracking009? = nil
    @State private var cost: Cost009? = nil
    @State private var resolvedId: Int = 0

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var lastSyncedAt: Date? = nil
    @State private var refreshingFix = false
    @State private var fixError: String? = nil
    @State private var tick = Date()

    /// Cached reads stay on screen for 10 minutes before the header line warns.
    private let cacheWindow: TimeInterval = 600

    // MARK: Derived — ordering

    private var segments: [Segment009] {
        // Prefer the tracking copy (fresher: it is re-pulled by the live CTA),
        // fall back to the detail copy. Sort locally; never trust server order.
        let rows = (tracking?.segments?.isEmpty == false ? tracking?.segments : journey?.segments) ?? []
        return rows.sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) }
    }

    private var transfers: [Transfer009] {
        (journey?.transfers ?? []).sorted { ($0.scheduledAt ?? "") < ($1.scheduledAt ?? "") }
    }

    private var containers: [Container009] {
        (tracking?.containers?.isEmpty == false ? tracking?.containers : journey?.containers) ?? []
    }

    private var primaryContainer: Container009? {
        containers.first { $0.currentLocation?.lat != nil } ?? containers.first
    }

    private var activeSegment: Segment009? {
        if let id = tracking?.activeSegmentId, let s = segments.first(where: { $0.id == id }) { return s }
        return segments.first { ["in_transit", "booked"].contains(($0.status ?? "").lowercased()) }
    }

    private var railSegment: Segment009? {
        segments.first { ($0.mode ?? "").uppercased() == "RAIL" }
    }

    private var regime: JourneyRegime009 { .from(currency: journey?.currency) }

    /// Cost roll-up currency is server-fixed. Kept separate from the shipment
    /// row's own currency so a disagreement is visible instead of silent.
    private var ledgerCurrency: String { (cost?.currency ?? journey?.currency ?? "USD").uppercased() }
    private var currencyDisagrees: Bool {
        guard let a = cost?.currency?.uppercased(), let b = journey?.currency?.uppercased() else { return false }
        return a != b
    }

    private func legState(_ raw: String?) -> LegState009 {
        switch (raw ?? "").lowercased() {
        case "completed", "done", "delivered":     return .done
        case "in_transit", "in_progress", "booked": return .active
        case "cancelled", "delayed":                return .stopped
        default:                                    return .pending
        }
    }

    private func modeWord(_ mode: String?) -> String {
        switch (mode ?? "").uppercased() {
        case "RAIL":   return "RAIL"
        case "VESSEL": return "VESSEL"
        case "TRUCK":  return "TRUCK"
        default:       return (mode ?? "—").uppercased()
        }
    }

    /// A TRUCK leg at either end of a multi-leg chain is a dray; the middle of
    /// the chain is line-haul. Derived from the real `mode` + position only.
    private func roleWord(_ mode: String?, index: Int, count: Int) -> String {
        let m = (mode ?? "").uppercased()
        if m == "TRUCK" && count > 1 && (index == 0 || index == count - 1) { return "DRAY" }
        if count > 1 && index > 0 && index < count - 1 { return "LINE-HAUL" }
        if m == "RAIL" || m == "VESSEL" { return "LINE-HAUL" }
        return "HAUL"
    }

    private func transferWord(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "truck_to_rail":   return "TRUCK → RAIL"
        case "rail_to_truck":   return "RAIL → TRUCK"
        case "truck_to_vessel": return "TRUCK → VESSEL"
        case "vessel_to_truck": return "VESSEL → TRUCK"
        case "rail_to_vessel":  return "RAIL → VESSEL"
        case "vessel_to_rail":  return "VESSEL → RAIL"
        default: return (raw ?? "TRANSFER").replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    private func facilityWord(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: Derived — the ledger rows (legs interleaved with their real seams)

    private var chainRows: [ChainRow009] {
        let segs = segments
        guard !segs.isEmpty else { return [] }
        var rows: [ChainRow009] = []

        for (idx, s) in segs.enumerated() {
            let role = roleWord(s.mode, index: idx, count: segs.count)
            let leg = ChainLeg009(
                id: s.id,
                legNumber: s.legNumber ?? (idx + 1),
                mode: modeWord(s.mode),
                kicker: "LEG \(s.legNumber ?? (idx + 1)) · \(role) · \(modeWord(s.mode))",
                lane: laneLabel(s),
                subline: legSubline(s),
                statusWord: (s.status ?? "pending").replacingOccurrences(of: "_", with: " ").uppercased(),
                state: legState(s.status),
                rate: s.rate?.value
            )
            rows.append(.leg(leg))

            // The real seam that departs this leg, if the chain records one.
            if let t = transfers.first(where: { $0.fromSegmentId == s.id }) {
                rows.append(.seam(seam(t)))
            }
        }
        return rows
    }

    private func laneLabel(_ s: Segment009) -> String {
        let o = nonEmpty(s.originDescription)
        let d = nonEmpty(s.destinationDescription)
        switch (o, d) {
        case let (o?, d?): return "\(o) → \(d)"
        case let (o?, _):  return o
        case let (_, d?):  return d
        default:           return "Lane not described"
        }
    }

    private func legSubline(_ s: Segment009) -> String {
        var bits: [String] = []
        if let dep = stamp(s.departedAt) { bits.append("dep \(dep)") }
        if let arr = stamp(s.arrivedAt)  { bits.append("arr \(arr)") }
        if bits.isEmpty, let hrs = s.estimatedHours?.value { bits.append("est \(trimNumber(hrs))h") }
        if let rid = s.railShipmentId    { bits.append("rail #\(rid)") }
        if let tid = s.truckShipmentId   { bits.append("truck #\(tid)") }
        if bits.isEmpty { bits.append("no timestamps yet") }
        return bits.joined(separator: " · ")
    }

    private func seam(_ t: Transfer009) -> ChainSeam009 {
        var bits: [String] = []
        if let f = facilityWord(t.facilityType) { bits.append(f) }
        if let s = stamp(t.completedAt) { bits.append("lifted \(s)") }
        else if let s = stamp(t.startedAt) { bits.append("started \(s)") }
        else if let s = stamp(t.scheduledAt) { bits.append("sched \(s)") }
        if let d = t.dwellTimeHours?.value { bits.append("dwell \(trimNumber(d))h of \(regime.freeTimeHours)h free") }
        if bits.isEmpty { bits.append("no lift timestamps yet") }

        // Honest streamflow note — only when the server flagged THIS crossing.
        var flood: String? = nil
        if let flag = tracking?.floodImpact?.flags?.first(where: { $0.transferId == t.id }),
           flag.streamflowRising == true, let delta = flag.dwellDeltaHours, delta > 0 {
            let head = nonEmpty(flag.floodHeadline) ?? "rising gage at this crossing"
            flood = "Streamflow · \(head) · +\(trimNumber(delta))h dwell"
        }

        return ChainSeam009(
            id: t.id,
            kicker: "SEAM · \(transferWord(t.transferType))",
            facility: nonEmpty(t.facilityName) ?? "Facility not named",
            subline: bits.joined(separator: " · "),
            statusWord: (t.status ?? "scheduled").replacingOccurrences(of: "_", with: " ").uppercased(),
            state: legState(t.status),
            cost: t.transferCost?.value,
            floodNote: flood
        )
    }

    // MARK: Derived — the spatial band

    private func point(_ g: Geo009?) -> ChainPoint009? {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: g?.lat,
            longitude: g?.lng
        ) else { return nil }
        return ChainPoint009(lat: coordinate.latitude, lng: coordinate.longitude)
    }

    /// Ordered stops: origin, every seam facility in chain order, destination.
    private var chainStops: [ChainStop009] {
        let segs = segments
        guard !segs.isEmpty else { return [] }
        var out: [ChainStop009] = []

        out.append(ChainStop009(
            id: 0,
            label: nonEmpty(journey?.originLocation?.description)
                ?? nonEmpty(segs.first?.originDescription) ?? "Origin",
            point: point(journey?.originLocation),
            state: .done))

        for (idx, s) in segs.enumerated() where idx < segs.count - 1 {
            let t = transfers.first(where: { $0.fromSegmentId == s.id })
            out.append(ChainStop009(
                id: idx + 1,
                label: nonEmpty(t?.facilityName)
                    ?? nonEmpty(s.destinationDescription) ?? "Ramp \(idx + 1)",
                point: point(t?.location),
                state: legState(t?.status)))
        }

        out.append(ChainStop009(
            id: segs.count,
            label: nonEmpty(journey?.destinationLocation?.description)
                ?? nonEmpty(segs.last?.destinationDescription) ?? "Destination",
            point: point(journey?.destinationLocation),
            state: legState(segs.last?.status)))

        return out
    }

    private var chainEdges: [ChainEdge009] {
        segments.map { ChainEdge009(id: $0.id, mode: modeWord($0.mode), state: legState($0.status)) }
    }

    // A container fix is observation evidence, not permission to place the
    // container between two schematic chain nodes. The live glyph remains off
    // the band until the server returns an exact segment projection.

    // MARK: Derived — copy

    private var routeTitle: String {
        let stops = chainStops
        if let a = stops.first?.label, let b = stops.last?.label, stops.count >= 2 {
            return "\(shortPlace(a)) → \(shortPlace(b))"
        }
        if let n = nonEmpty(journey?.intermodalNumber) { return n }
        if loading { return "Loading journey…" }
        return "Intermodal journey"
    }

    private func shortPlace(_ s: String) -> String {
        // First comma-separated component keeps the 28pt title on one line
        // without inventing a name.
        s.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? s
    }

    private var containerCaption: String {
        guard let c = primaryContainer else { return loading ? "…" : "NO CONTAINER" }
        let n = nonEmpty(c.containerNumber) ?? "CONTAINER"
        let t = nonEmpty(c.containerType).map { " · \($0.uppercased())" } ?? ""
        return n + t
    }

    private var isMoving: Bool { activeSegment != nil }

    private var statusPillText: String {
        if loading && journey == nil { return "LOADING" }
        guard journey != nil else { return "NO DATA" }
        if let m = nonEmpty(tracking?.currentMode) { return "LIVE · \(m.uppercased())" }
        if isMoving { return "IN MOTION" }
        return (journey?.status ?? "planning").replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var statusPillColor: Color {
        if journey == nil { return palette.textTertiary }
        if tracking?.currentMode != nil { return Brand.success }
        if isMoving { return Brand.info }
        return palette.textTertiary
    }

    /// "DOOR-TO-DOOR · 2 DRAYS · 1 LINE-HAUL · 2 LIFTS" — every count real.
    private var verdictKicker: String {
        let segs = segments
        guard !segs.isEmpty else { return "DOOR-TO-DOOR CHAIN" }
        var drays = 0
        var linehauls = 0
        for (i, s) in segs.enumerated() {
            if roleWord(s.mode, index: i, count: segs.count) == "DRAY" { drays += 1 } else { linehauls += 1 }
        }
        var parts = ["DOOR-TO-DOOR"]
        if drays > 0 { parts.append("\(drays) DRAY\(drays == 1 ? "" : "S")") }
        if linehauls > 0 { parts.append("\(linehauls) LINE-HAUL\(linehauls == 1 ? "" : "S")") }
        let lifts = transfers.count
        parts.append("\(lifts) LIFT\(lifts == 1 ? "" : "S")")
        return parts.joined(separator: " · ")
    }

    private var verdictLine: String {
        guard journey != nil else {
            return loading ? "Pulling the chain…" : "No intermodal journey on this id."
        }
        guard let a = activeSegment else {
            let st = (journey?.status ?? "planning").replacingOccurrences(of: "_", with: " ")
            return "Chain \(st) · no leg in motion"
        }
        let head = "\(modeWord(a.mode).capitalized) leg on the road"
        if let eta = stamp(tracking?.nextRampEta ?? tracking?.floodImpact?.nextRampEta),
           let name = nextRampName {
            return "\(head) · \(name) \(eta)"
        }
        if let eta = stamp(tracking?.nextRampEta) { return "\(head) · next ramp \(eta)" }
        return "\(head) · next ramp time not scheduled"
    }

    private var nextRampName: String? {
        guard let id = tracking?.floodImpact?.nextRampTransferId,
              let t = transfers.first(where: { $0.id == id }) else { return nil }
        return nonEmpty(t.facilityName)
    }

    // MARK: Derived — run plan (computed, not model-generated; every value real)

    private var runPlanHeadline: String {
        guard journey != nil else { return "Nothing to plan yet" }
        if let flood = tracking?.floodImpact, flood.streamflowRisk == true,
           let delta = flood.dwellDeltaHours, delta > 0 {
            let where_ = nextRampName ?? "the next ramp"
            return "Rising water at \(where_) — build in \(trimNumber(delta))h of extra dwell"
        }
        guard let a = activeSegment else {
            if let next = segments.first(where: { legState($0.status) == .pending }) {
                return "Next up is leg \(next.legNumber ?? 0) · \(modeWord(next.mode).lowercased())"
            }
            return "Every leg on this chain is closed out"
        }
        if let eta = stamp(tracking?.nextRampEta), let name = nextRampName {
            return "\(modeWord(a.mode).capitalized) leg holds \(eta) — stage \(name) now"
        }
        return "\(modeWord(a.mode).capitalized) leg is the one to chase"
    }

    /// The single number on the card. Ramp dwell is a REAL column
    /// (intermodal_transfers.dwellTimeHours), pushed out only by a real gage.
    private var runPlanNumber: String {
        if let d = tracking?.rampDwell ?? tracking?.floodImpact?.rampDwell {
            return "RAMP DWELL \(trimNumber(d))H"
        }
        if let lifts = cost?.totalTransferCost, lifts > 0 {
            return "LIFTS \(money(lifts, ledgerCurrency))"
        }
        return "DWELL NOT SCHEDULED"
    }

    private var runPlanNote: String {
        var bits: [String] = []
        bits.append("Free time \(regime.freeTimeHours)h · \(regime.regulator)")
        if let n = journey?.hazmatClass, !n.isEmpty { bits.append("\(regime.dangerousGoods) class \(n)") }
        return bits.joined(separator: " · ")
    }

    private var runPlanDetail: String {
        guard let flood = tracking?.floodImpact else {
            return "Derived from the live segment and ramp payload. A shipper-scope coach model is not wired on this route yet."
        }
        if flood.available == true, flood.streamflowRisk == true {
            let n = flood.flags?.filter { $0.streamflowRising == true }.count ?? 0
            return "USGS streamflow flagged \(n) crossing\(n == 1 ? "" : "s"). Ramp ETA and dwell below already carry that push-out."
        }
        let why = (flood.reason ?? "ok").replacingOccurrences(of: "_", with: " ")
        return "No streamflow risk on the next crossing (\(why)). Ramp ETA and dwell are the scheduled values, untouched."
    }

    // MARK: Derived — staleness (offline honesty line)

    private var syncAgeSeconds: TimeInterval? {
        guard let t = lastSyncedAt else { return nil }
        return max(0, tick.timeIntervalSince(t))
    }

    private var isStale: Bool {
        if !reach.isOnline { return true }
        guard let age = syncAgeSeconds else { return journey != nil }
        return age > cacheWindow || (loadError != nil && journey != nil)
    }

    private var syncLine: String {
        // Offline outranks every other register state: "CACHED 3M AGO" implies
        // the next pull will refresh it. Offline says it will not.
        if !reach.isOnline {
            guard let age = syncAgeSeconds else { return "OFFLINE · NEVER SYNCED" }
            return "OFFLINE · CACHED \(ageWord(age))"
        }
        if loading && journey == nil { return "SYNCING" }
        guard let age = syncAgeSeconds else { return "NEVER SYNCED" }
        if loadError != nil { return "CACHED \(ageWord(age)) · REFRESH FAILED" }
        if age > cacheWindow { return "CACHED \(ageWord(age))" }
        if age < 45 { return "LIVE · JUST NOW" }
        return "LIVE · \(ageWord(age))"
    }

    private func ageWord(_ secs: TimeInterval) -> String {
        if secs < 60 { return "\(Int(secs))S AGO" }
        if secs < 3600 { return "\(Int(secs / 60))M AGO" }
        if secs < 86_400 { return "\(Int(secs / 3600))H AGO" }
        return "\(Int(secs / 86_400))D AGO"
    }

    /// Offline is a property of the DEVICE, not of the chain, so it gets its own
    /// band rather than being folded into the age stamp. Read-only screen: this
    /// gates nothing, it only stops a frozen chain from reading as a live one.
    @ViewBuilder
    private var offlineBanner: some View {
        if !reach.isOnline && journey != nil {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.warning)
                Text("Offline — the chain, the live fix and the cost roll-up below are the last snapshot this device pulled\(syncAgeSeconds.map { " (\(ageWord($0).lowercased()))" } ?? ""). None of it is updating.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                offlineBanner

                if !reach.isOnline && journey == nil {
                    // Cold and offline: no last-good chain in memory and no way
                    // to fetch one. Naming that beats an empty state that reads
                    // as "this journey does not exist".
                    EusoEmptyState(
                        icon: Image(systemName: "wifi.slash"),
                        title: "Offline — no chain cached",
                        subtitle: "This journey has not been read on this device yet, and the chain, tracking and cost roll-up all need the network. Reconnect to pull it."
                    )
                } else if loading && journey == nil {
                    LifecycleCard {
                        Text("Loading the intermodal chain…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if journey == nil {
                    emptyJourney
                } else {
                    chainBandCard
                    verdictBlock
                    ledgerSection
                    runPlanCard
                    ctaRow
                    regimeFootnote
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .task {
            // Drives the staleness line only — no data motion, no timer-faked fix.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                tick = Date()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: Space.s2) {
                EusoTripEyebrow(verbatim: "SHIPPER · RAIL · INTERMODAL JOURNEY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(containerCaption)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    // Honesty law: cached / live / failed are visibly distinct.
                    Text(syncLine)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isStale ? Brand.warning : palette.textTertiary)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(routeTitle)
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.55)
                Spacer(minLength: Space.s2)
                HStack(spacing: 6) {
                    Circle().fill(statusPillColor).frame(width: 6, height: 6)
                    Text(statusPillText)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(statusPillColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(statusPillColor.opacity(0.16)))
            }
            if let err = loadError, journey != nil {
                Text("Last refresh failed · \(err)")
                    .font(EType.caption).foregroundStyle(Brand.warning).lineLimit(2)
            }
        }
    }

    private var emptyJourney: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            }
            EusoEmptyState(
                icon: Image(systemName: "point.topleft.down.to.point.bottomright.curvepath"),
                title: "No intermodal journey here",
                subtitle: "This id has no chain on your account. Intermodal moves you are the shipper of record on — or that belong to your company — show every leg here the moment they are booked."
            )
        }
    }

    // MARK: Chain band (spatial face of the timeline)

    private var chainBandCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            JourneyChainBand009(
                stops: chainStops,
                edges: chainEdges,
                liveLabel: liveChipText,
                liveIsReal: false,
                etaLabel: etaChipText,
                telemetryLabel: telemetryPillText
            )
            .frame(height: 168)

            HStack(spacing: Space.s4) {
                legendDot(Brand.success, "Leg closed")
                legendDot(Brand.blue, "Leg moving")
                legendDot(palette.textTertiary, "Leg scheduled")
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
        }
    }

    private var liveChipText: String {
        guard let c = primaryContainer else { return "NO CONTAINER ON CHAIN" }
        if let where_ = nonEmpty(c.currentLocation?.description) {
            let mode = nonEmpty(tracking?.currentMode ?? c.currentMode).map { "\($0.uppercased()) · " } ?? ""
            return "LIVE · \(mode)\(where_.uppercased())"
        }
        if point(c.currentLocation) != nil { return "LIVE · FIX REPORTED · PROJECTION PENDING" }
        return "POSITION NOT REPORTED"
    }

    private var etaChipText: String {
        if let eta = stamp(tracking?.nextRampEta ?? tracking?.floodImpact?.nextRampEta) { return "RAMP \(eta)" }
        if let d = journey?.estimatedTransitDays { return "\(d)D TRANSIT" }
        return "RAMP ETA —"
    }

    private var telemetryPillText: String {
        let segs = segments
        guard let a = activeSegment, let n = a.legNumber else {
            if segs.isEmpty { return "NO LEGS BOOKED" }
            return "\(segs.count) LEGS · NONE MOVING"
        }
        let total = journey?.numberOfSegments ?? segs.count
        let box = nonEmpty(primaryContainer?.containerNumber).map { " · \($0)" } ?? ""
        return "LEG \(n) OF \(total) · \(modeWord(a.mode))\(box)"
    }

    // MARK: Verdict

    private var verdictBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verdictKicker)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(verdictLine)
                .font(.system(size: 17, weight: .bold)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Ledger (temporal + financial face of the timeline)

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("JOURNEY & COST · \(ledgerCurrency)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text(cost == nil ? "cost pending" : "\(chainRows.count) rows")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            if chainRows.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "arrow.triangle.branch"),
                    title: "No legs on this chain yet",
                    subtitle: "Segments appear the moment the intermodal booking is written."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(chainRows.enumerated()), id: \.element.id) { idx, row in
                        Group {
                            switch row {
                            case .leg(let l):  legRow(l)
                            case .seam(let s): seamRow(s)
                            }
                        }
                        .background(rowSpine(isFirst: idx == 0, isLast: idx == chainRows.count - 1))
                        if idx < chainRows.count - 1 {
                            Divider().padding(.leading, 40).overlay(palette.borderFaint)
                        }
                    }
                    rollUpStrip
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    /// The continuous spine, drawn per row so it starts at the first node and
    /// stops at the last — no fixed-height guessing.
    private func rowSpine(isFirst: Bool, isLast: Bool) -> some View {
        GeometryReader { g in
            Path { p in
                let x: CGFloat = 11
                let top: CGFloat = isFirst ? 12 : 0
                let bottom: CGFloat = isLast ? 12 : g.size.height
                if bottom > top {
                    p.move(to: CGPoint(x: x, y: top))
                    p.addLine(to: CGPoint(x: x, y: bottom))
                }
            }
            .stroke(palette.borderFaint, lineWidth: 2)
        }
    }

    private func legRow(_ l: ChainLeg009) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            nodeGlyph(l.state).frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(l.kicker)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Text(l.lane)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(l.subline)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                statusWord(l.statusWord, state: l.state)
                Text(l.rate == nil ? "rate —" : money(l.rate, ledgerCurrency))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(l.rate == nil ? palette.textTertiary : palette.textPrimary)
            }
        }
        .padding(.vertical, Space.s2)
    }

    private func seamRow(_ s: ChainSeam009) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            seamGlyph(s.state).frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.kicker)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.info)
                Text(s.facility)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.subline)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let flood = s.floodNote {
                    Text(flood)
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                statusWord(s.statusWord, state: s.state)
                Text(s.cost == nil ? "lift —" : money(s.cost, ledgerCurrency))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(s.cost == nil ? palette.textTertiary : palette.textPrimary)
            }
        }
        .padding(.vertical, Space.s2)
    }

    @ViewBuilder
    private func statusWord(_ text: String, state: LegState009) -> some View {
        switch state {
        case .active:
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(LinearGradient.primary)
        case .done:
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
        case .stopped:
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.danger)
        case .pending:
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func nodeGlyph(_ state: LegState009) -> some View {
        switch state {
        case .done:
            ZStack {
                Circle().fill(Brand.success).frame(width: 14, height: 14)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(palette.bgCard)
            }
            .frame(height: 24)
        case .active:
            ZStack {
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 18, height: 18)
                Circle().fill(Brand.blue).frame(width: 11, height: 11)
                Circle().fill(.white).frame(width: 4, height: 4)
            }
            .frame(height: 24)
        case .stopped:
            ZStack {
                Circle().fill(Brand.danger).frame(width: 14, height: 14)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(palette.bgCard)
            }
            .frame(height: 24)
        case .pending:
            Circle()
                .strokeBorder(palette.textTertiary, lineWidth: 2)
                .frame(width: 12, height: 12)
                .frame(height: 24)
        }
    }

    /// A seam is a mode change, so its node is a diamond, not a dot — the
    /// glyph itself says "something swapped here".
    private func seamGlyph(_ state: LegState009) -> some View {
        let tint: Color = {
            switch state {
            case .done:    return Brand.success
            case .active:  return Brand.info
            case .stopped: return Brand.danger
            case .pending: return palette.textTertiary
            }
        }()
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(tint, lineWidth: 1.8))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(45))
            .frame(height: 24)
    }

    private var rollUpStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(liftsLine)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: Space.s2)
                Text("DOOR-TO-DOOR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Text(cost?.grandTotal == nil ? "—" : money(cost?.grandTotal, ledgerCurrency))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
            }
            if currencyDisagrees {
                Text("Cost roll-up is priced \(ledgerCurrency) — the cost ledger fixes that currency — while the shipment row is billed \(journey?.currency?.uppercased() ?? "—"). No conversion has been applied.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Brand.blue.opacity(0.07)))
        .padding(.top, Space.s3)
    }

    private var liftsLine: String {
        let n = cost?.transfers?.count ?? transfers.count
        let sum = cost?.totalTransferCost
        let lifts = "Ramp lifts ×\(n)"
        guard let sum else { return "\(lifts) · cost pending" }
        return "\(lifts) · \(money(sum, ledgerCurrency))"
    }

    // MARK: Run plan

    private var runPlanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                    Text("E").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                }
                Text("ESANG")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("· RUN PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.info)
                Spacer(minLength: Space.s2)
                // Honest provenance: this card is computed, not model-generated.
                Text("RULE-BASED")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(runPlanHeadline)
                .font(.system(size: 15, weight: .bold)).kerning(-0.2)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
            HStack(spacing: Space.s2) {
                Text(runPlanNumber)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Brand.magenta)
                Circle().fill(palette.textTertiary).frame(width: 3, height: 3)
                Text(runPlanNote)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.top, 6)
            Text(runPlanDetail)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
        )
    }

    // MARK: CTA pair

    private var trackDisabledReason: String? {
        if railSegment == nil { return "No rail line-haul leg on this chain." }
        if resolvedId <= 0 { return "No journey resolved yet." }
        if let e = fixError { return e }
        return nil
    }

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: refreshingFix ? "Pulling fix…" : "Track rail leg",
                    action: { Task { await refreshFix() } },
                    isLoading: refreshingFix || railSegment == nil || resolvedId <= 0
                )
                .frame(maxWidth: .infinity)

                RailSecondaryActionButton(
                    title: "Cost detail",
                    sheetTitle: "Door-to-door cost · \(ledgerCurrency)",
                    lines: costSheetLines,
                    width: 148,
                    systemImage: "dollarsign.circle"
                )
            }
            if let reason = trackDisabledReason {
                Text(reason)
                    .font(EType.caption)
                    .foregroundStyle(railSegment == nil ? palette.textTertiary : Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Every line is a decoded field from getIntermodalCostBreakdown.
    private var costSheetLines: [String] {
        guard let c = cost else {
            return ["Cost breakdown has not loaded for this journey.",
                    "Pull to refresh to try the roll-up again."]
        }
        var out: [String] = []
        if let n = nonEmpty(c.intermodalNumber) { out.append("Journey \(n)") }
        for leg in (c.segments ?? []).sorted(by: { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) }) {
            let status = (leg.status ?? "pending").replacingOccurrences(of: "_", with: " ")
            out.append("Leg \(leg.legNumber ?? 0) · \(modeWord(leg.mode)) · \(money(leg.rate, ledgerCurrency)) · \(status)")
        }
        for lift in (c.transfers ?? []) {
            let f = nonEmpty(lift.facilityName) ?? "facility not named"
            out.append("Lift \(transferWord(lift.transferType)) · \(f) · \(money(lift.cost, ledgerCurrency))")
        }
        out.append("Segments subtotal \(money(c.totalSegmentCost, ledgerCurrency))")
        out.append("Transfers subtotal \(money(c.totalTransferCost, ledgerCurrency))")
        out.append("Door-to-door \(money(c.grandTotal, ledgerCurrency))")
        out.append("Priced in \(ledgerCurrency). The cost ledger fixes this roll-up's currency; it is not converted per shipment.")
        if let row = journey?.currency?.uppercased(), row != ledgerCurrency {
            out.append("Shipment row is billed \(row) — the two disagree and nothing has been converted.")
        }
        return out
    }

    // MARK: Regime footnote

    private var regimeFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REGIME · \(regime.regulator) · \(regime.borderAuthority) · \(regime.freeTimeHours)H RAMP FREE TIME")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("Band selected from the shipment's currency column (\(journey?.currency?.uppercased() ?? "—")) — intermodal_shipments carries no country column, so this is a derivation, not a country field.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s1)
    }

    // MARK: - Load

    private func load() async {
        loading = true
        loadError = nil

        // Resolve the journey id. A caller-supplied id wins; otherwise take the
        // shipper's own most recent live chain (tenant-scoped server-side).
        var id = requestedId
        if id <= 0 {
            struct ListIn: Encodable { let limit: Int }
            if let page: JourneyPage009 = try? await EusoTripAPI.shared.query(
                "intermodal.getIntermodalShipments", input: ListIn(limit: 20)) {
                let rows = page.shipments ?? []
                let live = rows.first {
                    !["delivered", "cancelled", "settled", "invoiced"].contains(($0.status ?? "").lowercased())
                }
                id = (live ?? rows.first)?.id ?? 0
            }
        }
        let journeyId = id
        resolvedId = journeyId

        guard journeyId > 0 else {
            journey = nil; tracking = nil; cost = nil
            loading = false
            return
        }

        struct DetailIn: Encodable { let id: Int }
        struct ShipmentIn: Encodable { let intermodalShipmentId: Int }

        // Parallel fan-out — one dead section degrades alone. The chain detail
        // is the only hard requirement and is NOT swallowed; tracking and cost
        // are best-effort so a cost or weather outage never blanks the journey.
        async let trackTask: Tracking009? = EusoTripAPI.shared.query(
            "intermodal.getIntermodalTracking", input: ShipmentIn(intermodalShipmentId: journeyId))
        async let costTask: Cost009? = EusoTripAPI.shared.query(
            "intermodal.getIntermodalCostBreakdown", input: ShipmentIn(intermodalShipmentId: journeyId))

        do {
            // Decoded as Optional on purpose: the ownership gate returns a bare
            // `null` for an unowned or missing id, which is an honest empty —
            // not an error, and never another tenant's freight.
            let d: Journey009? = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalShipmentDetail", input: DetailIn(id: journeyId))
            journey = d
            tracking = (try? await trackTask) ?? nil
            cost = (try? await costTask) ?? nil
            lastSyncedAt = Date()
            tick = Date()
        } catch {
            // READ_CACHED: whatever was already decoded stays on screen and the
            // header staleness line flips to warning. Nothing is silently eaten.
            _ = try? await trackTask
            _ = try? await costTask
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// "Track rail leg" — re-pulls the live container fix, active segment and
    /// ramp ETA. ONLINE_ONLY by necessity: no rail path is offline-eligible
    /// (Services/EusoTripAPI.swift:1684), so a failure is stated, never queued.
    private func refreshFix() async {
        guard resolvedId > 0, railSegment != nil, !refreshingFix else { return }
        refreshingFix = true
        fixError = nil
        struct ShipmentIn: Encodable { let intermodalShipmentId: Int }
        do {
            let t: Tracking009 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking", input: ShipmentIn(intermodalShipmentId: resolvedId))
            tracking = t
            lastSyncedAt = Date()
            tick = Date()
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            fixError = "Live fix unavailable · \(msg). Nothing was queued — rail has no offline-eligible path."
        }
        refreshingFix = false
    }

    // MARK: - Formatting

    private func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private func money(_ v: Double?, _ code: String) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(code) \(Int(v))"
    }

    private func trimNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// ISO-8601 -> "May 26 · 14:05". Nil in, nil out — never a placeholder date.
    private func stamp(_ iso: String?) -> String? {
        guard let iso = nonEmpty(iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return out.string(from: d) }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: iso) { return out.string(from: d) }
        return String(iso.prefix(16))
    }
}

// MARK: - Journey chain band
//
// The compact ordered-segment face of the same timeline. This is deliberately
// not geography: no curved connector, chord, or status-coloured route line is
// inferred between independently reported stops. Segment order is shown with
// neutral chevrons; exact track geometry belongs to a canonical rail plan.

private struct JourneyChainBand009: View {
    @Environment(\.palette) private var palette

    let stops: [ChainStop009]
    let edges: [ChainEdge009]
    let liveLabel: String
    let liveIsReal: Bool
    let etaLabel: String
    let telemetryLabel: String

    /// 0…1 display position per stop. Even spacing communicates sequence only;
    /// it must never imply distance, track shape, or a projected live fix.
    private var fractions: [Double] {
        let n = stops.count
        guard n >= 2 else { return n == 1 ? [0.5] : [] }
        return (0..<n).map { Double($0) / Double(n - 1) }
    }

    private func stopColor(_ s: ChainStop009) -> Color {
        switch s.state {
        case .done:    return Brand.success
        case .active:  return Brand.info
        case .stopped: return Brand.danger
        case .pending: return palette.textTertiary
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let insetL: CGFloat = 22
            let insetR: CGFloat = 22
            let usable = max(1, w - insetL - insetR)
            let baseline = h * 0.60
            let fr = fractions

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)

                // Faint network grid — reads as a board, never as a real map.
                Path { p in
                    for f in [0.28, 0.60, 0.86] {
                        p.move(to: CGPoint(x: 0, y: h * f)); p.addLine(to: CGPoint(x: w, y: h * f))
                    }
                    for f in [0.25, 0.5, 0.75] {
                        p.move(to: CGPoint(x: w * f, y: 0)); p.addLine(to: CGPoint(x: w * f, y: h))
                    }
                }
                .stroke(palette.borderFaint, lineWidth: 1)

                if fr.count >= 2 {
                    // Neutral relays communicate sequence without pretending to
                    // be track geometry or recolouring a route by state.
                    ForEach(Array(edges.enumerated()), id: \.element.id) { idx, e in
                        if idx + 1 < fr.count {
                            let x1: CGFloat = insetL + usable * CGFloat(fr[idx])
                            let x2: CGFloat = insetL + usable * CGFloat(fr[idx + 1])
                            VStack(spacing: 2) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .heavy))
                                Text(e.mode.uppercased())
                                    .font(.system(size: 7, weight: .heavy))
                                    .tracking(0.25)
                            }
                            .foregroundStyle(palette.textTertiary)
                            .position(x: (x1 + x2) / 2, y: baseline - 10)
                        }
                    }

                    // Stop nodes + labels.
                    ForEach(Array(stops.enumerated()), id: \.element.id) { idx, s in
                        let x: CGFloat = insetL + usable * CGFloat(fr[idx])
                        let isEnd = idx == 0 || idx == stops.count - 1
                        Group {
                            if isEnd {
                                ZStack {
                                    Circle().fill(stopColor(s)).frame(width: 10, height: 10)
                                    Circle().fill(.white).frame(width: 3.6, height: 3.6)
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(palette.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .strokeBorder(stopColor(s), lineWidth: 1.6))
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .position(x: x, y: baseline)

                        Text(s.label.uppercased())
                            .font(.system(size: 7, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: 82)
                            .position(x: min(max(x, 44), max(45, w - 44)), y: baseline + 18)
                    }

                }

                // Chips: LIVE / ETA on top, telemetry pill at the foot.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: Space.s2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(liveIsReal ? Brand.success : palette.textTertiary)
                                .frame(width: 6, height: 6)
                            Text(liveLabel)
                                .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.66)))
                        Spacer(minLength: Space.s2)
                        Text(etaLabel)
                            .font(.system(size: 9, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(palette.bgCard))
                            .overlay(Capsule().strokeBorder(palette.borderFaint))
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: Space.s2) {
                        Text(telemetryLabel)
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.3).monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                        Text("ORDERED SEGMENTS · NOT TRACK GEOMETRY")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(Brand.warning)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                }
                .padding(Space.s2)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }
}

// MARK: - Intermodal double-stack well-car
//
// The canonical intermodal asset, drawn as a real animated vector (wheel spin +
// chassis bob), never a raster and never a static silhouette. It is not
// decoration: it marks the live container fix on the chain, so it renders only
// when a real coordinate resolved. Reduce Motion parks it.
//
// UNVERIFIED · named-gap: this belongs in the shared EquipmentAnimation
// component as EquipmentKind.railIntermodal. Until that case lands it stays
// file-private here so it can never collide with a sibling rail screen.

private struct RailIntermodalCar009: View {
    var animated: Bool = true

    @State private var spin = false
    @State private var bob = false

    private static let steel = LinearGradient(
        colors: [Color(hex: 0xEDEFF3), Color(hex: 0xCED4DE), Color(hex: 0x9AA2B0)],
        startPoint: .top, endPoint: .bottom)

    /// Two two-axle trucks under the well — the 640-space X centres.
    private static let axles: [CGFloat] = [152, 208, 432, 488]

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 640.0   // authored in a 640-wide space
            ZStack {
                // rail
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 214 * s))
                    p.addLine(to: CGPoint(x: 640 * s, y: 214 * s))
                }
                .stroke(Color(hex: 0x9B7FD9).opacity(0.55),
                        style: StrokeStyle(lineWidth: 4 * s, lineCap: .round, dash: [16 * s, 10 * s]))

                ZStack {
                    // deck + bolsters
                    RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                        .fill(Color(hex: 0x2A2F3A))
                        .frame(width: 432 * s, height: 16 * s)
                        .position(x: 320 * s, y: 184 * s)
                    // lower container — the brand box
                    RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(width: 340 * s, height: 74 * s)
                        .position(x: 320 * s, y: 141 * s)
                    Circle().fill(.white).frame(width: 30 * s, height: 30 * s)
                        .position(x: 320 * s, y: 141 * s)
                    Text("E")
                        .font(.system(size: 17 * s, weight: .heavy))
                        .foregroundStyle(Brand.magenta)
                        .position(x: 320 * s, y: 141 * s)
                    // upper container — steel
                    RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                        .fill(Self.steel)
                        .frame(width: 316 * s, height: 54 * s)
                        .position(x: 320 * s, y: 75 * s)
                    Text("EUSO")
                        .font(.system(size: 13 * s, weight: .heavy)).tracking(2 * s)
                        .foregroundStyle(Color(hex: 0x5A606D).opacity(0.6))
                        .position(x: 320 * s, y: 75 * s)
                }
                .offset(y: bob ? -2 * s : 0)

                ForEach(Self.axles, id: \.self) { cx in
                    wheel(s).frame(width: 40 * s, height: 40 * s).position(x: cx * s, y: 200 * s)
                }
            }
        }
        .onAppear { start() }
        .onChange(of: animated) { _, _ in start() }
    }

    private func start() {
        guard animated else { spin = false; bob = false; return }
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { spin = true }
        withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) { bob = true }
    }

    private func wheel(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: 0x1A1A1A))
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x5A606D), Color(hex: 0x1F2330)],
                                     center: .center, startRadius: 0, endRadius: 14 * s))
                .padding(6 * s)
            Circle().fill(Color(hex: 0x7A7F88)).frame(width: 10 * s, height: 10 * s)
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(Color(hex: 0x3A3F4A))
                    .frame(width: 2.2 * s, height: 7 * s)
                    .offset(y: -10 * s)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
        }
        .rotationEffect(.degrees(spin ? 360 : 0))
    }
}

// MARK: - Previews

#Preview("009 · Rail Intermodal Journey · Night") {
    RailIntermodalJourney_009(theme: Theme.dark, intermodalShipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("009 · Rail Intermodal Journey · Light") {
    RailIntermodalJourney_009(theme: Theme.light, intermodalShipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
