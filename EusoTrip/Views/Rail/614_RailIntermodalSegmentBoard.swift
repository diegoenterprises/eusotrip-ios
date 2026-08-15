//
//  614_RailIntermodalSegmentBoard.swift
//  EusoTrip — Rail Engineer (carrier) · 05 Rail · 614 Intermodal Segment Board
//
//  Verbatim port of 05 Rail/Light-SVG/614 Rail Intermodal Segment Board.svg
//  (Light + Dark twin).
//
//  ── ARCHETYPE = BOARD / OPERATIONS ──────────────────────────────────────────
//  A queue a rail dispatcher works, not a card they read. Many shipments, one
//  tight row each: which leg it is on, which are STALLED AT A SEAM, at which
//  facility, and how long they have been sitting. The board sorts stalled-first
//  and paints a stalled row as a warning band inside a field of neutral rows, so
//  the broken seam is the first thing the eye lands on.
//
//  THE SVG <desc> IS WRONG ON THIS SCREEN AND THE ROUTER + THE LANE BRIEF WIN.
//  The <desc> self-declares "screen class=DETAIL (one intermodal shipment's
//  door-to-door journey)". That is not what this file is, for three reasons that
//  are all checkable on disk:
//    (a) 566_RailIntermodalTransfer.swift ALREADY is the single-shipment
//        transfer detail, and 009 Rail Intermodal Journey is the single-shipment
//        journey. A third single-shipment relay would be a recreation.
//    (b) The <desc>'s own procedure table is stale in every line — it cites
//        getIntermodalShipmentDetail at intermodal.ts:436 (really :537, and its
//        input key is `id`, not `intermodalShipmentId`), advanceSegment at :459
//        (really :561), getIntermodalTracking at :615 (really :747),
//        recordTransfer at :510 (really :637); it claims RBAC `railProcedure`
//        (really `protectedProcedure`); and it claims advanceSegment "writes
//        blockchainAuditTrail + broadcasts WS_EVENTS" when it writes NEITHER.
//    (c) The screen is named Segment BOARD, and the two reads the lane brief
//        names — getIntermodalShipments and getIntermodalDashboard — are a list
//        read and a tenant aggregate. Those are board reads.
//  The SVG's VISUAL vocabulary is kept in full: one sparkle eyebrow, mono id
//  register, 28/-0.4 title, seam hero, US/CA/MX crossing-regime chip rail,
//  3-cell KPI strip with the middle cell carrying the gradient, an itemised
//  segment list with the at-risk row tinted, and the Advance-segment CTA pair.
//  What changed is the SUBJECT: five stations of one shipment became N rows of
//  N shipments.
//
//  ── WIRING MANIFEST · every line re-read first-hand in
//     eusoronetechnologiesinc/frontend/server/routers/ this fire ───────────────
//   Board rows        intermodal.getIntermodalShipments  EXISTS intermodal.ts:504  (QUERY)
//                     input {status?, limit=20, offset=0} -> {shipments[], total}
//   Summary spine     intermodal.getIntermodalDashboard  EXISTS intermodal.ts:849  (QUERY)
//                     NO input -> {activeShipments, avgTransitDays, modeSplit, totalRevenue}
//   Seam ledger       intermodal.getTransfers            EXISTS intermodal.ts:943  (QUERY)
//                     input {limit=50} -> intermodal_transfers[] carrying
//                     intermodalShipmentId — that column is the join that makes
//                     this a board instead of a list.
//   Advance sheet     intermodal.getIntermodalTracking   EXISTS intermodal.ts:747  (QUERY)
//                     input {intermodalShipmentId} -> {segments[], currentMode,
//                     activeSegmentId, nextRampEta, rampDwell, floodImpact}
//   THE COMMIT        intermodal.advanceSegment          EXISTS intermodal.ts:561  (MUTATION)
//                     input {intermodalShipmentId, completedSegmentId | alias
//                     fromSegmentId, toSegmentId ignored} (zod .refine requires
//                     one of the first two) -> {success, nextSegmentId, newStatus}
//                     Called through EusoTripAPI.mutation (POST). Until
//                     2026-08-10 iOS issued this as query() = GET; the server has
//                     no method override, so the CTA was permanently dead on iOS
//                     while it worked on web — fault class S4. This file is
//                     mutation() from the first commit.
//   NAMED GAP         multiModal.dispatchDrayage         DOES NOT EXIST — zero
//                     hits across the whole frontend/ tree. See the drayage
//                     truth row below; the TS shape is proposed in the report.
//
//  WHAT THIS ROUTER WRITES, HONESTLY. advanceSegment updates intermodal_segments
//  (completed + arrivedAt), promotes the next leg to booked, INSERTS an
//  intermodal_transfers row for the new seam, and moves intermodal_shipments.status.
//  It writes NO blockchainAuditTrail row and it broadcasts NOTHING on the socket —
//  grep of intermodal.ts for WS_EVENTS / WS_CHANNELS / broadcast returns zero, and
//  the ONLY blockchainAuditTrail insert in the entire 977-line file is inside
//  applyModeChoice (intermodal.ts:720, best-effort try/catch). So: DB row YES ·
//  audit row NO · WS_EVENTS.* NONE. Nothing on this screen may claim otherwise,
//  and the board reloads by re-reading rather than by waiting on a tick.
//
//  RBAC. Every procedure in intermodal.ts is `protectedProcedure`, tenant-gated
//  in code by loadOwnedShipment() / resolveCaller(): shipper-of-record, same
//  companyId, or ADMIN. A foreign row reads as honest-empty, never as an error.
//  There is no rail-carrier-specific gate on this router — stated because the
//  SVG <desc> claims `railProcedure` and no such wrapper is used here.
//
//  transportMode = rail. COUNTRY IS CONTENT, NOT A FILE FORK. intermodal_shipments
//  carries no `country` enum (unlike rail_yards), but it DOES carry a real
//  `currency` column (USD | CAD | MXN, default USD). One screen swings its
//  regulator, customs authority and ramp free-time off that real column:
//  US -> STB · CBP · 48h · USD, CA -> CTA · CBSA · 48h · CAD,
//  MX -> ARTF · Aduanas/VUCEM · 24h · MXN. Nothing is typed per country.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(3m) for the board — a segment
//  board turns over as ramps gate boxes in and out, so the last good serve stays
//  on screen and always stamps its own age in the mono 10pt header-right
//  register, which flips to Brand.warning past the TTL and reads "cached" vs
//  "live" vs "stale" rather than passing an old serve off as current.
//  advanceSegment is ONLINE_ONLY: it is a lifecycle commit that closes one leg
//  and opens the next, and the offline-eligibility table at
//  Services/EusoTripAPI.swift:1684 admits exactly six paths (hos.changeStatus,
//  messages.sendMessage, pod.submitPOD, loadLifecycle.executeTransition,
//  drivers.acceptLoad, location.telemetry.geofenceEvent). No rail or intermodal
//  path is among them, so this commit cannot queue. Offline, the CTA renders
//  dimmed with that exact reason on screen instead of pretending to hold it.
//
//  PRODUCTIVITY, ONE SENTENCE. It puts every intermodal box the tenant owns on
//  one screen ranked by how long it has been stuck at a ramp seam, so the
//  dispatcher clears the oldest stall first instead of finding it on the
//  demurrage invoice.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen

