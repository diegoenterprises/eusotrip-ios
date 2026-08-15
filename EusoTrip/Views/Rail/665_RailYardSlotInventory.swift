//
//  665_RailYardSlotInventory.swift
//  EusoTrip — Rail Engineer · Yard Slot Inventory (carrier-side slot board).
//
//  TITLE      665 Rail Yard Slot Inventory
//  PURPOSE    Show every lead track in one yard as a row of discrete occupancy cells —
//             which slots are taken, which cars are fouled, which tracks are empty, and
//             which cars are standing in the yard with no track at all — then commit the
//             next car into real open track from the same screen.
//  SOURCE     Verbatim port of 05 Rail/Light-SVG/665 Rail Yard Slot Inventory.svg (Light + Dark).
//             Composition mirrored register-for-register: DETAIL TopBar (back chevron + the
//             one sparkle eyebrow + mono yard caption + 28/-0.4 title + capacity pill) → the single
//             IridescentHairline → LADDER HERO (bowl eyebrow + used/capacity gradient
//             numeral + spine + per-track slot-cell rows + colour legend) → OPEN / NEEDS A
//             TRACK / NEXT PULL triad → NEEDS A CALL decision queue → derived spotting band
//             → tri-country free-time band → CTA pair (Assign to track · Yard map) → BottomNav.
//  ARCHETYPE  BOARD / OPERATIONS — a track×slot occupancy schematic. The SVG draws a
//             classification-bowl ladder, not a subject card: five tight cell rows read
//             left-to-right as physical track length, the summary band sits above them, and
//             the whole surface exists so someone standing on the lead can answer one
//             question — "where does this car go?" — and commit the answer. Cell rows are
//             fixed-width so a long track visibly out-runs a short one; that spatial read is
//             the archetype. It is NOT a detail card and NOT a hero → 3-KPI → list stamp.
//
//  HOW IT DIFFERS FROM ITS YARD SIBLINGS (checked before writing, none of them stamped):
//    · 559 Yard Operations   — MANY yards on a route in status swim-lanes, a HERE route map,
//                              one relative-capacity bar per yard. Reads getRailYards only,
//                              has no write. 665 is ONE yard, drawn per car, and it commits.
//    · 621 Yard Move Queue   — a hostler/backlog QUEUE over yardManagement (trailer lane),
//                              ranked by wait time. 665 is spatial, not a work queue, and it
//                              is carload-native (railcars), not trailers.
//    · 628 Yard Map          — a GEOGRAPHIC map hero + one uniform TILE per track + a zones
//                              list. Read-only. 665 has no map at all, renders one cell PER
//                              CAR (so row length carries occupancy), adds the free-time /
//                              last-event dimension, and owns the assignCarToTrack commit
//                              that 628 deliberately does not.
//
//  WIRING MANIFEST — every line re-confirmed first-hand against
//  eusoronetechnologiesinc/frontend/server/routers/railShipments.ts this fire.
//  Every procedure in that file is `railProcedure`.
//    EXISTS  railShipments.ts:1251  railShipments.getRailYards            (QUERY)
//              in  { railroadId?, state?, country?, yardType?, hasIntermodal?, limit=50 }
//              out [ rail_yards row ] — drives the yard chip rail + the yard of record
//                  (name / city / state / COUNTRY / yardType / totalTracks / capacity).
//    EXISTS  railShipments.ts:985   railShipments.getYardTrackOccupancy   (QUERY)  ← core read
//              in  { yardId }
//              out { yardId, yardName?, totalTracks?, capacity?, utilizationPct?,
//                    tracks:[{ trackNumber, cars:[{id,carNumber,carType,status}], carCount }],
//                    unassigned:[…] }. utilizationPct is NULL when capacity is unknown.
//              Consumed through the house shim EusoTripAPI.shared.railShipments
//              .getYardTrackOccupancy(yardId:) (EusoTripAPI.swift:26645) so this screen and
//              628 decode the same canonical envelope instead of forking the model.
//    EXISTS  railShipments.ts:931   railShipments.getRailcars             (QUERY)
//              in  { carType?, status?, yardId?, carrierId?, limit=50, offset=0 }
//              out { railcars:[ full row + yardName/yardCoordinates ], total }
//              Enriches each cell with trackNumber / lengthFeet / updatedAt. If this read
//              alone fails the ladder still paints; length + last-event render "—".
//    EXISTS  railShipments.ts:1071  railShipments.getTrainConsists        (QUERY)
//              in  { status?, limit=20, offset=0 }
//              out { consists:[ train_consists row ], total } — the NEXT PULL tile is the
//              soonest future departureTime among consists whose originYardId is this yard
//              and whose status is building / ready. No such consist ⇒ "—", never a guess.
//    EXISTS  railShipments.ts:1039  railShipments.assignCarToTrack        (MUTATION) ← commit
//              in  { yardId: coerce.number, carId: coerce.number,
//                    trackNumber: coerce.number().int().NULLABLE }
//              Note the zod verb: trackNumber is `.nullable()`, NOT `.optional()`. The key
//              MUST be present; null is the legal "return the car to the unassigned pool"
//              value. encode(to:) therefore encodeNil()s it explicitly rather than dropping
//              it, which an encodeIfPresent would have done and which would 400.
//              Server guards: yard must exist · trackNumber must be within 1…totalTracks ·
//              car must exist · car.currentYardId must equal yardId (PRECONDITION_FAILED).
//              out { success, carId, trackNumber }.
//
//  WHAT THE COMMIT WRITES — stated because the header gate demands the truth, not a claim:
//    DB ROW              railcars.trackNumber, via a single db.update (railShipments.ts:1063).
//                        That is the entire write. Nothing else is touched.
//    blockchainAuditTrail  NONE. assignCarToTrack contains no audit insert. The audit inserts
//                        in this router live at 237, 600, 781, 894, 1227, 1755, 2073, 2297,
//                        2449, 2576, 2677 and 3166 — the closest is createConsist's
//                        "rail.consist_created" at :1227, which is a different procedure.
//                        A yard move is currently NOT court-of-record. Named gap below.
//    WS_EVENTS           NONE. assignCarToTrack calls no wsService.broadcastToChannel. The
//                        only broadcasts in this router are BID_AWARDED (:916) and
//                        RAIL_DOC_UPDATED (:3185), plus the shipment create/status
//                        broadcasts at :270 / :560. Because there is no push, this screen
//                        RE-READS the board after every successful write. It never claims
//                        a live socket it does not have.
//
//  NOT WIRED, ON PURPOSE (a logged stub beats a dead button that looks alive):
//    · railShipments.getFacilityStatus (QUERY, railShipments.ts:1885 — the brief's :1800 has
//      drifted) takes { railroad: string, facilityCode: string }. getRailYards returns
//      railroadId as an INT and joins no rail_carriers row, so there is no AAR reporting
//      mark to pass. Calling it would mean inventing the railroad string. The SVG draws no
//      facility-status affordance, so nothing on this screen calls it.
//    · esangCoach.forScreen (esangCoach.ts:264) is a DRIVER in-cab coach: its SCREEN_ENUM
//      (esangCoach.ts:112) has no rail key and its system prompt speaks HOS/DVIR. Wiring the
//      SVG's ESang band to it would return the wrong entity. The band is therefore rendered
//      as a DERIVED SPOTTING READ — every noun and number in it is a decoded server field,
//      composed on device — and it is labelled as such. No model call is claimed.
//
//  NAMED GAPS (proposed TypeScript in the report — never faked on screen):
//    · railYard.slotOccupancy — there is no per-slot model server-side. A track's slot
//      capacity is unknown, so this screen paints one cell per REAL car and NEVER paints a
//      phantom open slot inside a track. Headroom is expressed once, at yard level, from
//      the real capacity figure. An empty track (carCount == 0) is drawn OPEN because the
//      server actually said zero.
//    · railYard.reserveSlot — the SVG's "Reserve slots" primary and its RESERVED cell class
//      have no backend. railcars.status "assigned" is the nearest REAL state (the car is
//      spoken for by a shipment) and is what the HELD cell class renders. The primary CTA is
//      renamed to the verb that exists: "Assign to track".
//    · railcars.spottedAt — railcars has createdAt and updatedAt (onUpdateNow) but no
//      placed-at timestamp. Every elapsed figure on this board is therefore measured from
//      railcars.updatedAt and labelled LAST EVENT, never "dwell" and never a billing figure.
//      The free-time comparison is stated as an estimate for exactly this reason.
//    · rail.car_spotted audit + WS_EVENTS.YARD_SLOT_CHANGED — the SVG <desc> claims this
//      screen streams over WS_EVENTS.YARD_SLOT_CHANGED. It does not exist and
//      assignCarToTrack emits nothing. Declared NONE above; proposed shape in the report.
//    · QUEUE(yard) — see the offline policy.
//
//  THE SVG <desc> IS WRONG ABOUT ITS DATA SOURCE, and the real router wins: the desc routes
//  this screen to yardManagement.getYardMap / getYardLocations / getYardDashboard /
//  moveTrailer / updateTrailerPosition. That is the TRAILER + chassis lane; this is a
//  carload railcar board. The desc concedes it itself ("today getYardMap returns
//  trailer/chassis slots, not railcar slots"). It also cites getAssetHealth at
//  railShipments.ts:1372; the real line is 1829. Nothing here calls the trailer lane.
//
//  RBAC   railProcedure on all four reads and on the commit (RAIL carrier gate, tenant-scoped
//         by ctx company). No shipper-band affordance on this screen.
//
//  transportMode = rail. COUNTRY IS CONTENT, one screen, no file fork — and it is DATA, not a
//  toggle: rail_yards.country (enum US | CA | MX, drizzle/schema.ts) is a real column on the
//  selected yard and it drives (a) the free-time regime the decision queue measures against —
//  48h US, 48h CA, 24h MX — (b) the length unit each car is reported in — feet US, metres
//  CA/MX, converted from the real railcars.lengthFeet — and (c) the named authority: STB/FRA,
//  Transport Canada Rail, ARTF/SICT. The SVG's country row is a presentation toggle and its
//  own <desc> flagged that to be wired; here the band is a read-out of the yard of record and
//  cannot be tapped into disagreeing with the data.
//
//  OFFLINE POLICY (Offline Mode Encyclopedia v2 · honesty law). A slot board is read standing
//  in a yard with bad signal, so the policy is declared, not assumed:
//    · READ_CACHED(10m) — the fused board (occupancy + car enrichment + next pull) is written
//      to a last-good on-disk snapshot per yard on every successful read. When the read fails
//      the snapshot paints, but NEVER silently: a monospaced 10pt staleness line directly
//      under the hero flips from palette.textTertiary "LIVE · read HH:mm:ss" to Brand.warning
//      "CACHED · N min old · not live", and the capacity pill flips to CACHED. 10m, not 30m,
//      because a bowl re-arranges faster than a gate ledger does. Past the ttl the snapshot is
//      REFUSED and the honest error card shows instead of stale numbers dressed as live.
//    · ONLINE_ONLY(assign) — assignCarToTrack is absent from the six-path offline-eligibility
//      table at Services/EusoTripAPI.swift:1684 (hos.changeStatus · messages.sendMessage ·
//      pod.submitPOD · loadLifecycle.executeTransition · drivers.acceptLoad ·
//      location.telemetry.geofenceEvent). No rail path is in it, so mutation() cannot enqueue
//      this move; offline it would hard-fail and the spot would be lost. The primary CTA
//      therefore renders visibly disabled with the reason printed under it, and the commit
//      itself carries a second guard. Nothing is silently swallowed (contrast 566:622) —
//      every failure raises a toast AND an inline state.
//    · Named gap QUEUE(yard) — the change site is the eligibility switch at
//      Services/EusoTripAPI.swift:1684 plus an OfflineQueue lane. Until a yard move is
//      idempotent and audited server-side it should stay ONLINE_ONLY on purpose: a replayed
//      spot hours later would put a car on a track that has since been filled.
//
//  WHY IT HELPS: the engineer sees which tracks are actually empty and which cars have been
//  standing longest, and spots the next car from the same screen — so the inbound cut goes
//  onto real open track instead of being held on the lead while someone walks the bowl.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct RailYardSlotInventory_665: View {
    let theme: Theme.Palette
    /// Optional deep-link target. When absent the board opens on the first yard the
    /// catalog returns; there is no hardcoded yard anywhere in this file.
    var yardId: Int? = nil

    var body: some View {
        Shell(theme: theme) { RailYardSlotInventoryBody665(initialYardId: yardId) } nav: {
            // Rail Engineer operational set. SHIPMENTS is current: the subject of this board
            // is the railcars carrying rail shipments, its commit re-spots one of them, and
            // it is reached from the Shipments hub (Rail551) — the same tab 559 Yard
            // Operations sits under. The SVG <desc> declares SHIPMENTS(current) too.
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

// MARK: - Wire shapes
//
// The occupancy envelope itself is decoded by the canonical house shim
// (YardTrackOccupancy / YardTrack / YardCar, EusoTripAPI.swift:26567-26593) so this screen
// and 628 cannot drift apart. Everything below is what that shim does not carry.

/// One `rail_yards` row from `railShipments.getRailYards` (railShipments.ts:1251). The house
/// `RailYardRow` shim omits `country`, which this screen needs because country is the free-time
/// regime and the length unit — so the row is decoded locally instead of being faked.
private struct YardCatalogRow665: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let splcCode: String?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let totalTracks: Int?
    let capacity: Int?
    let hasHazmat: Bool?
    let status: String?
}

/// One full `railcars` row from `railShipments.getRailcars` (railShipments.ts:931). Only the
/// columns this board renders are decoded; unknown keys are ignored by the decoder.
private struct RailcarRow665: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let carType: String?
    let status: String?
    let owner: String?
    let lengthFeet: Int?
    let trackNumber: Int?
    let currentYardId: Int?
    let assignedShipmentId: Int?
    let updatedAt: String?
}