struct RailIntermodalSegmentBoard_614: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailIntermodalSegmentBoardBody614() } nav: {
            // Rail Engineer operational band. SHIPMENTS is current: this board's
            // subject is the tenant's intermodal shipments and every row drills
            // into a shipment — the same tab 566 and 673 sit under.
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decimal parse boundary
//
// intermodal_shipments.totalRate / intermodal_transfers.dwellTimeHours et al are
// MySQL `decimal` — the driver serialises them as JSON STRINGS ("1250.00"). A
// future server change to emit numbers must not blank a figure, so every decimal
// decodes through this string-OR-number box (the same boundary 004 uses).

private struct Num614: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

// MARK: - Server shapes (every field Optional except id)

/// intermodal_shipments.originLocation / destinationLocation JSON column.
private struct IMPlace614: Decodable, Hashable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

/// One row of intermodal.getIntermodalShipments (intermodal.ts:504). The
/// procedure does `select().from(intermodalShipments)` so every column arrives.
private struct IMShipment614: Decodable, Identifiable {
    let id: Int
    let intermodalNumber: String?
    let originType: String?
    let destinationType: String?
    let originLocation: IMPlace614?
    let destinationLocation: IMPlace614?
    let commodity: String?
    let hazmatClass: String?
    let numberOfSegments: Int?
    let status: String?
    let totalRate: Num614?
    let currency: String?
    let estimatedTransitDays: Int?
    let actualTransitDays: Int?
    let createdAt: String?
    let updatedAt: String?
}

private struct IMShipmentsPage614: Decodable {
    let shipments: [IMShipment614]?
    let total: Int?
}

/// One row of intermodal.getTransfers (intermodal.ts:943) = one modal seam.
/// `intermodalShipmentId` is the join key that turns a flat transfer log into a
/// per-shipment seam census.
private struct IMSeam614: Decodable, Identifiable {
    let id: Int
    let intermodalShipmentId: Int?
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let transferType: String?
    let facilityName: String?
    let facilityType: String?
    let scheduledAt: String?
    let startedAt: String?
    let completedAt: String?
    let dwellTimeHours: Num614?
    let transferCost: Num614?
    let status: String?
    let notes: String?
}

/// intermodal.getIntermodalDashboard (intermodal.ts:849) — no input, tenant-scoped.
private struct IMDashboard614: Decodable {
    let activeShipments: Int?
    let avgTransitDays: Num614?
    let modeSplit: [String: Int]?
    let totalRevenue: Num614?
}

/// One leg from intermodal.getIntermodalTracking (intermodal.ts:747).
private struct IMLeg614: Decodable, Identifiable {
    let id: Int
    let legNumber: Int?
    let mode: String?
    let originDescription: String?
    let destinationDescription: String?
    let carrierId: Int?
    let rate: Num614?
    let estimatedHours: Num614?
    let actualHours: Num614?
    let status: String?
    let departedAt: String?
    let arrivedAt: String?
}

private struct IMTracking614: Decodable {
    let segments: [IMLeg614]?
    let currentMode: String?
    let activeSegmentId: Int?
    let nextRampEta: String?
    let rampDwell: Num614?
}

private struct IMAdvanceResult614: Decodable {
    let success: Bool?
    let nextSegmentId: Int?
    let newStatus: String?
}

// MARK: - Inputs
//
// Swift's synthesised encoder emits `null` for an absent optional and zod's
// `.optional()` rejects null, so every input carrying an optional hand-rolls
// encode(to:) with encodeIfPresent.

private struct BoardIn614: Encodable {
    let status: String?
    let limit: Int
    let offset: Int
    private enum K: String, CodingKey { case status, limit, offset }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(limit, forKey: .limit)
        try c.encode(offset, forKey: .offset)
    }
}

private struct SeamsIn614: Encodable { let limit: Int }

private struct TrackingIn614: Encodable { let intermodalShipmentId: Int }

/// advanceSegment's zod input is
/// `{intermodalShipmentId, completedSegmentId?, fromSegmentId?, toSegmentId?}`
/// with a `.refine` demanding completedSegmentId OR its alias fromSegmentId.
/// We send the CANONICAL `completedSegmentId` — the server's own comment
/// (intermodal.ts:564-570) files iOS's use of the fromSegmentId alias as a
/// shape-half to be aligned, and toSegmentId is tolerated-and-ignored because
/// the server derives the next leg itself.
private struct AdvanceIn614: Encodable {
    let intermodalShipmentId: Int
    let completedSegmentId: Int?
    private enum K: String, CodingKey { case intermodalShipmentId, completedSegmentId }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(intermodalShipmentId, forKey: .intermodalShipmentId)
        try c.encodeIfPresent(completedSegmentId, forKey: .completedSegmentId)
    }
}

// MARK: - READ_CACHED(3m) snapshot store
//
// The whole decoded board, kept in memory so re-entry paints instantly and can
// honestly label its own age. Nothing is synthesised — it is the last real
// payload, timestamped.

private struct BoardSnapshot614 {
    var shipments: [IMShipment614] = []
    var seams: [IMSeam614] = []
    var dashboard: IMDashboard614? = nil
    var total: Int = 0
}

private final class BoardCache614 {
    static let shared = BoardCache614()
    /// READ_CACHED(3m) — a board serve older than three minutes is labelled
    /// stale, in Brand.warning, and is never presented as live.
    static let ttl: TimeInterval = 3 * 60

    private let lock = NSLock()
    private var store: (snapshot: BoardSnapshot614, at: Date)? = nil

    func read() -> (snapshot: BoardSnapshot614, at: Date)? {
        lock.lock(); defer { lock.unlock() }
        return store
    }

    func write(_ snapshot: BoardSnapshot614) {
        lock.lock(); defer { lock.unlock() }
        store = (snapshot, Date())
    }
}

// MARK: - Mode + posture vocabulary

/// The three real values of the `intermodal_segments.mode` MySQL enum, plus an
/// honest unknown. Tint note: Brand.rail is the SVG's slate #607D8B, which the
/// wireframe uses for the DRAY stations, and Brand.info is #2196F3, which it
/// uses for the RAIL line-haul — so the mapping below looks inverted by name and
/// is correct by pixel.
private enum SeamMode614 {
    case truck, rail, vessel, unknown

    static func parse(_ raw: String?) -> SeamMode614 {
        switch (raw ?? "").uppercased() {
        case "TRUCK": return .truck
        case "RAIL":  return .rail
        case "VESSEL": return .vessel
        default: return .unknown
        }
    }
    var tint: Color {
        switch self {
        case .truck:  return Brand.rail       // slate — the dray legs
        case .rail:   return Brand.info       // rail blue — the line-haul
        case .vessel: return Brand.vessel
        case .unknown: return Brand.neutral
        }
    }
    var glyph: String {
        switch self {
        case .truck:  return "box.truck.fill"
        case .rail:   return "tram.fill"
        case .vessel: return "ferry.fill"
        case .unknown: return "questionmark"
        }
    }
    var word: String {
        switch self {
        case .truck:  return "DRAY"
        case .rail:   return "RAIL"
        case .vessel: return "OCEAN"
        case .unknown: return "MODE"
        }
    }
}

/// Where a shipment sits on its own chain. Every case is derived from the
/// server's OWN `intermodal_shipments.status` enum plus a count of that
/// shipment's real completed transfer rows — nothing is guessed.
///
///   planning · booked                  -> .awaiting
///   first_leg_active                   -> .onLeg(1)
///   second_leg_active                  -> .onLeg(2)
///   third_leg_active                   -> .onLeg(3)
///   at_transfer                        -> .atSeam(after: completed transfers + 1)
///   delivered · invoiced · settled     -> .done
///   cancelled                          -> .cancelled
///
/// `at_transfer` is the server's fallback status whenever the next leg is not
/// leg 2 or 3 (intermodal.ts:620), so its leg index cannot come from the status
/// word alone. It comes from counting that shipment's COMPLETED transfer rows:
/// each completed transfer is one seam already crossed.
private enum SeamPosture614: Equatable {
    case awaiting
    case onLeg(Int)
    case atSeam(afterLeg: Int)
    case done
    case cancelled
    case unknown

    var isStalled: Bool { if case .atSeam = self { return true }; return false }
}

// MARK: - Small helpers

private func parseISO614(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: raw) { return d }
    let f2 = ISO8601DateFormatter()
    if let d = f2.date(from: raw) { return d }
    return nil
}

private func compactAge614(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    if s < 60 { return "\(s)s" }
    if s < 3_600 { return "\(s / 60)m" }
    if s < 86_400 { return "\(s / 3_600)h \((s % 3_600) / 60)m" }
    return "\(s / 86_400)d \((s % 86_400) / 3_600)h"
}

private func seamWord614(_ transferType: String?) -> String {
    switch (transferType ?? "").lowercased() {
    case "truck_to_rail":   return "Dray → Rail"
    case "rail_to_truck":   return "Rail → Dray"
    case "truck_to_vessel": return "Dray → Ocean"
    case "vessel_to_truck": return "Ocean → Dray"
    case "rail_to_vessel":  return "Rail → Ocean"
    case "vessel_to_rail":  return "Ocean → Rail"
    default:
        let raw = (transferType ?? "").replacingOccurrences(of: "_", with: " ")
        return raw.isEmpty ? "Seam" : raw.capitalized
    }
}

private func facilityWord614(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    return raw.replacingOccurrences(of: "_", with: " ")
}

// MARK: - THE SEAM RULE
//
// This screen's signature device, and deliberately unlike its two neighbours:
// 673 draws labelled capsule PILLS joined by discs (a legend you read), and the
// 614 wireframe draws five 34pt station tiles with equipment glyphs (a diagram
// you study). This is neither. It is a 10pt micro-rule sized to fit inside a
// tight list row — one cell per real leg, mode-tinted, hairline for future legs,
// a caret on the live leg — whose whole job is the SEAM NOTCH: when a shipment
// is stalled between legs, the join breaks BELOW the rule's baseline as a filled
// amber wedge with a halo. A broken line reads as broken at a glance, down a
// column of twenty rows, without being read.

private struct SeamRule614: View {
    @Environment(\.palette) private var palette

    /// nil = the server has no leg count for this shipment. The rule then draws
    /// ONE unresolved track instead of inventing a cell structure — a drawn
    /// two-cell rule is a claim that the journey has two legs.
    let legCount: Int?
    let posture: SeamPosture614
    let mode: SeamMode614

    private var resolved: Bool { legCount != nil }
    private var cells: Int { max(1, min(legCount ?? 1, 8)) }

    /// How many cells are fully behind the box.
    private var filled: Int {
        switch posture {
        case .awaiting:            return 0
        case .onLeg(let n):        return max(0, n - 1)
        case .atSeam(let after):   return min(cells, max(1, after))
        case .done:                return cells
        case .cancelled, .unknown: return 0
        }
    }

    private var liveCell: Int? {
        if case .onLeg(let n) = posture, n >= 1, n <= cells { return n - 1 }
        return nil
    }