private struct RailcarsEnvelope665: Decodable {
    let railcars: [RailcarRow665]?
    let total: Int?
}

/// One `train_consists` row from `railShipments.getTrainConsists` (railShipments.ts:1071).
private struct ConsistRow665: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let trainType: String?
    let originYardId: Int?
    let destinationYardId: Int?
    let departureTime: String?
    let totalCars: Int?
    let status: String?
}

private struct ConsistsEnvelope665: Decodable {
    let consists: [ConsistRow665]?
    let total: Int?
}

/// `railShipments.assignCarToTrack` result (railShipments.ts:1039, MUTATION).
private struct AssignResult665: Decodable {
    let success: Bool?
    let carId: Int?
    let trackNumber: Int?
}

// MARK: - Fused board snapshot (also the READ_CACHED payload)
//
// Three reads land in one board. The snapshot is Codable because it is what the
// READ_CACHED(10m) store persists — the shim envelope is Decodable-only, so caching the
// FUSED result is both the honest unit (the staleness line covers the whole board) and the
// only encodable one.

/// One car occupying a cell, or standing in the unassigned pool.
private struct SlotCar665: Codable, Identifiable, Hashable {
    let id: Int
    let mark: String?
    let carType: String?
    let status: String?
    let track: Int?
    let lengthFeet: Int?
    /// `railcars.updatedAt` — the last recorded CHANGE to the row. NOT an arrival time.
    /// Rendered as LAST EVENT everywhere; see the railcars.spottedAt named gap.
    let lastEventAt: String?
}