    /// The join index the notch hangs from (0 = between cell 1 and cell 2).
    private var notchAfter: Int? {
        if case .atSeam(let after) = posture, after >= 1, after < cells { return after - 1 }
        if case .atSeam = posture { return max(0, cells - 2) }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let gap: CGFloat = 3
            let cellW = max(2, (w - gap * CGFloat(cells - 1)) / CGFloat(cells))
            ZStack(alignment: .topLeading) {
                if !resolved {
                    // No leg count on file — one faint unresolved track, no
                    // cells, no notch, no progress claim.
                    Capsule(style: .continuous)
                        .strokeBorder(palette.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: w, height: 6)
                        .offset(y: 3)
                } else {
                    HStack(spacing: gap) {
                        ForEach(Array(0..<cells), id: \.self) { i in
                            cell(i, width: cellW)
                        }
                    }
                    if let after = notchAfter {
                        // Hang the notch on the JOIN between cell `after` and the
                        // next one: join centre minus half the 14pt notch box.
                        notch()
                            .offset(x: (cellW + gap) * CGFloat(after + 1) - gap / 2 - 7, y: 3)
                    }
                }
            }
        }
        .frame(height: 14)
    }

    private func cell(_ i: Int, width: CGFloat) -> some View {
        let isFilled = i < filled
        let isLive = liveCell == i
        let cancelled = posture == .cancelled
        return ZStack {
            Capsule(style: .continuous)
                .fill(cancelled
                      ? palette.borderFaint
                      : (isLive ? mode.tint : (isFilled ? mode.tint.opacity(0.55) : Color.clear)))
                .frame(width: width, height: 6)
            if !isFilled && !isLive && !cancelled {
                Capsule(style: .continuous)
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
                    .frame(width: width, height: 6)
            }
            if isLive {
                // Live-leg caret — the box is ON this leg right now.
                Circle()
                    .fill(palette.bgCard)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(mode.tint, lineWidth: 2))
            }
        }
        .frame(width: width, height: 12, alignment: .center)
    }

    /// The seam notch — the whole point of the device.
    private func notch() -> some View {
        ZStack {
            Circle()
                .fill(Brand.warning.opacity(0.22))
                .frame(width: 14, height: 14)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 10, y: 0))
                p.addLine(to: CGPoint(x: 5, y: 9))
                p.closeSubpath()
            }
            .fill(Brand.warning)
            .frame(width: 10, height: 9)
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Body

private struct RailIntermodalSegmentBoardBody614: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    // Board state
    @State private var shipments: [IMShipment614] = []
    @State private var seams: [IMSeam614] = []
    @State private var dashboard: IMDashboard614? = nil
    @State private var boardTotal: Int = 0

    @State private var loading = true
    @State private var loadError: String? = nil

    // READ_CACHED(3m) bookkeeping — drives the header freshness register.
    @State private var fetchedAt: Date? = nil
    @State private var servedFromCache = false

    // Selection + the ONLINE_ONLY commit
    @State private var selectedId: Int? = nil
    @State private var advanceTarget: IMShipment614? = nil
    @State private var tracking: IMTracking614? = nil
    @State private var trackingLoading = false
    @State private var trackingError: String? = nil
    @State private var advancing = false
    @State private var advanceError: String? = nil
    @State private var toast: String? = nil

    private static let boardLimit = 50
    private static let seamLimit = 50

    // MARK: - Derived · the seam census (all real rows)

    /// The seam a shipment is sitting on: its NEWEST still-open transfer row.
    /// `scheduled | in_progress | delayed` is the server's own open set —
    /// intermodal.ts:253 uses exactly these three to find "the next ramp".
    /// Newest wins because advanceSegment (intermodal.ts:612) inserts a fresh
    /// transfer row every time it closes a leg, so the highest id on a shipment
    /// is the seam it reached most recently.
    private var openSeamByShipment: [Int: IMSeam614] {
        var out: [Int: IMSeam614] = [:]
        for s in seams {
            guard let sid = s.intermodalShipmentId else { continue }
            let st = (s.status ?? "").lowercased()
            guard ["scheduled", "in_progress", "delayed"].contains(st) else { continue }
            if let existing = out[sid], existing.id >= s.id { continue }
            out[sid] = s
        }
        return out
    }

    /// How many seams a shipment has reached = how many transfer rows it owns.
    ///
    /// HONESTY NOTE, checked in the router this fire: NOTHING in intermodal.ts
    /// ever transitions an intermodal_transfers row to "completed" —
    /// advanceSegment inserts at status "scheduled" (intermodal.ts:617) and
    /// recordTransfer inserts at "in_progress" (intermodal.ts:667). So a count
    /// of *completed* rows would be permanently zero and would silently pin
    /// every stalled box to seam 1. The count of ROWS is the honest signal:
    /// advanceSegment writes exactly one per leg it closes.
    private var seamRowCountByShipment: [Int: Int] {
        var out: [Int: Int] = [:]
        for s in seams {
            guard let sid = s.intermodalShipmentId else { continue }
            out[sid, default: 0] += 1
        }
        return out
    }

    private func posture(_ s: IMShipment614) -> SeamPosture614 {
        switch (s.status ?? "").lowercased() {
        case "planning", "booked":           return .awaiting
        case "first_leg_active":             return .onLeg(1)
        case "second_leg_active":            return .onLeg(2)
        case "third_leg_active":             return .onLeg(3)
        case "at_transfer":                  return .atSeam(afterLeg: max(1, seamRowCountByShipment[s.id] ?? 1))
        case "delivered", "invoiced", "settled": return .done
        case "cancelled":                    return .cancelled
        default:                             return .unknown
        }
    }

    /// The mode the box is riding (or about to ride). For a stalled box this is
    /// the receiving side of its open transfer row — the mode it is waiting for.
    private func mode(_ s: IMShipment614) -> SeamMode614 {
        if let seam = openSeamByShipment[s.id], let t = seam.transferType {
            let tail = t.lowercased().components(separatedBy: "_to_").last ?? ""
            return SeamMode614.parse(tail)
        }
        switch posture(s) {
        case .awaiting:     return SeamMode614.parse(s.originType)
        case .onLeg(let n): return n <= 1 ? SeamMode614.parse(s.originType) : .rail
        case .done:         return SeamMode614.parse(s.destinationType)
        default:            return .rail
        }
    }

    /// When the box arrived at the seam it is sitting on. Real timestamps only,
    /// most specific first; nil when the seam has no clock on file.
    private func stalledSince(_ s: IMShipment614) -> Date? {
        if let seam = openSeamByShipment[s.id] {
            if let d = parseISO614(seam.startedAt) { return d }
            if let d = parseISO614(seam.scheduledAt) { return d }
        }
        return parseISO614(s.updatedAt)
    }

    private func dwell(_ s: IMShipment614) -> TimeInterval? {
        guard let since = stalledSince(s) else { return nil }
        return max(0, Date().timeIntervalSince(since))
    }

    private var stalled: [IMShipment614] {
        shipments.filter { posture($0).isStalled }
    }

    private var moving: [IMShipment614] {
        shipments.filter { s -> Bool in
            if case .onLeg = posture(s) { return true }
            return false
        }
    }

    /// Board order: stalled longest-first, then boxes on a leg, then awaiting a
    /// first leg, then everything terminal. A dispatcher works top-down.
    private var orderedRows: [IMShipment614] {
        func rank(_ s: IMShipment614) -> Int {
            switch posture(s) {
            case .atSeam:   return 0
            case .onLeg:    return 1
            case .awaiting: return 2
            case .unknown:  return 3
            case .done:     return 4
            case .cancelled: return 5
            }
        }
        return shipments.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (dwell(a) ?? 0) > (dwell(b) ?? 0)
        }
    }

    /// The oldest stall — the hero's subject.
    private var leadStall: IMShipment614? {
        stalled.max { (dwell($0) ?? 0) < (dwell($1) ?? 0) }
    }

    // MARK: - Derived · country is content (off the real `currency` column)

    /// `currency` is nullable on intermodalShipments. A null currency resolves to
    /// NO regime — it is the only column this board can read a country off, so
    /// defaulting it to USD would manufacture a US jurisdiction, a USD settlement
    /// register and a 48h free-time clock out of an empty cell. nil means
    /// unresolved and every consumer below renders it as unresolved.
    private func regime(_ s: IMShipment614?) -> String? {
        guard let raw = s?.currency?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        switch raw.uppercased() {
        case "CAD": return "CA"
        case "MXN": return "MX"
        case "USD": return "US"
        default:    return nil
        }
    }

    private var boardRegime: String? { regime(leadStall ?? orderedRows.first) }

    private func regimeAuthority(_ code: String) -> String {
        switch code {
        case "CA": return "CA · CTA · CBSA"
        case "MX": return "MX · ARTF · Aduanas"
        default:   return "US · STB · CBP"
        }
    }

    private func regimeCurrency(_ code: String) -> String {
        switch code {
        case "CA": return "CAD"
        case "MX": return "MXN"
        default:   return "USD"
        }
    }

    /// Ramp free time by regime — the number the seam clock is racing.
    private func regimeFreeTime(_ code: String) -> String {
        code == "MX" ? "24h ramp free time" : "48h ramp free time"
    }

    // MARK: - Derived · summary spine

    /// modeSplit is keyed by the MySQL enum, which is UPPERCASE
    /// (TRUCK | RAIL | VESSEL). Read case-insensitively so a server-side casing
    /// change cannot silently zero a figure.
    private func legs(_ mode: String) -> Int {
        guard let m = dashboard?.modeSplit else { return 0 }
        for (k, v) in m where k.uppercased() == mode.uppercased() { return v }
        return 0
    }

    private var activeShipments: Int { dashboard?.activeShipments ?? shipments.count }

    // MARK: - READ_CACHED(3m) freshness register

    private var isStale: Bool {
        guard let fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) > BoardCache614.ttl
    }

    private func freshnessText(now: Date) -> String {
        guard let fetchedAt else { return loading ? "loading" : "no read" }
        let age = max(0, now.timeIntervalSince(fetchedAt))
        let label = age > BoardCache614.ttl ? "stale" : (servedFromCache ? "cached" : "live")
        return "\(label) · \(compactAge614(age))"
    }

    private func freshnessColor(now: Date) -> Color {
        guard let fetchedAt else { return palette.textTertiary }
        let age = max(0, now.timeIntervalSince(fetchedAt))
        if age > BoardCache614.ttl { return Brand.warning }
        return servedFromCache ? palette.textTertiary : Brand.success
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()

                if loading && shipments.isEmpty && dashboard == nil {
                    LifecycleCard {
                        Text("Loading the segment board…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError, shipments.isEmpty, dashboard == nil {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            Text("Pull down to retry. Nothing is drawn from a placeholder while this read is failing.")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                } else {
                    seamLeadHero
                    censusStrip
                    regimeRail
                    boardList
                    drayDispatchTruth
                    ctaBlock
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(item: $advanceTarget) { target in advanceSheet(target) }
    }

    // MARK: - TopBar (the single sparkle · mono id · live census pill)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · SEGMENT BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                // READ_CACHED(3m) staleness register — the honesty law lives here.
                TimelineView(.periodic(from: .now, by: 5)) { ctx in
                    HStack(spacing: 5) {
                        Circle().fill(freshnessColor(now: ctx.date)).frame(width: 6, height: 6)
                        Text(freshnessText(now: ctx.date))
                            .font(EType.mono(.micro))
                            .foregroundStyle(freshnessColor(now: ctx.date))
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text("Segment board")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                censusPill
            }
            Text(idCaption)
                .font(EType.mono(.caption)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// The SVG's static "ON PLAN" chip, made truthful: it reads the real stall
    /// census rather than asserting a plan nobody checked.
    private var censusPill: some View {
        let count = stalled.count
        let text = count > 0 ? "\(count) AT SEAM" : (shipments.isEmpty ? "NO BOXES" : "NO STALLS")
        let kind: StatusPill.Kind = count > 0 ? .warning : (shipments.isEmpty ? .neutral : .success)
        return StatusPill(text: text, kind: kind)
    }

    private var idCaption: String {
        var parts: [String] = []
        parts.append("\(shipments.count) of \(max(boardTotal, shipments.count)) shipments")
        parts.append("\(seams.count) seam rows")
        if let d = dashboard?.avgTransitDays?.value, d > 0.01 {
            parts.append(String(format: "avg %.1fd", d))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - SEAM LEAD hero
    //
    // Not a stat grid and not a five-station relay: a LEAD ITEM. The single
    // worst-aging seam on the tenant, named, timed and located — because on a
    // board the useful hero is the row you should be working, not an average.

    private var seamLeadHero: some View {
        ActiveCard {
            if let lead = leadStall {
                stalledLead(lead)
            } else {
                calmLead
            }
        }
    }

    private func stalledLead(_ s: IMShipment614) -> some View {
        let seam = openSeamByShipment[s.id]
        let code = regime(s)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("OLDEST SEAM")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Text(seamWord614(seam?.transferType))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer(minLength: 0)
                if stalled.count > 1 {
                    Text("+\(stalled.count - 1) more")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
            }

            HStack(alignment: .bottom, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dwell(s).map { compactAge614($0) } ?? "dwell unknown")
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(dwell(s) == nil ? AnyShapeStyle(palette.textTertiary)
                                                         : AnyShapeStyle(LinearGradient.diagonal))
                    Text(dwell(s) == nil
                         ? "no clock on this seam row yet"
                         : (code.map { "sitting at the seam · \(regimeFreeTime($0))" }
                            ?? "sitting at the seam · free time unresolved"))
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("FACILITY")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(seam?.facilityName ?? "unnamed ramp")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(facilityWord614(seam?.facilityType) ?? "type not recorded")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }

            Text(laneLabel(s))
                .font(EType.mono(.caption)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var calmLead: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("SEAM CENSUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(boardRegime.map { regimeAuthority($0) } ?? "jurisdiction unresolved")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text(shipments.isEmpty
                 ? "No intermodal shipments on this tenant"
                 : "No box is sitting at a seam")
                .font(.system(size: 22, weight: .bold)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)
            Text(shipments.isEmpty
                 ? "getIntermodalShipments returned an empty owned set. Rows appear here the moment an intermodal shipment is created against this shipper or company."
                 : "\(moving.count) box\(moving.count == 1 ? "" : "es") on a leg · \(seams.count) transfer row\(seams.count == 1 ? "" : "s") on file. The oldest stall takes this card the moment one opens.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func laneLabel(_ s: IMShipment614) -> String {
        let from = s.originLocation?.description ?? s.originType ?? "origin"
        let to = s.destinationLocation?.description ?? s.destinationType ?? "destination"
        return "\(s.intermodalNumber ?? "IM-\(s.id)") · \(from) → \(to)"
    }

    // MARK: - Census strip (the SVG's 3-cell KPI register, board-scoped)

    private var censusStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "ON BOARD", value: "\(activeShipments)")
            MetricTile(label: "AT SEAM",
                       value: "\(stalled.count)",
                       gradientNumeral: stalled.isEmpty,
                       accent: stalled.isEmpty ? nil : Brand.warning)
            MetricTile(label: "RAIL LEGS", value: "\(legs("RAIL"))")
        }
    }

    // MARK: - Crossing-regime rail (country is content)

    private var regimeRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                ForEach(["US", "CA", "MX"], id: \.self) { code in
                    regimeChip(code, active: code == boardRegime)
                }
                Spacer(minLength: 0)
            }
            Text(boardRegime.map {
                    "\(regimeFreeTime($0)) · settles in \(regimeCurrency($0)) · regime read from the shipment's real currency column"
                 } ?? "Regime unresolved — this board reads country off the shipment's currency column and that column is empty, so no jurisdiction, settlement currency or ramp free time is claimed here.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func regimeChip(_ code: String, active: Bool) -> some View {
        Text(regimeAuthority(code))
            .font(.system(size: 9, weight: .heavy)).tracking(0.2)
            .foregroundStyle(active ? Color.white : palette.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Group {
                    if active { Capsule().fill(LinearGradient.primary) }
                    else { Capsule().fill(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)) }
                }
            )
    }

    // MARK: - THE BOARD

    private var boardList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SEGMENT BOARD · STALLED FIRST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("intermodal segment feed")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            // Honesty law, second register: the rows themselves say when they
            // are a stored serve, not just the header clock.
            if isStale, let fetchedAt {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.warning)
                    Text("These rows are \(compactAge614(Date().timeIntervalSince(fetchedAt))) old — pull down to re-read the board.")
                        .font(EType.caption).foregroundStyle(Brand.warning)
                    Spacer(minLength: 0)
                }
            }
            if orderedRows.isEmpty {
                EusoEmptyState(
                    systemImage: "rectangle.split.3x1",
                    title: "No shipments on the board",
                    subtitle: "Intermodal shipments owned by this shipper or company appear here, ranked by how long they have been stuck at a seam."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(orderedRows) { s in boardRow(s) }
                }
            }
        }
    }

    private func boardRow(_ s: IMShipment614) -> some View {
        let p = posture(s)
        let m = mode(s)
        let seam = openSeamByShipment[s.id]
        let isSelected = selectedId == s.id
        let stalledRow = p.isStalled

        return Button {
            selectedId = (selectedId == s.id) ? nil : s.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: Space.s3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(m.tint.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: m.glyph)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(m.tint)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(laneTitle(s))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(rowSubtitle(s))
                            .font(EType.mono(.caption)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(stateWord(p))
                            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(stateInk(p))
                        Text(dwell(s).map { compactAge614($0) } ?? "—")
                            .font(.system(size: 13, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                }

                SeamRule614(legCount: s.numberOfSegments, posture: p, mode: m)

                if stalledRow {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                        Text(stalledLine(seam))
                            .font(EType.caption).foregroundStyle(Brand.warning)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stalledRow ? Brand.warning.opacity(0.07) : palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(stalledRow ? Brand.warning.opacity(0.34)
                                                                        : palette.borderFaint),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(laneTitle(s)), \(stateWord(p))")
    }

    private func laneTitle(_ s: IMShipment614) -> String {
        let from = s.originLocation?.description ?? s.originType ?? "Origin"
        let to = s.destinationLocation?.description ?? s.destinationType ?? "Destination"
        return "\(from) → \(to)"
    }

    private func rowSubtitle(_ s: IMShipment614) -> String {
        var parts: [String] = [s.intermodalNumber ?? "IM-\(s.id)"]
        if let c = s.commodity, !c.isEmpty { parts.append(c) }
        if let h = s.hazmatClass, !h.isEmpty { parts.append("hazmat \(h)") }
        // numberOfSegments is nullable — a null leg count is stated as unknown,
        // never rounded to a plausible "2 legs".
        if let n = s.numberOfSegments { parts.append("\(n) leg\(n == 1 ? "" : "s")") }
        else { parts.append("— legs") }
        return parts.joined(separator: " · ")
    }

    private func stalledLine(_ seam: IMSeam614?) -> String {
        guard let seam else {
            return "At a seam — no transfer row on file to name the ramp"
        }
        let place = seam.facilityName ?? facilityWord614(seam.facilityType) ?? "ramp"
        return "\(seamWord614(seam.transferType)) at \(place) · \((seam.status ?? "open").replacingOccurrences(of: "_", with: " "))"
    }

    private func stateWord(_ p: SeamPosture614) -> String {
        switch p {
        case .awaiting:          return "AWAITING LEG 1"
        case .onLeg(let n):      return "ON LEG \(n)"
        case .atSeam(let after): return "AT SEAM \(after)"
        case .done:              return "DELIVERED"
        case .cancelled:         return "CANCELLED"
        case .unknown:           return "STATUS UNKNOWN"
        }
    }

    private func stateInk(_ p: SeamPosture614) -> Color {
        switch p {
        case .atSeam:            return Brand.warning
        case .onLeg:             return Brand.info
        case .done:              return Brand.success
        case .awaiting, .unknown, .cancelled: return palette.textTertiary
        }
    }

    // MARK: - The drayage dead-air row, stated plainly
    //
    // Doctrine §4: never fabricate a procedure and never wire a lookalike from
    // another router that would return the wrong entity. The dray legs on this
    // board are `intermodal_segments` rows with mode TRUCK, keyed to
    // intermodalShipmentId. multiModal.getDrayageManagement (multiModal.ts:743)
    // and multiModal.createDrayageOrder (multiModal.ts:917) both read and write
    // the `loads` table with vertical='drayage' — a DIFFERENT entity that carries
    // no intermodalShipmentId at all, so neither can be joined to a row on this
    // board without lying about which box is which. And the one verb that would
    // actually dispatch a dray, multiModal.dispatchDrayage, does not exist
    // anywhere in the tree. So no driver is named here, no ETA is implied, and
    // the affordance is drawn dead with the reason on it.

    private var drayDispatchTruth: some View {
        let drayLegs = legs("TRUCK")
        return LifecycleCard(accentWarning: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "box.truck.badge.clock")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.warning)
                    Text("DRAY LEGS · NOT DISPATCHABLE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.warning)
                    Spacer(minLength: 0)
                    Text("\(drayLegs) leg\(drayLegs == 1 ? "" : "s")")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
                Text("The truck legs on this board are intermodal segments, not dispatched loads. No dray driver is assigned to any of them — assigning one is not built yet, so nothing here hands a leg to a driver. Dray orders raised elsewhere are filed as separate loads with no link back to these shipments, so they are deliberately left off this board.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "nosign").font(.system(size: 10, weight: .heavy))
                    Text("Dispatch dray").font(.system(size: 12, weight: .heavy))
                    Spacer(minLength: 0)
                    Text("not built yet").font(EType.mono(.micro))
                }
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(palette.textTertiary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .accessibilityLabel("Dispatch dray is unavailable — it is not built yet")
            }
        }
    }

    // MARK: - CTA pair (SVG register: one secondary, one primary commit)

    /// The row the Advance commit would act on: the dispatcher's pick, else the
    /// oldest stall. nil means nothing on the board can be advanced.
    private var advanceCandidate: IMShipment614? {
        if let id = selectedId, let hit = shipments.first(where: { $0.id == id }) { return hit }
        return leadStall
    }

    private var advanceBlockReason: String? {
        if advanceCandidate == nil {
            return shipments.isEmpty
                ? "Nothing on the board to advance."
                : "Tap a row to choose which shipment's leg to close."
        }
        if !reach.isOnline {
            return "Offline · advancing a segment is ONLINE_ONLY. Closing a leg opens the next one and writes a transfer row; it is not one of the six actions the offline outbox can replay, so it would be lost rather than held. Reconnect to commit. The board above is a stored snapshot."
        }
        return nil
    }

    private var ctaBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                // SVG copy here is "Tracking". A board has no single shipment to
                // track, and a board-level Tracking button would be a dead nav
                // stub — doctrine §4. It opens the real open-seam ledger instead.
                RailSecondaryActionButton(
                    title: "Seam log",
                    sheetTitle: "Open seams · getTransfers",
                    lines: seamLogLines,
                    width: 150,
                    systemImage: "arrow.left.arrow.right"
                )
                if let target = advanceCandidate, reach.isOnline {
                    CTAButton(
                        title: "Advance segment",
                        action: { openAdvance(target) },
                        trailingIcon: "arrow.right",
                        subtitle: target.intermodalNumber ?? "IM-\(target.id)"
                    )
                } else {
                    blockedCTA
                }
            }
            if let reason = advanceBlockReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: reach.isOnline ? "info.circle" : "wifi.slash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(reach.isOnline ? palette.textTertiary : Brand.warning)
                    Text(reason)
                        .font(EType.caption)
                        .foregroundStyle(reach.isOnline ? palette.textTertiary : Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var blockedCTA: some View {
        HStack(spacing: 6) {
            Image(systemName: reach.isOnline ? "hand.tap" : "wifi.slash")
                .font(.system(size: 13, weight: .bold))
            Text("Advance segment").font(EType.title)
        }
        .foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.primary).opacity(0.28)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityLabel("Advance segment unavailable")
    }

    private var seamLogLines: [String] {
        guard !seams.isEmpty else {
            return ["No seam transfers are on file for your company yet.",
                    "A seam is recorded every time a leg is closed, and again whenever a ramp lift is logged."]
        }
        return seams.prefix(10).map { s in
            let facility = s.facilityName ?? facilityWord614(s.facilityType) ?? "facility not recorded"
            let when = parseISO614(s.startedAt) ?? parseISO614(s.scheduledAt)
            let age = when.map { " · \(compactAge614(Date().timeIntervalSince($0))) ago" } ?? ""
            return "\(seamWord614(s.transferType)) · \(facility) · \((s.status ?? "status pending").replacingOccurrences(of: "_", with: " "))\(age)"
        }
    }

    // MARK: - Advance sheet (ONLINE_ONLY · confirm-gated · real segment id)

    private func openAdvance(_ s: IMShipment614) {
        advanceError = nil
        trackingError = nil
        tracking = nil
        advanceTarget = s
    }

    private func advanceSheet(_ s: IMShipment614) -> some View {
        // The ONLY segment id we will ever commit is the one the server itself
        // nominated as active (getIntermodalTracking.activeSegmentId). No id is
        // ever inferred from a position on the rule.
        let activeId = tracking?.activeSegmentId
        let active = tracking?.segments?.first(where: { leg in activeId != nil && leg.id == activeId! })
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("ADVANCE SEGMENT · CLOSE THIS LEG")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(s.intermodalNumber ?? "IM-\(s.id)")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text(laneTitle(s))
                    .font(EType.caption).foregroundStyle(palette.textSecondary)

                if trackingLoading {
                    LifecycleCard {
                        Text("Reading this shipment's legs…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = trackingError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if let legsList = tracking?.segments, !legsList.isEmpty {
                    legTable(legsList, activeId: tracking?.activeSegmentId)
                    rampLine
                } else {
                    LifecycleCard(accentWarning: true) {
                        Text("No legs came back for this shipment, so there is no real segment to close. Nothing is committed from a guess.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let active {
                    Text("Confirming closes leg \(active.legNumber ?? 0) (\(SeamMode614.parse(active.mode).word), segment #\(active.id)), moves the next leg to booked, and records the transfer at the new seam. The next leg is chosen for you. No audit-trail entry is written and nothing is announced live, so the board refreshes by reloading.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let err = advanceError {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let active, reach.isOnline {
                    confirmButton(title: "Confirm · close leg \(active.legNumber ?? 0)", busy: advancing) {
                        Task { await advance(shipment: s, completedSegmentId: active.id) }
                    }
                } else {
                    Text(reach.isOnline
                         ? "No active leg on this shipment — nothing to close."
                         : "Offline · this confirmation must go through live and cannot be held for later.")
                        .font(EType.caption).foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loadTracking(s) }
    }

    private func legTable(_ legsList: [IMLeg614], activeId: Int?) -> some View {
        let ordered = legsList.sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) }
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("LEGS · TRACKED SEGMENTS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, leg in
                    let m = SeamMode614.parse(leg.mode)
                    let isActive = leg.id == activeId
                    HStack(spacing: Space.s3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(m.tint.opacity(0.14)).frame(width: 32, height: 32)
                            Image(systemName: m.glyph)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(m.tint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Leg \(leg.legNumber ?? idx + 1) · \(m.word)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Text(legEndpoints(leg))
                                .font(EType.mono(.caption))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                        Text((leg.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(isActive ? Brand.info : palette.textTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill((isActive ? Brand.info : palette.textTertiary).opacity(0.14)))
                    }
                    .padding(Space.s3)
                    .background(isActive ? Brand.info.opacity(0.06) : Color.clear)
                    if idx < ordered.count - 1 {
                        Divider().padding(.leading, 56).overlay(palette.borderFaint)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    /// A leg's endpoints as the server recorded them — honestly blank-labelled
    /// rather than rendered as an empty line when the columns are unset.
    private func legEndpoints(_ leg: IMLeg614) -> String {
        let ends = [leg.originDescription, leg.destinationDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return ends.isEmpty ? "endpoints not recorded" : ends.joined(separator: " → ")
    }

    /// getIntermodalTracking additionally returns nextRampEta / rampDwell, which
    /// the server pushes out by a real USGS gage reading when streamflow is
    /// rising at the next crossing. Shown only when the server actually sent it.
    @ViewBuilder
    private var rampLine: some View {
        if tracking?.nextRampEta != nil || tracking?.rampDwell?.value != nil {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    if let eta = tracking?.nextRampEta {
                        Text("Next ramp ETA · \(eta)")
                            .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let dwellHours = tracking?.rampDwell?.value {
                        Text(String(format: "Planned ramp dwell · %.1fh", dwellHours))
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func confirmButton(title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if busy { ProgressView().tint(.white) }
                else { Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white) }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - Toast

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: - Load (READ_CACHED(3m), cache-first, parallel fan-out)

    private func load() async {
        // Cache-first paint so the board is never blank on re-entry — and the
        // header immediately says "cached · Nm" rather than implying live.
        if shipments.isEmpty, dashboard == nil, let cached = BoardCache614.shared.read() {
            shipments = cached.snapshot.shipments
            seams = cached.snapshot.seams
            dashboard = cached.snapshot.dashboard
            boardTotal = cached.snapshot.total
            fetchedAt = cached.at
            servedFromCache = true
        }

        loading = true
        loadError = nil

        do {
            // Secondary fan-out starts first and folds to nil/[] on failure, so
            // a dead seam ledger or a dead aggregate degrades alone.
            async let seamsFetch = fetchSeams()
            async let dashFetch = fetchDashboard()

            // Primary read — this one owns the error surface. If the board rows
            // cannot be read there is no board, and the screen says so instead
            // of drawing an empty queue as if the tenant had no freight.
            let page: IMShipmentsPage614 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalShipments",
                input: BoardIn614(status: nil, limit: Self.boardLimit, offset: 0))

            let seamRows = await seamsFetch
            let dash = await dashFetch

            shipments = page.shipments ?? []
            boardTotal = page.total ?? shipments.count
            // nil = the seam read FAILED (keep the last good ledger rather than
            // blanking every seam name); [] = the tenant genuinely has no
            // transfer rows. The two are not the same and are not conflated.
            seams = seamRows ?? seams
            dashboard = dash ?? dashboard

            fetchedAt = Date()
            servedFromCache = false
            BoardCache614.shared.write(
                BoardSnapshot614(shipments: shipments, seams: seams,
                                 dashboard: dashboard, total: boardTotal))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        loading = false
    }

    /// intermodal.getTransfers — query · intermodal.ts:943. Folds to nil on
    /// failure so a dead seam ledger costs the board its seam names, not its
    /// rows — and so "failed" is never mistaken for "no seams on file".
    private func fetchSeams() async -> [IMSeam614]? {
        do {
            return try await EusoTripAPI.shared.query(
                "intermodal.getTransfers", input: SeamsIn614(limit: Self.seamLimit))
        } catch { return nil }
    }

    /// intermodal.getIntermodalDashboard — query · intermodal.ts:849, no input.
    private func fetchDashboard() async -> IMDashboard614? {
        do {
            return try await EusoTripAPI.shared.queryNoInput("intermodal.getIntermodalDashboard")
        } catch { return nil }
    }

    private func loadTracking(_ s: IMShipment614) async {
        trackingLoading = true
        trackingError = nil
        do {
            let resp: IMTracking614 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking",
                input: TrackingIn614(intermodalShipmentId: s.id))
            tracking = resp
        } catch {
            trackingError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        trackingLoading = false
    }

    /// THE COMMIT. mutation() = POST. advanceSegment is `.mutation` on the
    /// server (intermodal.ts:561) and the server has no method override, so
    /// issuing this as query() would ship a permanently dead CTA — the S4 fault
    /// that was only cured on 2026-08-10. The error is surfaced, never swallowed.
    private func advance(shipment: IMShipment614, completedSegmentId: Int) async {
        guard reach.isOnline else {
            advanceError = "Offline · this commit is ONLINE_ONLY and cannot be queued."
            return
        }
        advancing = true
        advanceError = nil
        do {
            let res: IMAdvanceResult614 = try await EusoTripAPI.shared.mutation(
                "intermodal.advanceSegment",
                input: AdvanceIn614(intermodalShipmentId: shipment.id,
                                    completedSegmentId: completedSegmentId))
            advanceTarget = nil
            let next = res.nextSegmentId.map { "next leg #\($0)" } ?? "final leg closed"
            showToast("Segment advanced · \(res.newStatus ?? "updated") · \(next)")
            await load()
        } catch {
            advanceError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        advancing = false
    }
}

#Preview("614 · Rail Intermodal Segment Board · Night") {
    RailIntermodalSegmentBoard_614(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("614 · Rail Intermodal Segment Board · Light") {
    RailIntermodalSegmentBoard_614(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