private struct SlotTrack665: Codable, Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    let cars: [SlotCar665]
}

private struct SlotBoard665: Codable {
    let yardId: Int
    let yardName: String?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let totalTracks: Int?
    let capacity: Int?
    let utilizationPct: Double?
    let tracks: [SlotTrack665]
    let unassigned: [SlotCar665]
    let nextPullAt: String?
    let nextPullConsist: String?
    let nextPullStatus: String?
    /// False when the getRailcars leg failed — length and last-event then render "—"
    /// rather than a fabricated figure.
    let enriched: Bool
}

// MARK: - READ_CACHED(10m) store

private struct SlotBoardEnvelope665: Codable {
    let capturedAt: Date
    let value: SlotBoard665
}

private enum SlotBoardCache665 {
    static let ttl: TimeInterval = 10 * 60
    static let ttlLabel = "10m"

    private static func fileURL(_ yardId: Int) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("rail-yard-slots-665", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("board-\(yardId).json")
    }

    static func store(_ value: SlotBoard665) {
        guard let url = fileURL(value.yardId) else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(SlotBoardEnvelope665(capturedAt: Date(), value: value)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Snapshot + age, only while inside the ttl. Past the ttl this returns nil so the caller
    /// must show its error state instead of stale numbers dressed as live.
    static func load(_ yardId: Int) -> (value: SlotBoard665, age: TimeInterval)? {
        guard let url = fileURL(yardId), let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let env = try? dec.decode(SlotBoardEnvelope665.self, from: data) else { return nil }
        let age = Date().timeIntervalSince(env.capturedAt)
        guard age >= 0, age <= ttl else { return nil }
        return (env.value, age)
    }
}

// MARK: - Cell classes
//
// Exactly one class per REAL `railcars.status` enum member. Nothing is painted that the
// server did not say, and every colour painted is named in the legend.

private enum SlotState665 {
    case loaded        // status "loaded"        — a loaded car occupies the slot
    case empty         // status "available" | "stored" — an empty car occupies the slot
    case held          // status "assigned"      — spoken for by a shipment
    case pulling       // status "in_transit"    — moving off / about to leave
    case badOrder      // status "in_repair" | "out_of_service" — the slot is fouled
    case unknown       // status absent

    init(status: String?) {
        switch (status ?? "").lowercased() {
        case "loaded":                        self = .loaded
        case "available", "stored":           self = .empty
        case "assigned":                      self = .held
        case "in_transit":                    self = .pulling
        case "in_repair", "out_of_service":   self = .badOrder
        default:                              self = .unknown
        }
    }

    var label: String {
        switch self {
        case .loaded:   return "LOADED"
        case .empty:    return "EMPTY"
        case .held:     return "HELD"
        case .pulling:  return "PULLING"
        case .badOrder: return "BAD ORDER"
        case .unknown:  return "UNKNOWN"
        }
    }

    var tint: Color {
        switch self {
        case .loaded:   return Brand.info      // 0x2196F3 — the SVG's occupied blue
        case .empty:    return Brand.rail      // 0x607D8B — the SVG's empty slate
        case .held:     return Brand.warning   // 0xFFA726 — the SVG's reserved amber
        case .pulling:  return Brand.success   // 0x00C48C — the SVG's outlined green
        case .badOrder: return Brand.danger    // 0xF44336 — the SVG's bad-order red
        case .unknown:  return Brand.neutral   // 0x6B7280 — the server sent no status
        }
    }

    /// The outlined classes (SVG's green B1 cells) read as hollow; the rest are solid.
    var isOutlined: Bool { self == .pulling }
    var fillOpacity: Double { isOutlined ? 0.18 : (self == .empty ? 0.55 : 0.85) }
    var isBlocking: Bool { self == .badOrder }
}

// MARK: - Country content

/// Free time, length unit and rail authority, keyed off the REAL rail_yards.country enum.
private enum FreeTimeRegime665: String {
    case us = "US"
    case ca = "CA"
    case mx = "MX"

    init(country: String?) {
        switch (country ?? "").uppercased() {
        case "CA": self = .ca
        case "MX": self = .mx
        default:   self = .us
        }
    }

    /// Carload free time before storage / demurrage begins to accrue.
    var freeHours: Int {
        switch self {
        case .us, .ca: return 48
        case .mx:      return 24
        }
    }
    var freeLabel: String { "\(freeHours)h" }

    var unitLabel: String {
        switch self {
        case .us: return "feet"
        case .ca: return "metres"
        case .mx: return "metros"
        }
    }
    var unitSuffix: String {
        switch self {
        case .us: return "ft"
        case .ca, .mx: return "m"
        }
    }
    var authority: String {
        switch self {
        case .us: return "STB · FRA"
        case .ca: return "Transport Canada Rail"
        case .mx: return "ARTF · SICT"
        }
    }
    var code: String { rawValue }

    /// Real `railcars.lengthFeet` rendered in the yard-of-record's unit. Feet stay feet;
    /// CA/MX convert at the exact 0.3048 factor. Absent length ⇒ nil ⇒ "—".
    func length(feet: Int?) -> String? {
        guard let feet, feet > 0 else { return nil }
        switch self {
        case .us: return "\(feet) ft"
        case .ca, .mx:
            let m = Double(feet) * 0.3048
            return "\(Int(m.rounded())) m"
        }
    }
}

// MARK: - Body

private struct RailYardSlotInventoryBody665: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    let initialYardId: Int?

    // Catalog + selection
    @State private var yards: [YardCatalogRow665] = []
    @State private var selectedYardId: Int? = nil

    // Board
    @State private var board: SlotBoard665? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var cacheAge: TimeInterval? = nil
    @State private var lastLiveAt: Date? = nil
    /// Generation guard — a slow response for a yard the user has already left can never
    /// paint over the current selection.
    @State private var boardRequestId = 0

    // Commit
    @State private var showAssign = false
    @State private var assignCar: SlotCar665? = nil
    @State private var assignTrack: Int? = nil
    @State private var assigning = false
    @State private var assignError: String? = nil
    @State private var toast: (text: String, ok: Bool)? = nil

    private static let carsLimit = 200
    private static let consistsLimit = 50

    // MARK: Derived

    private var selectedYard: YardCatalogRow665? {
        guard let id = selectedYardId else { return nil }
        return yards.first { $0.id == id }
    }

    private var regime: FreeTimeRegime665 {
        FreeTimeRegime665(country: board?.country ?? selectedYard?.country)
    }

    private var isCached: Bool { cacheAge != nil }

    private var allSpotted: [SlotCar665] { (board?.tracks ?? []).flatMap { $0.cars } }
    private var unassigned: [SlotCar665] { board?.unassigned ?? [] }
    private var allCars: [SlotCar665] { allSpotted + unassigned }

    private var openTracks: [SlotTrack665] { (board?.tracks ?? []).filter { $0.cars.isEmpty } }

    /// Yard-level headroom. Nil — rendered "—" — whenever capacity is unknown; a slot count
    /// is never invented from a track count.
    private var openSlots: Int? {
        guard let cap = board?.capacity, cap > 0 else { return nil }
        return max(0, cap - allCars.count)
    }

    private func count(_ state: SlotState665) -> Int {
        allCars.filter { SlotState665(status: $0.status) == state }.count
    }

    private var badOrderCars: [SlotCar665] {
        allSpotted.filter { SlotState665(status: $0.status).isBlocking }
    }

    /// Elapsed hours since the car's last recorded row change. Nil when the field is absent.
    private func hoursSinceLastEvent(_ car: SlotCar665) -> Double? {
        guard let d = Self.parseISO(car.lastEventAt) else { return nil }
        let s = Date().timeIntervalSince(d)
        guard s >= 0 else { return nil }
        return s / 3600
    }

    private func pastFreeTime(_ car: SlotCar665) -> Bool {
        guard let h = hoursSinceLastEvent(car) else { return false }
        return h >= Double(regime.freeHours)
    }

    /// The decision queue: fouled slots first, then cars past the free-time estimate, then
    /// cars standing with no track — each ordered by how long it has been quiet.
    private var needsACall: [SlotCar665] {
        let fouled = badOrderCars
        let fouledIds = Set(fouled.map { $0.id })
        let overdue = allSpotted
            .filter { !fouledIds.contains($0.id) && pastFreeTime($0) }
        let overdueIds = Set(overdue.map { $0.id })
        let loose = unassigned.filter { !fouledIds.contains($0.id) && !overdueIds.contains($0.id) }
        let by: (SlotCar665, SlotCar665) -> Bool = {
            (hoursSinceLastEvent($0) ?? -1) > (hoursSinceLastEvent($1) ?? -1)
        }
        return fouled.sorted(by: by) + overdue.sorted(by: by) + loose.sorted(by: by)
    }

    /// Minutes until the soonest consist pull originating at this yard. Nil ⇒ "—".
    private var nextPullMinutes: Int? {
        guard let d = Self.parseISO(board?.nextPullAt) else { return nil }
        let s = d.timeIntervalSinceNow
        guard s > 0 else { return nil }
        return Int(s / 60)
    }

    /// Derived spotting read — composed on device from fields already on this board.
    /// Nil when the board cannot support a sentence; never padded with a guess.
    private var spottingRead: (headline: String, detail: String)? {
        guard let b = board else { return nil }
        if let car = unassigned.sorted(by: { (hoursSinceLastEvent($0) ?? -1) > (hoursSinceLastEvent($1) ?? -1) }).first {
            let mark = car.mark ?? "car \(car.id)"
            if let t = openTracks.first {
                var detail = "track \(t.number) is empty on the live read"
                if let h = hoursSinceLastEvent(car) {
                    detail += " · \(mark) quiet \(Self.elapsed(h)) against a \(regime.freeLabel) \(regime.code) free clock"
                }
                return ("Spot \(mark) to track \(String(format: "%02d", t.number))", detail)
            }
            var detail = "no track on this yard is empty — \(allCars.count) cars are standing"
            if let cap = b.capacity, cap > 0 { detail += " against \(cap) slots" }
            return ("\(mark) has nowhere to go", detail)
        }
        if let fouled = badOrderCars.first {
            let mark = fouled.mark ?? "car \(fouled.id)"
            let spot = fouled.track.map { "track \(String(format: "%02d", $0))" } ?? "the yard"
            return ("\(mark) is fouling \(spot)",
                    "\(SlotState665(status: fouled.status).label.lowercased()) · pull it to the shop track before the next cut arrives")
        }
        if !openTracks.isEmpty {
            let n = openTracks.count
            return ("\(n) track\(n == 1 ? "" : "s") open, nothing waiting",
                    "every car at \(b.yardName ?? "this yard") has a track")
        }
        return nil
    }

    private var canAssign: Bool {
        reach.isOnline && !assigning && selectedYardId != nil && !allCars.isEmpty && !isCached
    }

    private var assignBlockedReason: String? {
        if selectedYardId == nil { return "Pick a yard first — the commit is scoped to one yard of record." }
        if !reach.isOnline {
            return "Offline — a yard move cannot be held on this device; no rail action is eligible for offline queuing. Reconnect to spot the car."
        }
        if isCached {
            return "This board is a cached snapshot, not a live read. Spotting against stale occupancy could put a car on a track that has since been filled — pull to refresh first."
        }
        if allCars.isEmpty { return "No cars are at this yard on the live read, so there is nothing to spot." }
        return nil
    }

    /// Capacity pill — the yard-level utilization, or the freshness ruling when it outranks it.
    private var capacityPill: (text: String, color: Color) {
        if !reach.isOnline { return ("OFFLINE", palette.textTertiary) }
        if isCached        { return ("CACHED", Brand.warning) }
        guard let pct = board?.utilizationPct else { return ("CAPACITY —", palette.textTertiary) }
        let rounded = Int(pct.rounded())
        let color: Color = pct >= 95 ? Brand.danger : (pct >= 80 ? Brand.warning : Brand.info)
        return ("\(rounded)% FULL", color)
    }

    /// READ_CACHED staleness line — monospaced 10pt, tertiary live, Brand.warning the moment
    /// the screen is painting a snapshot instead of a live read.
    private var staleness: (text: String, warn: Bool) {
        if let age = cacheAge {
            let mins = max(Int(age / 60), 0)
            let old = mins < 1 ? "under a minute" : (mins == 1 ? "1 min" : "\(mins) min")
            return ("READ_CACHED(\(SlotBoardCache665.ttlLabel)) · CACHED · \(old) old · not live", true)
        }
        guard let at = lastLiveAt else {
            return ("READ_CACHED(\(SlotBoardCache665.ttlLabel)) · awaiting first read", false)
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return ("READ_CACHED(\(SlotBoardCache665.ttlLabel)) · LIVE · read \(f.string(from: at))", false)
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()

                if !yards.isEmpty { yardRail }

                if loading && board == nil {
                    loadingLadder
                } else if let err = loadError, board == nil {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        Text("Pull to retry. Nothing is being shown from cache — the last snapshot for this yard is older than \(SlotBoardCache665.ttlLabel).")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if board != nil {
                    ladderHero
                    stalenessRow
                    triad
                    decisionQueue
                    if let read = spottingRead { spottingBand(read) }
                    countryBand
                    ctaPair
                    if let reason = assignBlockedReason { blockedNotice(reason) }
                } else {
                    EusoEmptyState(systemImage: "rectangle.split.3x1",
                                   title: "No yard selected",
                                   subtitle: "Pick a yard to read its track and slot occupancy.")
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await bootstrap() }
        .eusoRefreshable { await reloadBoard() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showAssign) { assignSheet }
    }

    // MARK: TopBar (DETAIL register, per the SVG)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · YARD SLOTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(yardCaption)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text("Slot inventory")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text(capacityPill.text)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(capacityPill.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(capacityPill.color.opacity(0.16)))
            }
        }
    }

    private var yardCaption: String {
        guard let y = selectedYard ?? yards.first else { return "NO YARD" }
        let place = [y.city, y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let base = place.isEmpty ? (y.name ?? "YARD") : place
        return base.uppercased()
    }

    // MARK: Yard chip rail

    private var yardRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yards) { y in
                    let active = y.id == selectedYardId
                    Button {
                        guard y.id != selectedYardId else { return }
                        selectedYardId = y.id
                        Task { await reloadBoard() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(y.name ?? "Yard \(y.id)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(active ? .white : palette.textPrimary)
                                .lineLimit(1)
                            Text(chipSub(y))
                                .font(EType.mono(.micro))
                                .foregroundStyle(active ? Color.white.opacity(0.85) : palette.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(
                            Group {
                                if active { AnyView(LinearGradient.primary) }
                                else      { AnyView(palette.bgCard) }
                            }
                        )
                        .overlay(Capsule().strokeBorder(active ? Color.clear : palette.borderFaint, lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chipSub(_ y: YardCatalogRow665) -> String {
        var parts: [String] = []
        if let c = y.country, !c.isEmpty { parts.append(c.uppercased()) }
        if let t = y.totalTracks, t > 0 { parts.append("\(t) tk") }
        if let cap = y.capacity, cap > 0 { parts.append("\(cap) slots") }
        return parts.isEmpty ? "yard \(y.id)" : parts.joined(separator: " · ")
    }

    // MARK: Hero — the classification-bowl ladder

    private var ladderHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(bowlEyebrow)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                usedNumeral
                VStack(alignment: .leading, spacing: 1) {
                    Text("slots used")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(usedSubline)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }

            ladder

            legend
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var bowlEyebrow: String {
        let kind = (board?.yardType ?? selectedYard?.yardType ?? "")
            .replacingOccurrences(of: "_", with: " ").uppercased()
        let n = board?.totalTracks ?? selectedYard?.totalTracks ?? 0
        let head = kind.isEmpty ? "YARD" : kind
        return n > 0 ? "\(head) · \(n) LEAD TRACK\(n == 1 ? "" : "S")" : "\(head) · TRACK COUNT —"
    }

    private var usedNumeral: some View {
        let used = allCars.count
        let cap = board?.capacity ?? 0
        // Honest denominator: capacity is em-dashed when the yard row leaves it null, never
        // back-filled from a track count.
        let denom = cap > 0 ? "/\(cap)" : "/—"
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(used)")
                .font(.system(size: 30, weight: .bold).monospacedDigit()).kerning(-0.6)
                .foregroundStyle(LinearGradient.primary)
            Text(denom)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var usedSubline: String {
        var parts: [String] = []
        if let open = openSlots { parts.append("\(open) open") } else { parts.append("capacity —") }
        parts.append("\(unassigned.count) need a track")
        if count(.badOrder) > 0 { parts.append("\(count(.badOrder)) fouled") }
        return parts.joined(separator: " · ")
    }

    /// The ladder: one row per REAL track, one cell per REAL car, left-aligned at a fixed
    /// cell width so a long track visibly out-runs a short one. No phantom open slot is ever
    /// drawn inside a track — there is no per-slot model server-side.
    private var ladder: some View {
        let tracks = board?.tracks ?? []
        return Group {
            if tracks.isEmpty {
                Text("This yard reports no tracks on file, so there is no ladder to draw.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.s3)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    // Ladder spine + one tick per track row.
                    VStack(spacing: 0) {
                        ForEach(tracks) { _ in
                            HStack(spacing: 0) {
                                Rectangle().fill(palette.borderStrong).frame(width: 2)
                                Rectangle().fill(palette.borderSoft).frame(width: 6, height: 1.6)
                                Spacer(minLength: 0)
                            }
                            .frame(height: SlotLadderRow665.rowHeight)
                        }
                    }
                    .frame(width: 8)

                    VStack(spacing: 0) {
                        ForEach(tracks) { t in
                            SlotLadderRow665(
                                track: t,
                                regime: regime,
                                isTarget: assignTrack == t.number,
                                onTap: { tapTrack(t) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func tapTrack(_ t: SlotTrack665) {
        assignTrack = (assignTrack == t.number) ? nil : t.number
        if assignCar == nil { assignCar = unassigned.first ?? allSpotted.first }
        assignError = nil
        showAssign = true
    }

    /// Every colour the ladder paints is named here — an unnamed colour on an operations
    /// board is a defect, so this row carries five swatches where the SVG carried four.
    private var legend: some View {
        HStack(spacing: 8) {
            legendSwatch(.loaded)
            legendSwatch(.empty)
            legendSwatch(.held)
            legendSwatch(.pulling)
            legendSwatch(.badOrder)
            Spacer(minLength: 0)
        }
    }

    private func legendSwatch(_ s: SlotState665) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(s.tint.opacity(s.fillOpacity))
                .frame(width: 11, height: 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(s.isOutlined ? s.tint.opacity(0.5) : Color.clear, lineWidth: 1)
                )
            Text(s.label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.textSecondary)
            Text("\(count(s))")
                .font(.system(size: 8.5, weight: .heavy)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    // MARK: Staleness

    private var stalenessRow: some View {
        let s = staleness
        return HStack(spacing: 6) {
            Image(systemName: s.warn ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
            Text(s.text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    // MARK: Triad

    private var triad: some View {
        HStack(spacing: Space.s2) {
            slotTile(label: "OPEN SLOTS",
                     value: openSlots.map { "\($0)" } ?? "—",
                     sub: openTracks.isEmpty
                        ? "NO EMPTY TRACK"
                        : "\(openTracks.count) EMPTY TRACK\(openTracks.count == 1 ? "" : "S")",
                     subColor: .white,
                     highlight: true)

            slotTile(label: "NEEDS A TRACK",
                     value: "\(unassigned.count)",
                     sub: unassigned.isEmpty ? "ALL SPOTTED" : "SPOT TO COMMIT",
                     subColor: unassigned.isEmpty ? Brand.success : Brand.warning,
                     highlight: false)

            slotTile(label: "NEXT PULL",
                     value: nextPullMinutes.map(Self.durationShort) ?? "—",
                     sub: nextPullSub,
                     subColor: nextPullMinutes == nil ? palette.textTertiary : Brand.info,
                     highlight: false)
        }
    }

    private var nextPullSub: String {
        guard nextPullMinutes != nil else { return "NO CONSIST BUILDING" }
        let name = board?.nextPullConsist ?? "CONSIST"
        let st = (board?.nextPullStatus ?? "").uppercased()
        return st.isEmpty ? name.uppercased() : "\(name.uppercased()) · \(st)"
    }

    private func slotTile(label: String, value: String, sub: String, subColor: Color, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(highlight ? Color.white.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 26, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? Color.white : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(highlight ? Color.white.opacity(0.9) : subColor)
                .lineLimit(1).minimumScaleFactor(0.65)
        }
        .padding(.vertical, 12).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            Group {
                if highlight { AnyView(LinearGradient.diagonal) }
                else         { AnyView(palette.bgCard) }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(highlight ? Color.clear : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Decision queue

    private var decisionQueue: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEEDS A CALL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("free time \(regime.freeLabel) · \(regime.code)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }

            if needsACall.isEmpty {
                LifecycleCard {
                    Text("Every car at this yard has a track and none is fouled.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(needsACall.prefix(8).enumerated()), id: \.element.id) { idx, car in
                        callRow(car)
                        if idx < min(needsACall.count, 8) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))

                if needsACall.count > 8 {
                    Text("+\(needsACall.count - 8) more waiting on a call")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }

            if board?.enriched == false {
                // The getRailcars leg did not land: no length and no last-event field reached
                // this board. Say so rather than letting every row's "—" look like real data.
                Text("Car detail did not load on this read — length and last-event are unavailable, so every elapsed figure and free-time verdict on this board is withheld rather than estimated. Pull to retry.")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Elapsed is measured from railcars.updatedAt — the car's last recorded change, not a placed-at time. Treat the free-time read as an estimate, never as a billing figure.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func callRow(_ car: SlotCar665) -> some View {
        let state = SlotState665(status: car.status)
        let fouled = state.isBlocking
        let overdue = pastFreeTime(car)
        let loose = car.track == nil

        let tint: Color = fouled ? Brand.danger : (overdue ? Brand.danger : Brand.warning)
        let pill: String = fouled ? "FOULED" : (overdue ? "PAST FREE TIME" : "NO TRACK")
        let glyph: String = fouled ? "exclamationmark.triangle.fill" : (loose ? "tray.full.fill" : "clock.badge.exclamationmark")

        let spot: String = car.track.map { "track \(String(format: "%02d", $0))" } ?? "unassigned pool"
        var sub: [String] = [spot]
        if let t = car.carType, !t.isEmpty { sub.append(t.replacingOccurrences(of: "_", with: " ")) }
        sub.append(state.label.lowercased())
        if let len = regime.length(feet: car.lengthFeet) { sub.append(len) }

        return HStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint))

            VStack(alignment: .leading, spacing: 4) {
                Text(car.mark ?? "Car \(car.id)")
                    .font(.system(size: 14, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub.joined(separator: " · "))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(pill)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.16)))
                Text(hoursSinceLastEvent(car).map { Self.elapsed($0) } ?? "—")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("LAST EVENT")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .contentShape(Rectangle())
        .onTapGesture {
            assignCar = car
            assignTrack = openTracks.first?.number ?? car.track
            assignError = nil
            showAssign = true
        }
    }

    // MARK: Derived spotting band
    //
    // The SVG draws an ESang proposal here. esangCoach.forScreen is a driver coach with no
    // rail screen key, so this band is composed on device from fields already decoded on this
    // board and is labelled as a derived read. No model call is made or claimed.

    private func spottingBand(_ read: (headline: String, detail: String)) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(read.headline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(read.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("DERIVED ON DEVICE FROM THIS BOARD · NOT AN ASSISTANT")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Country band (read-out of the yard of record, not a toggle)

    private var countryBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("YARD SLOTS · UNITS & FREE TIME BY COUNTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("set by the yard of record")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                ForEach([FreeTimeRegime665.us, .ca, .mx], id: \.rawValue) { r in
                    countryTile(r, active: r == regime)
                }
            }
        }
    }

    private func countryTile(_ r: FreeTimeRegime665, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(r.code) · \(r.unitLabel)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? .white : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("free time \(r.freeLabel)")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(r.authority)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(active ? Color.white.opacity(0.8) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(
            Group {
                if active { AnyView(LinearGradient.primary) }
                else      { AnyView(palette.bgCard) }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: "Assign to track",
                action: {
                    assignCar = unassigned.first ?? allSpotted.first
                    assignTrack = openTracks.first?.number
                    assignError = nil
                    showAssign = true
                },
                subtitle: unassigned.isEmpty
                    ? "RE-SPOT A CAR"
                    : "\(unassigned.count) CAR\(unassigned.count == 1 ? "" : "S") NEED A TRACK",
                isLoading: !canAssign
            )

            Button {
                NotificationCenter.default.post(name: .eusoRailNavSwap, object: nil,
                                                userInfo: ["screenId": "Rail628"])
            } label: {
                Text("Yard map")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    // 60 = CTAButton's 52 minHeight + its 4pt vertical padding, so the pair
                    // sits on one baseline the way the SVG's 48pt pair does.
                    .frame(width: 128, height: 60)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func blockedNotice(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: reach.isOnline ? "info.circle.fill" : "wifi.slash")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Brand.warning)
            Text(reason)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.30), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Loading skeleton

    private var loadingLadder: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard).frame(height: 216)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard).frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1))
                }
            }
            Text("Reading track occupancy…")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Assign sheet — the commit

    private var assignSheet: some View {
        let target = assignTrack
        let car = assignCar
        let tracks = board?.tracks ?? []

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SPOT A CAR · \((board?.yardName ?? "YARD").uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }

                Text("Assign to track")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text("Sets the car's track of record for this yard. A track outside 1…\(board?.totalTracks ?? 0) is refused, and so is any car whose current yard is not this one.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Car picker
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("CAR")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    if allCars.isEmpty {
                        Text("No cars are at this yard on the live read.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(unassigned + allSpotted) { c in
                                    carChip(c, active: c.id == car?.id)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }

                // Track picker
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("DESTINATION TRACK")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    if tracks.isEmpty {
                        Text("This yard reports no tracks, so there is nothing to spot to.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                            ForEach(tracks) { t in
                                trackChip(number: t.number, occupied: t.cars.count, active: target == t.number)
                            }
                            unassignChip(active: target == nil)
                        }
                    }
                }

                // Truthful commit statement
                VStack(alignment: .leading, spacing: 6) {
                    Text(commitSentence)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This writes railcars.trackNumber only. It does NOT write a blockchain audit row and it broadcasts no live event — so the board re-reads itself after the write instead of waiting for a push it does not get.")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                if let err = assignError {
                    Text(err)
                        .font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !reach.isOnline {
                    Text("Offline — this move cannot be held for later. No rail action is eligible for offline queuing, so it would be lost rather than replayed.")
                        .font(EType.caption).foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await commitAssign() }
                } label: {
                    HStack {
                        Spacer()
                        if assigning {
                            ProgressView().tint(.white)
                        } else {
                            Text(target == nil ? "Return car to pool" : "Spot to track \(String(format: "%02d", target ?? 0))")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(car == nil || !reach.isOnline || assigning ? 0.6 : 1.0)
                .disabled(car == nil || !reach.isOnline || assigning)

                Color.clear.frame(height: 24)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var commitSentence: String {
        guard let car = assignCar else { return "Pick a car to spot." }
        let mark = car.mark ?? "car \(car.id)"
        if let t = assignTrack {
            let occ = (board?.tracks ?? []).first { $0.number == t }?.cars.count ?? 0
            return "\(mark) → track \(String(format: "%02d", t)) · \(occ) car\(occ == 1 ? "" : "s") on it now."
        }
        return "\(mark) → unassigned pool · the car stays at this yard with no track of record."
    }

    private func carChip(_ c: SlotCar665, active: Bool) -> some View {
        let s = SlotState665(status: c.status)
        return Button {
            assignCar = c
            assignError = nil
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.mark ?? "Car \(c.id)")
                    .font(.system(size: 11, weight: .heavy)).monospaced()
                    .foregroundStyle(active ? .white : palette.textPrimary)
                    .lineLimit(1)
                Text(c.track.map { "track \(String(format: "%02d", $0)) · \(s.label.lowercased())" } ?? "no track · \(s.label.lowercased())")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(active ? Color.white.opacity(0.85) : palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                Group {
                    if active { AnyView(LinearGradient.primary) }
                    else      { AnyView(palette.bgCard) }
                }
            )
            .overlay(Capsule().strokeBorder(active ? Color.clear : palette.borderFaint, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func trackChip(number: Int, occupied: Int, active: Bool) -> some View {
        Button {
            assignTrack = number
            assignError = nil
        } label: {
            VStack(spacing: 2) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(active ? .white : palette.textPrimary)
                Text(occupied == 0 ? "OPEN" : "\(occupied) CAR\(occupied == 1 ? "" : "S")")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(active ? Color.white.opacity(0.9)
                                            : (occupied == 0 ? Brand.success : palette.textTertiary))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                Group {
                    if active { AnyView(LinearGradient.diagonal) }
                    else      { AnyView(palette.bgCard) }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(active ? Color.clear
                                     : (occupied == 0 ? Brand.success.opacity(0.35) : palette.borderFaint),
                              lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func unassignChip(active: Bool) -> some View {
        Button {
            assignTrack = nil
            assignError = nil
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(active ? .white : palette.textSecondary)
                Text("POOL")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                Group {
                    if active { AnyView(LinearGradient.diagonal) }
                    else      { AnyView(palette.bgCard) }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(active ? Color.clear : palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Toast

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t.text)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(t.ok ? Brand.success : Brand.danger))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ text: String, ok: Bool) {
        withAnimation(.easeOut(duration: 0.18)) { toast = (text, ok) }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: - Data

    /// Catalog first, then the board for whichever yard is in scope. The catalog is what
    /// makes the yard of record real — there is no hardcoded yard id in this file.
    private func bootstrap() async {
        loading = true
        // zod: every getRailYards filter is `.optional()`, which REJECTS an explicit null.
        // Swift's synthesized encoder would emit one, so the optional filters are hand-rolled
        // with encodeIfPresent and simply omitted when unset.
        struct YardsIn: Encodable {
            let country: String?
            let limit: Int
            enum CodingKeys: String, CodingKey { case country, limit }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(country, forKey: .country)
                try c.encode(limit, forKey: .limit)
            }
        }
        do {
            let rows: [YardCatalogRow665] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: nil, limit: 50))
            self.yards = rows
            if selectedYardId == nil {
                selectedYardId = initialYardId.flatMap { id in rows.first { $0.id == id }?.id }
                    ?? rows.first?.id
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        await reloadBoard()
    }

    /// Fused board read. Occupancy is the spine; the railcar enrichment and the consist pull
    /// are best-effort so one dead leg degrades alone instead of blanking the ladder.
    private func reloadBoard() async {
        guard let yardId = selectedYardId else { loading = false; return }
        boardRequestId += 1
        let gen = boardRequestId
        loading = true

        struct CarsIn: Encodable { let yardId: Int; let limit: Int; let offset: Int }
        struct ConsistsIn: Encodable { let limit: Int; let offset: Int }

        // Fan out. The occupancy read is the spine; the other two legs are best-effort so a
        // dead enrichment degrades alone instead of blanking the ladder.
        async let occTask: YardTrackOccupancy =
            EusoTripAPI.shared.railShipments.getYardTrackOccupancy(yardId: yardId)
        async let carsTask: RailcarsEnvelope665 =
            EusoTripAPI.shared.query("railShipments.getRailcars",
                                     input: CarsIn(yardId: yardId, limit: Self.carsLimit, offset: 0))
        async let consistsTask: ConsistsEnvelope665 =
            EusoTripAPI.shared.query("railShipments.getTrainConsists",
                                     input: ConsistsIn(limit: Self.consistsLimit, offset: 0))

        let occ = try? await occTask
        let cars = ((try? await carsTask)?.railcars) ?? []
        let consists = ((try? await consistsTask)?.consists) ?? []
        let pull = Self.nextPull(from: consists, yardId: yardId)

        guard gen == boardRequestId else { return }

        guard let occ else {
            // The spine failed. Serve the cached snapshot if it is inside the ttl and mark it
            // loudly; otherwise refuse to paint anything at all.
            if let cached = SlotBoardCache665.load(yardId) {
                board = cached.value
                cacheAge = cached.age
                loadError = nil
            } else {
                board = nil
                cacheAge = nil
                loadError = "Could not read track occupancy for this yard. Nothing is being shown from cache — the last snapshot is older than \(SlotBoardCache665.ttlLabel)."
            }
            loading = false
            return
        }

        let yard = yards.first { $0.id == yardId }
        let byId = Dictionary(cars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // "Enriched" only means something when there is something to enrich. A genuinely
        // empty yard is enriched vacuously — otherwise the board would accuse a working
        // read of having failed.
        let occCarCount = occ.tracks.reduce(0) { $0 + $1.cars.count } + occ.unassigned.count
        let enriched = occCarCount == 0 || !cars.isEmpty

        func fuse(_ c: YardCar, fallbackTrack: Int?) -> SlotCar665 {
            let row = byId[c.id]
            return SlotCar665(
                id: c.id,
                mark: c.carNumber ?? row?.railcarNumber,
                carType: c.carType ?? row?.carType,
                status: c.status ?? row?.status,
                track: row?.trackNumber ?? fallbackTrack,
                lengthFeet: row?.lengthFeet,
                lastEventAt: row?.updatedAt
            )
        }

        let tracks = occ.tracks.map { t in
            SlotTrack665(number: t.trackNumber, cars: t.cars.map { fuse($0, fallbackTrack: t.trackNumber) })
        }
        let loose = occ.unassigned.map { fuse($0, fallbackTrack: nil) }

        let fused = SlotBoard665(
            yardId: occ.yardId,
            yardName: occ.yardName ?? yard?.name,
            city: yard?.city,
            state: yard?.state,
            country: yard?.country,
            yardType: yard?.yardType,
            totalTracks: occ.totalTracks ?? yard?.totalTracks,
            capacity: occ.capacity ?? yard?.capacity,
            utilizationPct: occ.utilizationPct,
            tracks: tracks,
            unassigned: loose,
            nextPullAt: pull?.departureTime,
            nextPullConsist: pull?.consistNumber,
            nextPullStatus: pull?.status,
            enriched: enriched
        )

        board = fused
        cacheAge = nil
        lastLiveAt = Date()
        loadError = nil
        SlotBoardCache665.store(fused)
        loading = false
    }

    /// NEXT PULL from `railShipments.getTrainConsists`. The proc has no yard filter, so the
    /// page is filtered here to consists ORIGINATING at this yard that are still building or
    /// ready and whose departureTime is still ahead. No qualifying row ⇒ nil ⇒ the tile
    /// renders "—". Nothing is extrapolated.
    static func nextPull(from consists: [ConsistRow665], yardId: Int) -> ConsistRow665? {
        consists
            .filter { c in
                guard c.originYardId == yardId else { return false }
                let s = (c.status ?? "").lowercased()
                guard s == "building" || s == "ready" else { return false }
                guard let d = parseISO(c.departureTime) else { return false }
                return d.timeIntervalSinceNow > 0
            }
            .min { a, b in
                (parseISO(a.departureTime) ?? .distantFuture) < (parseISO(b.departureTime) ?? .distantFuture)
            }
    }

    /// POST `railShipments.assignCarToTrack` (railShipments.ts:1039, MUTATION — mutation(),
    /// never query(); the server has no method override, so a GET here would be fault class S4).
    ///
    /// ONLINE_ONLY: the path is absent from the offline-eligibility table at
    /// EusoTripAPI.swift:1684, so an offline attempt hard-fails and nothing queues. The CTA is
    /// already disabled offline; this guard is the second lock.
    private func commitAssign() async {
        guard let yardId = selectedYardId, let car = assignCar else {
            assignError = "Pick a car to spot."
            return
        }
        guard reach.isOnline else {
            assignError = "Offline — a yard move cannot be queued on this device. Reconnect to spot the car."
            showToast("Offline — spot not sent", ok: false)
            return
        }

        /// zod: `trackNumber: z.coerce.number().int().nullable()`. NULLABLE, not optional —
        /// the key must be PRESENT and null is the legal "return to pool" value. encodeNil is
        /// explicit here; an encodeIfPresent would drop the key and the call would 400.
        struct In: Encodable {
            let yardId: Int
            let carId: Int
            let trackNumber: Int?
            enum CodingKeys: String, CodingKey { case yardId, carId, trackNumber }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(yardId, forKey: .yardId)
                try c.encode(carId, forKey: .carId)
                if let trackNumber { try c.encode(trackNumber, forKey: .trackNumber) }
                else { try c.encodeNil(forKey: .trackNumber) }
            }
        }

        assigning = true
        assignError = nil
        do {
            let res: AssignResult665 = try await EusoTripAPI.shared.mutation(
                "railShipments.assignCarToTrack",
                input: In(yardId: yardId, carId: car.id, trackNumber: assignTrack))
            let mark = car.mark ?? "Car \(car.id)"
            if let t = res.trackNumber {
                showToast("\(mark) spotted to track \(String(format: "%02d", t))", ok: true)
            } else {
                showToast("\(mark) returned to the unassigned pool", ok: true)
            }
            showAssign = false
            assignCar = nil
            // No WS_EVENT is broadcast for this write, so the board re-reads itself.
            await reloadBoard()
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            assignError = msg
            showToast("Spot failed", ok: false)
        }
        assigning = false
    }

    // MARK: - Formatting

    static func parseISO(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: iso) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: iso)
    }

    /// Elapsed hours as a yard-legible figure: "14h", "2d 3h", "45m".
    static func elapsed(_ hours: Double) -> String {
        if hours < 1 { return "\(max(Int(hours * 60), 0))m" }
        if hours < 48 { return "\(Int(hours))h" }
        let days = Int(hours / 24)
        let rem = Int(hours) - days * 24
        return rem == 0 ? "\(days)d" : "\(days)d \(rem)h"
    }

    /// Minutes to the next pull as "35m" / "2h 10m".
    static func durationShort(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - One ladder row
//
// Track label (mono, zero-padded, right-aligned) + one fixed-width cell per REAL car, left
// aligned. Row LENGTH is the information: a track with eight cars visibly out-runs a track
// with two. A track the server reported as empty draws an OPEN rail instead of cells — that
// is the only "open" this screen ever paints, because it is the only one the server states.

private struct SlotLadderRow665: View {
    @Environment(\.palette) private var palette

    static let rowHeight: CGFloat = 22
    private static let cellWidth: CGFloat = 26
    private static let cellHeight: CGFloat = 13
    private static let cellGap: CGFloat = 3
    private static let maxCells = 11

    let track: SlotTrack665
    let regime: FreeTimeRegime665
    let isTarget: Bool
    let onTap: () -> Void

    private var visible: [SlotCar665] { Array(track.cars.prefix(Self.maxCells)) }
    private var overflow: Int { max(0, track.cars.count - Self.maxCells) }

    /// Total occupied length in the yard-of-record's unit — real railcars.lengthFeet only.
    /// Nil when no car on this track reports a length.
    private var occupiedLength: String? {
        let feet = track.cars.compactMap { $0.lengthFeet }.reduce(0, +)
        guard feet > 0 else { return nil }
        return regime.length(feet: feet)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d", track.number))
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(isTarget ? Brand.blue : palette.textSecondary)
                .frame(width: 20, alignment: .trailing)

            if track.cars.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(Brand.success.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: Self.cellHeight)
                        .frame(maxWidth: .infinity)
                    Text("OPEN")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                }
            } else {
                HStack(spacing: Self.cellGap) {
                    ForEach(visible) { car in
                        cell(SlotState665(status: car.status))
                    }
                    if overflow > 0 {
                        Text("+\(overflow)")
                            .font(.system(size: 8, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textTertiary)
                            .frame(minWidth: 18)
                    }
                    Spacer(minLength: 0)
                    if let len = occupiedLength {
                        Text(len)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func cell(_ s: SlotState665) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(s.tint.opacity(s.fillOpacity))
            .frame(width: Self.cellWidth, height: Self.cellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(s.isOutlined ? s.tint.opacity(0.55) : Color.clear, lineWidth: 1)
            )
    }
}

#Preview("665 · Rail Yard Slot Inventory · Night") {
    RailYardSlotInventory_665(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("665 · Rail Yard Slot Inventory · Light") {
    RailYardSlotInventory_665(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
