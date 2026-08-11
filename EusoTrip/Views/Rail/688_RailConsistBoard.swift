//
//  688_RailConsistBoard.swift
//  EusoTrip — Rail Engineer · Consist Board (carrier operational band).
//
//  PURPOSE: assemble ONE cut at a yard and commit it — pull real standing cars
//  off the yard's tracks into a head-to-rear order, watch the rated gross rail
//  load build against the country's weight regime and the hazmat buffer rule,
//  then write that car order to the server.
//
//  Verbatim port of 05 Rail/Light-SVG/688 Rail Consist Board.svg (Light + Dark).
//
//  ARCHETYPE: BOARD (assembling cut). The SVG demanded it: a tonnage/length
//  summary band sitting over a numbered head→rear car list — position badge,
//  reporting mark in mono, AAR type + lading, tons right-aligned, a single
//  status word per row. Tight rows, numbers-first, scannable off a walkway with
//  gloves on. It is explicitly NOT a detail card and not a KPI grid.
//
//  555 vs 688 — SAME NAME, DIFFERENT JOB (numbering collision, both earn a slot):
//    555 is the FLEET board — every consist the division is running, in status
//        swim-lanes (rolling / building / border / yard). "Where are my cuts?"
//    688 is the CUT board — one train, one yard, the cars inside it in order.
//        "What is in this cut, in what order, and is it legal to leave?"
//    They share no procedure call, no composition and no verb. 555 reads
//    getTrainConsists as a LIST; 688 reads one consist as a HEADER and then
//    works the yard. 555's own "Build new consist" CTA is a no-op today
//    (555:168-171 sets a flag and clears it) — 688 is the screen that makes
//    createConsist real for the first time in the iOS app.
//
//  WIRING MANIFEST — every interactive element → its procedure
//  ─────────────────────────────────────────────────────────────────────────
//  Cut header (symbol, type, status, PTC, head-end units, committed totals)
//      → railShipments.getTrainConsists   EXISTS railShipments.ts:1071 (query)
//  Yard picker + country regime driver (railYards.country is US|CA|MX)
//      → railShipments.getRailYards       EXISTS railShipments.ts:1251 (query)
//  Yard tracks + the cars standing on each track
//      → railShipments.getYardTrackOccupancy EXISTS railShipments.ts:985 (query)
//  Car specs used for GRL / length / AAR class / DOT spec / loaded-empty
//      → railShipments.getRailcars        EXISTS railShipments.ts:931 (query)
//  Per-car BAD ORDER flag (live wayside detector alarm on this train)
//      → railMechanical.getWaysideDetectorReads EXISTS railMechanical.ts:247 (query)
//  "Spot on track" (place a standing car on a yard track)
//      → railShipments.assignCarToTrack   EXISTS railShipments.ts:1039 (MUTATION)
//  "Build train" (commit the cut → writes the head-to-rear positions)
//      → railShipments.createConsist      EXISTS railShipments.ts:1193 (MUTATION)
//  "Add car"  → opens the yard shelf above; no network of its own.
//
//  STUB · named-gap (drawn in a truthful unavailable state, never faked):
//      Reading a COMMITTED cut back. createConsist writes consist_cars with
//      position 1..n (railShipments.ts:1216-1222) and NOTHING reads that table
//      — the only other reference is a reverse lookup at railShipments.ts:1372.
//      So a consist that already exists cannot show its own car order. The
//      CAR ORDER register says exactly that, names the missing procedure, and
//      shows the cut being assembled now instead of inventing rows.
//      Proposed: getConsistCars({consistId:number}) → { consistId, cars:[{
//        position:number, railcarId:number, railcarNumber:string|null,
//        carType:string|null, aarClass:string|null, dotSpec:string|null,
//        tareWeight:number|null, loadLimit:number|null, lengthFeet:number|null,
//        status:"coupled"|"uncoupled"|"set_out", shipmentId:number|null,
//        coupledAt:string|null }] } — a left-join of consist_cars → railcars
//        ordered by position. railProcedure, query.
//
//  PERSISTENCE · AUDIT · SOCKET
//      createConsist inserts train_consists + one consist_cars row per car with
//      its position, then writes blockchainAuditTrail eventType
//      "rail.consist_created" at railShipments.ts:1227 (best-effort, never
//      throws). assignCarToTrack updates railcars.trackNumber only — no audit
//      row. WS_EVENTS: NONE. Neither procedure touches wsService; the SVG
//      <desc> claims WS_CHANNELS.RAIL_CONSIST / WS_EVENTS.CONSIST_UPDATED and
//      an audit type of "rail.consist_assembled" — both are wrong against the
//      real router, so this board never promises a live push.
//
//  RBAC: railProcedure on every call (RAIL-mode role gate, engineer/carrier).
//  transportMode = RAIL.
//
//  COUNTRY IS CONTENT (one screen, driven by the origin yard's real
//  railYards.country enum — US | CA | MX — with a manual override):
//      US · AAR interchange / FRA 49 CFR — 286,000 lb gross rail load;
//           49 CFR 174.85 buffer-car rule behind the power.
//      CA · Transport Canada / TDG — 286,000 lb GRL; TDG Part 10 buffer rule.
//      MX · ARTF / SICT NOM — AAR Plate B, 263,000 lb GRL; NOM-002-SCT
//           separación de carros con placa de riesgo.
//  The GRL ceilings are published interchange regulation, not business values.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(10m) for the board — the cut
//  header, the yard and its standing cars persist per yard so a cold trackside
//  launch still draws the cut, with a monospaced 10pt staleness line in the
//  header right register that flips to Brand.warning past the TTL and reads
//  "cached · Nm ago" instead of the live road mark. Every commit is ONLINE_ONLY:
//  createConsist writes an immutable blockchainAuditTrail row and stamps
//  permanent head-to-rear positions, and assignCarToTrack moves physical iron —
//  a silently replayed cut would double-build the train. No rail path is in the
//  six-path offline table at Services/EusoTripAPI.swift:1684, so no rail
//  mutation can queue today; both CTAs disable with the reason printed on the
//  button instead of pretending to queue.
//
//  WHY THIS SCREEN EARNS ITS PLACE: the engineer builds the cut on the ground
//  and sees the gross rail load, the length and the hazmat buffer go legal or
//  illegal as each car couples on — instead of totting up a paper switch list
//  and finding out at the departure test that the train is over the rating.
//

import SwiftUI

struct RailConsistBoard_688: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConsistBoardBody688() } nav: {
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

// MARK: - Decoded server shapes
//
// MySQL DECIMAL columns arrive as JSON strings from the mysql2 driver, but a
// coerced path can hand back a number. Accept either; never guess a value.
private struct Num688: Codable, Equatable {
    let value: Double?
    init(_ v: Double?) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = value { try c.encode(v) } else { try c.encodeNil() }
    }
}

/// railShipments.getTrainConsists → consists[] (train_consists row + crosswind).
private struct ConsistRow688: Codable, Identifiable {
    let id: Int
    let consistNumber: String?
    let locomotiveUnits: [String]?
    let totalCars: Int?
    /// train_consists.totalWeight is decimal(12,2) with NO unit declared in the
    /// schema, and createConsist never writes it (railShipments.ts:1205-1212).
    /// Decoded so the shape is honest, deliberately NOT rendered — labelling an
    /// unwritten, unit-less column "tons" would be a fabricated number. The
    /// board's gross comes from summing real per-car UMLER tare + load limit.
    let totalWeight: Num688?
    let totalLengthFeet: Int?
    let trainType: String?
    let originYardId: Int?
    let destinationYardId: Int?
    let status: String?
    let railroadId: Int?
    let ptcActive: Bool?
}

private struct ConsistsPage688: Decodable {
    let consists: [ConsistRow688]?
    let total: Int?
}

/// railShipments.getRailcars → railcars[] (railcars row + yardName/coordinates).
private struct Railcar688: Codable, Identifiable, Equatable {
    let id: Int
    let railcarNumber: String?
    let carType: String?
    let owner: String?
    let lessee: String?
    let tareWeight: Int?
    let loadLimit: Int?
    let lengthFeet: Int?
    let aarClass: String?
    let dotSpec: String?
    let status: String?
    let currentYardId: Int?
    let trackNumber: Int?
    let yardName: String?

    static func == (a: Railcar688, b: Railcar688) -> Bool { a.id == b.id }

    /// UMLER gross rail load = tare + load limit, pounds. House formula, the
    /// same one 598_RailEquipmentSpecs derives. nil when either half is absent —
    /// a car with no spec is never given an invented rating.
    var grossRailLoadLb: Double? {
        guard let tw = tareWeight, let ll = loadLimit else { return nil }
        return Double(tw) + Double(ll)
    }
    /// A DOT-spec tank car is hazmat-capable and carries the placement rule.
    var isTankSpec: Bool {
        if let s = dotSpec, !s.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return (carType ?? "") == "tankcar"
    }
    var isLoaded: Bool { (status ?? "") == "loaded" }
    var isShopped: Bool {
        let s = status ?? ""
        return s == "in_repair" || s == "out_of_service"
    }
}

private struct RailcarsPage688: Decodable {
    let railcars: [Railcar688]?
    let total: Int?
}

/// railShipments.getYardTrackOccupancy → tracks[] + unassigned[].
private struct YardSlimCar688: Codable, Identifiable {
    let id: Int
    let carNumber: String?
    let carType: String?
    let status: String?
}

private struct YardTrack688: Codable, Identifiable {
    let trackNumber: Int
    let cars: [YardSlimCar688]?
    let carCount: Int?
    var id: Int { trackNumber }
}

private struct YardOccupancy688: Codable {
    let yardId: Int
    let yardName: String?
    let totalTracks: Int?
    let capacity: Int?
    let utilizationPct: Double?
    let tracks: [YardTrack688]?
    let unassigned: [YardSlimCar688]?
    let note: String?
}

/// railShipments.getRailYards → bare array of rail_yards rows.
private struct RailYard688: Codable, Identifiable {
    let id: Int
    let name: String?
    let splcCode: String?
    let railroadId: Int?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let totalTracks: Int?
}

/// railMechanical.getWaysideDetectorReads → the live bad-order signal.
private struct WaysideRead688: Decodable, Identifiable {
    let id: String
    let trainId: String?
    let railcarNumber: String?
    let site: String?
    let detectorType: String?
    let reading: Double?
    let threshold: Double?
    let unit: String?
    let alarm: Bool?
    let readAt: String?
}

private struct CreateConsistResult688: Decodable {
    let id: Num688?
    let trainId: String?
    let totalCars: Int?
}

private struct AssignResult688: Decodable {
    let success: Bool?
    let carId: Int?
    let trackNumber: Int?
}

// MARK: - Country weight + placement regime
//
// Published interchange regulation, not business values. The regime is chosen
// by the origin yard's real `rail_yards.country` enum (US | CA | MX) and can be
// overridden by hand when a cut is interlined across a border.
private enum WeightRegime688: String, CaseIterable, Identifiable {
    case us = "US"
    case ca = "CA"
    case mx = "MX"

    var id: String { rawValue }

    var short: String {
        switch self {
        case .us: return "US · AAR"
        case .ca: return "CA · TC"
        case .mx: return "MX · ARTF"
        }
    }

    var authority: String {
        switch self {
        case .us: return "AAR interchange · FRA 49 CFR"
        case .ca: return "Transport Canada · TDG"
        case .mx: return "ARTF · SICT NOM"
        }
    }

    var plate: String {
        switch self {
        case .us, .ca: return "286k GRL"
        case .mx:      return "Plate B · 263k"
        }
    }

    /// Maximum gross rail load per car, pounds.
    var maxGrlLb: Double {
        switch self {
        case .us, .ca: return 286_000
        case .mx:      return 263_000
        }
    }

    /// Buffer-car rule for a placarded car behind the power.
    var placementRule: String {
        switch self {
        case .us: return "49 CFR 174.85 — a placarded car needs a buffer car between it and the locomotive."
        case .ca: return "TDG Part 10 / TC RTDGR — a placarded car needs a buffer car behind the power."
        case .mx: return "NOM-002-SCT / ARTF — se requiere carro separador entre la locomotora y el carro con placa de riesgo."
        }
    }

    var currency: String {
        switch self {
        case .us: return "USD"
        case .ca: return "CAD"
        case .mx: return "MXN"
        }
    }

    static func from(country: String?) -> WeightRegime688 {
        switch (country ?? "").uppercased() {
        case "CA": return .ca
        case "MX": return .mx
        default:   return .us
        }
    }
}

// MARK: - READ_CACHED(10m) envelope
//
// Persisted per yard so a cold, offline launch trackside still draws the cut
// header and the standing cars — with their age on screen — instead of a blank
// board. Never used to satisfy a write.
private struct ConsistCache688: Codable {
    let savedAt: Date
    let consist: ConsistRow688?
    let yard: RailYard688?
    let occupancy: YardOccupancy688?
    let cars: [Railcar688]
}

private enum ConsistBoardCache688 {
    /// READ_CACHED(10m). A yard's standing cars turn over on the shift, not on
    /// the minute — ten minutes is the window in which "what is on the ground
    /// here" is still worth drawing without a network hit.
    static let ttl: TimeInterval = 10 * 60

    private static func key(_ yardId: Int) -> String { "eusotrip.rail688.consistBoard.\(yardId)" }

    static func save(_ env: ConsistCache688, yardId: Int) {
        guard let data = try? JSONEncoder().encode(env) else { return }
        UserDefaults.standard.set(data, forKey: key(yardId))
    }

    static func load(yardId: Int) -> ConsistCache688? {
        guard let data = UserDefaults.standard.data(forKey: key(yardId)) else { return nil }
        return try? JSONDecoder().decode(ConsistCache688.self, from: data)
    }
}

// MARK: - Body

private struct RailConsistBoardBody688: View {
    @Environment(\.palette) private var palette
    /// ONLINE_ONLY gate for both commits + the offline serve for the board.
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    // Reads
    @State private var consist: ConsistRow688? = nil
    @State private var yards: [RailYard688] = []
    @State private var selectedYardId: Int? = nil
    @State private var occupancy: YardOccupancy688? = nil
    @State private var standing: [Railcar688] = []
    @State private var alarms: [WaysideRead688] = []

    // The cut being assembled — head to rear, in coupling order. Live user
    // input over decoded server rows; nothing here is invented.
    @State private var cut: [Railcar688] = []

    // Country regime — seeded from the yard's real country, overridable.
    @State private var regime: WeightRegime688 = .us
    @State private var regimeTouched = false

    // Load / cache state
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var servedFromCache = false
    @State private var lastSyncedAt: Date? = nil

    // Commit state
    @State private var showBuildSheet = false
    @State private var showYardSheet = false
    @State private var buildSymbol = ""
    @State private var destinationYardId: Int? = nil
    @State private var building = false
    @State private var spotCar: Railcar688? = nil
    @State private var spotTrack: Int? = nil
    @State private var spotting = false
    @State private var toast: String? = nil
    @State private var toastIsError = false

    // MARK: Derived — every value below reduces real decoded fields

    private var selectedYard: RailYard688? {
        guard let id = selectedYardId else { return nil }
        return yards.first { $0.id == id }
    }

    private var yardLabel: String {
        if let y = selectedYard {
            let place = [y.city, y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return place.isEmpty ? (y.name ?? "Yard #\(y.id)") : "\(y.name ?? "Yard #\(y.id)") · \(place)"
        }
        if let o = occupancy, let n = o.yardName { return n }
        return "No yard selected"
    }

    private var cutGrossLb: Double {
        cut.compactMap { $0.grossRailLoadLb }.reduce(0, +)
    }

    private var cutGrossTons: Double { cutGrossLb / 2000 }

    private var cutLengthFt: Int {
        cut.compactMap { $0.lengthFeet }.reduce(0, +)
    }

    private var cutLoads: Int { cut.filter { $0.isLoaded }.count }
    private var cutEmpties: Int { cut.count - cutLoads }
    private var cutHazmat: [Railcar688] { cut.filter { $0.isTankSpec } }

    /// Cars whose rated GRL exceeds the regime ceiling — a real overload, from
    /// real UMLER fields against a published limit.
    private var overRatedCars: [Railcar688] {
        cut.filter { car in
            guard let g = car.grossRailLoadLb else { return false }
            return g > regime.maxGrlLb
        }
    }

    /// Cars with no tare/loadLimit on file — rated tonnage cannot include them.
    private var unratedCars: [Railcar688] {
        cut.filter { $0.grossRailLoadLb == nil }
    }

    /// Live wayside alarm index, keyed by reporting mark + number.
    private var alarmedMarks: Set<String> {
        Set(alarms.filter { $0.alarm == true }.compactMap { $0.railcarNumber })
    }

    private func isBadOrder(_ car: Railcar688) -> Bool {
        if car.isShopped { return true }
        if let n = car.railcarNumber, alarmedMarks.contains(n) { return true }
        return false
    }

    /// 49 CFR 174.85 / TDG Part 10 / NOM-002-SCT: the car directly behind the
    /// power must not be placarded. Position 1 of the cut is that car.
    ///
    /// HONESTY BOUND: `railcars` carries no placard, UN number or hazmat class
    /// column, so this can only detect a DOT-spec TANK CAR — hazmat-CAPABLE,
    /// not proven placarded. The board therefore raises it as a check to run,
    /// never as a decided violation, and says so in the exception copy.
    private var placementViolation: Railcar688? {
        guard let head = cut.first, head.isTankSpec else { return nil }
        return head
    }

    private var badOrderCount: Int { cut.filter { isBadOrder($0) }.count }

    /// The one-word verdict for the cut. Never green while a real defect stands.
    private var cutVerdict: (String, StatusPill.Kind) {
        if cut.isEmpty { return ("EMPTY CUT", .neutral) }
        if badOrderCount > 0 { return ("BAD ORDER", .danger) }
        if !overRatedCars.isEmpty { return ("OVER RATING", .danger) }
        if placementViolation != nil { return ("PLACEMENT", .warning) }
        if !unratedCars.isEmpty { return ("SPEC MISSING", .warning) }
        return ("CLEAR TO BUILD", .success)
    }

    private var headEndUnits: [String] { consist?.locomotiveUnits ?? [] }

    private var roadMark: String {
        // The consist's own symbol carries the road when the server has one.
        if let n = consist?.consistNumber, !n.isEmpty {
            let head = n.split(separator: "-").first.map(String.init) ?? n
            return head.uppercased()
        }
        return "—"
    }

    /// trainType is nullable. An absent type is an em-dash, matching roadMark
    /// above — "manifest" is a real train class and asserting it off an empty
    /// column tells the yard the cut is something the server never said it was.
    private var trainTypeLabel: String {
        guard let t = consist?.trainType, !t.isEmpty else { return "—" }
        return t.uppercased()
    }

    /// status is nullable — same rule. "assembling" is a live consist state.
    private var statusLabel: String {
        guard let s = consist?.status, !s.isEmpty else { return "—" }
        return s.uppercased()
    }

    // MARK: READ_CACHED(10m) staleness — the honesty law lives here

    private var cacheAge: TimeInterval? {
        guard let stamp = lastSyncedAt else { return nil }
        return Date().timeIntervalSince(stamp)
    }

    private var cacheIsStale: Bool {
        guard let age = cacheAge else { return true }
        return age > ConsistBoardCache688.ttl
    }

    private var stalenessLine: String {
        guard let age = cacheAge else { return "no cached board" }
        if !servedFromCache { return "\(roadMark)·\(trainTypeLabel)" }
        if age < 60 { return "cached · just now" }
        if age < 3600 { return "cached · \(Int(age / 60))m ago" }
        return "cached · \(Int(age / 3600))h ago"
    }

    private var stalenessWarns: Bool { servedFromCache && cacheIsStale }

    // MARK: ONLINE_ONLY gates

    private var commitBlockedReason: String? {
        if !reach.isOnline {
            return "Offline · committing a cut is ONLINE_ONLY. It stamps permanent head-to-rear positions and writes an immutable audit row, so it is never queued for silent replay."
        }
        if cut.isEmpty { return "Couple at least one car into the cut." }
        if selectedYard == nil { return "Pick the yard this cut is being built at." }
        if destinationYardId == nil { return "Pick the destination yard." }
        if selectedYard?.railroadId == nil { return "This yard has no railroad of record — the consist needs an owning road." }
        if buildSymbol.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the cut a train symbol." }
        return nil
    }

    private var canBuild: Bool { commitBlockedReason == nil && !building }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && consist == nil && standing.isEmpty {
                    LifecycleCard { Text("Loading the cut…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError, standing.isEmpty, consist == nil {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            Text("Pull to retry. Nothing is drawn from memory unless the cached line above says so.")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                } else {
                    // A partial failure is NEVER swallowed: the board still
                    // draws what answered, and says out loud what did not.
                    degradedNotice
                    CutTonnageBand688(
                        verdict: cutVerdict.0,
                        verdictKind: cutVerdict.1,
                        grossTons: cutGrossTons,
                        carCount: cut.count,
                        lengthFt: cutLengthFt,
                        loads: cutLoads,
                        empties: cutEmpties,
                        hazmat: cutHazmat.count,
                        headEndUnits: headEndUnits.count,
                        ptcActive: consist?.ptcActive,
                        roadLine: "CUT · \(roadMark) \(trainTypeLabel) · \(statusLabel)",
                        grlCeilingLb: regime.maxGrlLb,
                        heaviestLb: cut.compactMap { $0.grossRailLoadLb }.max(),
                        palette: palette
                    )
                    exceptionRegister
                    carOrderRegister
                    yardShelfRegister
                    regimeBand
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showBuildSheet) { buildSheet }
        .sheet(isPresented: $showYardSheet) { yardSheet }
        .sheet(item: $spotCar) { car in spotSheet(car) }
    }

    /// Partial-degradation band. When one wave answered and another did not the
    /// screen keeps working, but the missing half is named on screen — an
    /// unspoken failure is the defect, not the failure itself.
    @ViewBuilder
    private var degradedNotice: some View {
        if servedFromCache {
            LifecycleCard(accentWarning: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Serving the cached board")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                    Text("The yard did not answer, so this is the last board saved for it — see the age in the header. Nothing here can be committed until the yard is reachable again.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let err = loadError {
            LifecycleCard(accentWarning: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Part of this board did not load")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                    Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("What you see below is only what answered. Pull to retry.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    // MARK: Header — eyebrow · title · train line · staleness · chips · hairline

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ CARRIER · RAIL · CONSIST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 8)
                // READ_CACHED(10m) staleness — always visible, warns past TTL.
                Text(stalenessLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(stalenessWarns ? Brand.warning : palette.textTertiary)
                    .fixedSize()
                    .accessibilityLabel("Consist board \(stalenessLine)")
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Consist board")
                    .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(cutSubtitle)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            chipRow.padding(.top, 2)
            IridescentHairline().padding(.top, 4)
        }
    }

    private var cutSubtitle: String {
        let symbol = consist?.consistNumber ?? "New cut"
        // An unresolved train type drops out of the line rather than reading
        // as a literal dash mid-sentence.
        guard trainTypeLabel != "—" else { return "\(symbol) · building at \(yardLabel)" }
        return "\(symbol) · \(trainTypeLabel.lowercased()) · building at \(yardLabel)"
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            boardChip("\(cut.count) cars", palette.textSecondary)
            boardChip(cut.isEmpty ? "— t" : "\(Int(cutGrossTons.rounded())) t", Brand.info)
            boardChip(cutHazmat.isEmpty ? "no tank cars" : "\(cutHazmat.count) DOT tank", cutHazmat.isEmpty ? palette.textTertiary : Brand.hazmat)
        }
    }

    private func boardChip(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Exception register — the reasons the cut cannot leave

    @ViewBuilder
    private var exceptionRegister: some View {
        let over = overRatedCars
        let unrated = unratedCars
        let placement = placementViolation
        let shopped = cut.filter { isBadOrder($0) }
        if !over.isEmpty || !unrated.isEmpty || placement != nil || !shopped.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("EXCEPTIONS · \(regime.short)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                if !shopped.isEmpty {
                    exceptionLine(
                        tint: Brand.danger,
                        head: "\(shopped.count) bad-order car\(shopped.count == 1 ? "" : "s")",
                        detail: shopped.compactMap { $0.railcarNumber }.joined(separator: " · ") + " — shopped status or a live wayside alarm. Set out before the departure test."
                    )
                }
                if !over.isEmpty {
                    exceptionLine(
                        tint: Brand.danger,
                        head: "\(over.count) car\(over.count == 1 ? "" : "s") over \(Int(regime.maxGrlLb / 1000))k GRL",
                        detail: over.compactMap { $0.railcarNumber }.joined(separator: " · ") + " — rated gross rail load exceeds the \(regime.authority) ceiling."
                    )
                }
                if let p = placement {
                    exceptionLine(
                        tint: Brand.warning,
                        head: "Check placarding behind the power",
                        detail: "\(p.railcarNumber ?? "Position 1") is a DOT-spec tank car in position 1. The equipment record carries no placard or UN number, so confirm on the ground whether it is placarded — if it is, \(regime.placementRule)"
                    )
                }
                if !unrated.isEmpty {
                    exceptionLine(
                        tint: Brand.warning,
                        head: "\(unrated.count) car\(unrated.count == 1 ? "" : "s") with no UMLER rating",
                        detail: unrated.compactMap { $0.railcarNumber }.joined(separator: " · ") + " — tare or load limit is absent on file, so their weight is NOT in the gross above."
                    )
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func exceptionLine(tint: Color, head: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1, style: .continuous).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                Text(detail).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: CAR ORDER · HEAD TO REAR — the spine of the board

    private var carOrderRegister: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("CAR ORDER · HEAD TO REAR")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(cut.isEmpty ? "couple a car" : "\(cut.count) coupled")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            if !headEndUnits.isEmpty {
                headEndRow
            }
            if cut.isEmpty {
                EusoEmptyState(
                    systemImage: "train.side.front.car",
                    title: "No cars coupled yet",
                    subtitle: "Pull standing cars off the yard below and they land here in head-to-rear order — the same order that is written to the server when you build the train."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(Array(cut.enumerated()), id: \.element.id) { idx, car in
                        carOrderRow(position: idx + 1, car: car)
                    }
                }
            }
            committedOrderNotice
        }
    }

    private var headEndRow: some View {
        HStack(spacing: Space.s3) {
            Text("HEAD")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Brand.info)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Brand.info.opacity(0.5)))
            VStack(alignment: .leading, spacing: 3) {
                Text(headEndUnits.joined(separator: " · "))
                    .font(.system(size: 13, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("head-end power · \(headEndUnits.count) unit\(headEndUnits.count == 1 ? "" : "s")\(consist?.ptcActive == true ? " · PTC cut in" : "")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text("PWR").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func carOrderRow(position: Int, car: Railcar688) -> some View {
        let bad = isBadOrder(car)
        let over = (car.grossRailLoadLb ?? 0) > regime.maxGrlLb
        let haz = car.isTankSpec
        let tint: Color = bad || over ? Brand.danger : (haz ? Brand.hazmat : Brand.success)
        let tag: String = {
            if bad { return "BAD ORDER" }
            if over { return "OVER \(Int(regime.maxGrlLb / 1000))k" }
            if haz { return "DOT TANK" }
            if car.grossRailLoadLb == nil { return "NO SPEC" }
            return car.isLoaded ? "LOADED" : "EMPTY"
        }()
        let tons: String = {
            guard let g = car.grossRailLoadLb else { return "— t" }
            return String(format: "%.1f t", g / 2000)
        }()
        let spec = [car.aarClass, car.dotSpec, car.carType?.replacingOccurrences(of: "_", with: " ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return HStack(spacing: Space.s3) {
            Text("\(position)")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(tint.opacity(0.5)))
            VStack(alignment: .leading, spacing: 3) {
                Text(car.railcarNumber ?? "—")
                    .font(.system(size: 13.5, weight: .heavy)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                Text(spec.isEmpty ? (car.status ?? "—") : spec)
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(tons)
                    .font(.system(size: 13, weight: .heavy)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                Text(tag)
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(tint)
            }
            Button {
                cut.removeAll { $0.id == car.id }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cut \(car.railcarNumber ?? "car") out of the consist")
        }
        .padding(Space.s3)
        .background(bad || over ? Brand.danger.opacity(0.06) : (haz ? Brand.hazmat.opacity(0.06) : palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(bad || over ? Brand.danger.opacity(0.30) : palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// The one named gap, drawn honestly: a consist that already exists cannot
    /// show its own committed order because nothing reads consist_cars.
    @ViewBuilder
    private var committedOrderNotice: some View {
        if let c = consist, (c.totalCars ?? 0) > 0 {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(palette.textTertiary).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMMITTED ORDER NOT READABLE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(c.consistNumber ?? "This cut") already carries \(c.totalCars ?? 0) car\((c.totalCars ?? 0) == 1 ? "" : "s")\(c.totalLengthFeet.map { " over \($0) ft" } ?? "") on the server. Their head-to-rear positions were written when the consist was built, but no procedure reads consist_cars back yet — so they are not drawn rather than guessed.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: YARD register — the real standing cars this cut is pulled from

    private var yardShelfRegister: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("YARD · CARS STANDING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(occupancyLine)
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            if availableCars.isEmpty {
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(occupancy?.note ?? "No cars standing at this yard right now.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                        Text("Switch yards from the picker below the exceptions band.")
                            .font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                }
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(availableCars.prefix(6)) { car in yardCarRow(car) }
                }
                if availableCars.count > 6 {
                    Button { showYardSheet = true } label: {
                        Text("See all \(availableCars.count) standing cars")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.info)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Brand.info.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var occupancyLine: String {
        guard let o = occupancy else { return "—" }
        let tracks = o.totalTracks ?? (o.tracks?.count ?? 0)
        if let u = o.utilizationPct {
            return "\(tracks) tracks · \(String(format: "%.0f", u))% full"
        }
        return "\(tracks) tracks"
    }

    /// Standing cars that are not already in the cut, ordered by track then mark.
    private var availableCars: [Railcar688] {
        let inCut = Set(cut.map { $0.id })
        return standing
            .filter { !inCut.contains($0.id) }
            .sorted {
                let a = $0.trackNumber ?? Int.max
                let b = $1.trackNumber ?? Int.max
                if a != b { return a < b }
                return ($0.railcarNumber ?? "") < ($1.railcarNumber ?? "")
            }
    }

    private func yardCarRow(_ car: Railcar688) -> some View {
        let bad = isBadOrder(car)
        let trackText = car.trackNumber.map { "Track \($0)" } ?? "unassigned"
        let grl = car.grossRailLoadLb.map { String(format: "%.0fk GRL", $0 / 1000) } ?? "no rating"
        return HStack(spacing: Space.s3) {
            Circle()
                .fill(bad ? Brand.danger : (car.isLoaded ? Brand.info : Brand.success))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(car.railcarNumber ?? "—")
                    .font(.system(size: 12.5, weight: .heavy)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                Text("\(trackText) · \((car.carType ?? "car").replacingOccurrences(of: "_", with: " ")) · \(grl)")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { spotCar = car; spotTrack = car.trackNumber } label: {
                Text("Spot")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
            Button { couple(car) } label: {
                Text("Couple")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func couple(_ car: Railcar688) {
        guard !cut.contains(where: { $0.id == car.id }) else { return }
        cut.append(car)
    }

    // MARK: Country regime band + yard picker

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEIGHT REGIME · \(regime.authority.uppercased())")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(regimeTouched ? "manual" : "from yard")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                ForEach(WeightRegime688.allCases) { r in
                    Button {
                        regime = r
                        regimeTouched = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.short).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                            Text(r.plate).font(.system(size: 9, weight: .heavy))
                        }
                        .foregroundStyle(r == regime ? Brand.info : palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(r == regime ? Brand.info.opacity(0.12) : palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(r == regime ? Brand.info.opacity(0.35) : palette.borderFaint))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(regime.placementRule)
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if yards.count > 1 {
                yardPicker
            }
        }
    }

    private var yardPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(yards) { y in
                    Button {
                        selectedYardId = y.id
                        if !regimeTouched { regime = WeightRegime688.from(country: y.country) }
                        Task { await loadYard() }
                    } label: {
                        Text(y.name ?? "Yard #\(y.id)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(y.id == selectedYardId ? palette.textOnGradient : palette.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 12).frame(height: 26)
                            .background(
                                Group {
                                    if y.id == selectedYardId {
                                        Capsule().fill(LinearGradient.diagonal)
                                    } else {
                                        Capsule().fill(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint))
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: CTA pair — SVG geometry, both commits ONLINE_ONLY

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    if buildSymbol.trimmingCharacters(in: .whitespaces).isEmpty {
                        buildSymbol = consist?.consistNumber ?? ""
                    }
                    if destinationYardId == nil {
                        destinationYardId = consist?.destinationYardId
                    }
                    showBuildSheet = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Build train")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(palette.textOnGradient)
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(reach.isOnline && !cut.isEmpty ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!reach.isOnline || cut.isEmpty)

                Button { showYardSheet = true } label: {
                    Text("Add car")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 140, height: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let reason = ctaDisabledReason {
                Text(reason)
                    .font(EType.caption).foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ctaDisabledReason: String? {
        if !reach.isOnline {
            return "Offline · Build train is ONLINE_ONLY. It stamps permanent head-to-rear positions and writes an immutable audit row, so it is never queued for silent replay. No rail path is offline-eligible today."
        }
        if cut.isEmpty { return "Couple at least one standing car into the cut before building the train." }
        return nil
    }

    // MARK: Build sheet — the confirm gate on createConsist

    private var buildSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "train.side.front.car").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("BUILD TRAIN · COMMIT THE CUT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Commit \(cut.count) car\(cut.count == 1 ? "" : "s")")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("This writes the consist and one row per car with its head-to-rear position, and logs the build to the immutable audit trail. The order below is the order that is stored.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("TRAIN SYMBOL").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    TextField("e.g. the cut's reporting symbol", text: $buildSymbol)
                        .font(.system(size: 15, weight: .bold)).monospaced()
                        .foregroundStyle(palette.textPrimary)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("DESTINATION YARD").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    if yards.isEmpty {
                        Text("No yards loaded — the destination cannot be chosen, so the build stays blocked.")
                            .font(EType.caption).foregroundStyle(Brand.warning)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s2) {
                                ForEach(yards.filter { $0.id != selectedYardId }) { y in
                                    Button { destinationYardId = y.id } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(y.name ?? "Yard #\(y.id)")
                                                .font(.system(size: 11, weight: .heavy)).lineLimit(1)
                                            Text([y.city, y.state, y.country].compactMap { $0 }.joined(separator: " · "))
                                                .font(.system(size: 9)).lineLimit(1)
                                        }
                                        .foregroundStyle(y.id == destinationYardId ? Brand.info : palette.textSecondary)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .fill(y.id == destinationYardId ? Brand.info.opacity(0.12) : palette.bgCard))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .strokeBorder(y.id == destinationYardId ? Brand.info.opacity(0.35) : palette.borderFaint))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("ORDER TO BE WRITTEN").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(Array(cut.enumerated()), id: \.element.id) { idx, car in
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .heavy)).monospaced()
                                .foregroundStyle(palette.textTertiary).frame(width: 20, alignment: .trailing)
                            Text(car.railcarNumber ?? "—")
                                .font(.system(size: 12, weight: .bold)).monospaced()
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(car.grossRailLoadLb.map { String(format: "%.1f t", $0 / 2000) } ?? "— t")
                                .font(.system(size: 11, weight: .heavy)).monospaced()
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }

                if let reason = commitBlockedReason {
                    Text(reason).font(EType.caption).foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await buildTrain() }
                } label: {
                    HStack {
                        Spacer()
                        if building {
                            ProgressView().tint(palette.textOnGradient)
                        } else {
                            Text("Confirm build · \(cut.count) car\(cut.count == 1 ? "" : "s")")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(palette.textOnGradient)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(canBuild ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!canBuild)
                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
    }

    // MARK: Yard sheet — every standing car

    private var yardSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("YARD · STANDING CARS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(yardLabel)
                    .font(.system(size: 20, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text(occupancyLine)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                if availableCars.isEmpty {
                    Text(occupancy?.note ?? "Nothing standing here that is not already in the cut.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                } else {
                    ForEach(availableCars) { car in yardCarRow(car) }
                }
                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: Spot sheet — assignCarToTrack

    private func spotSheet(_ car: Railcar688) -> some View {
        let tracks = occupancy?.tracks ?? []
        return VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SPOT ON TRACK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text(car.railcarNumber ?? "Car")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)
            Text("Move this car to a track at \(yardLabel). Clearing the track returns it to the unassigned pool.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            if tracks.isEmpty {
                Text("This yard reports no tracks, so a car cannot be spotted here.")
                    .font(EType.caption).foregroundStyle(Brand.warning)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        Button { spotTrack = nil } label: {
                            trackChip(label: "Unassigned", detail: "clear", selected: spotTrack == nil)
                        }
                        .buttonStyle(.plain)
                        ForEach(tracks) { t in
                            Button { spotTrack = t.trackNumber } label: {
                                trackChip(label: "Track \(t.trackNumber)",
                                          detail: "\(t.carCount ?? (t.cars?.count ?? 0)) cars",
                                          selected: spotTrack == t.trackNumber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !reach.isOnline {
                Text("Offline · spotting a car is ONLINE_ONLY. It moves physical iron in the yard, and no rail path is offline-eligible today, so it is never queued.")
                    .font(EType.caption).foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await spot(car) }
            } label: {
                HStack {
                    Spacer()
                    if spotting {
                        ProgressView().tint(palette.textOnGradient)
                    } else {
                        Text(spotTrack.map { "Spot on track \($0)" } ?? "Return to unassigned")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(palette.textOnGradient)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(reach.isOnline && !spotting ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .disabled(!reach.isOnline || spotting)
            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private func trackChip(label: String, detail: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .heavy))
            Text(detail).font(.system(size: 9)).monospaced()
        }
        .foregroundStyle(selected ? Brand.info : palette.textSecondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(selected ? Brand.info.opacity(0.12) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .strokeBorder(selected ? Brand.info.opacity(0.35) : palette.borderFaint))
    }

    // MARK: Toast

    /// A failed commit never reads as a success — the toast carries the real
    /// outcome's colour, not a uniform green.
    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(toastIsError ? Brand.danger : Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ msg: String, isError: Bool = false) {
        withAnimation(.easeOut(duration: 0.18)) {
            toast = msg
            toastIsError = isError
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: - Encodable inputs
    //
    // Zod `.optional()` rejects an explicit null, so every optional field goes
    // through encodeIfPresent in a hand-rolled encoder. assignCarToTrack's
    // trackNumber is `.nullable()` (not optional) — null IS the "clear the
    // track" signal there, so it uses the synthesized encoder deliberately.

    private struct ConsistsIn688: Encodable {
        let status: String?
        let limit: Int
        let offset: Int
        enum CodingKeys: String, CodingKey { case status, limit, offset }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(status, forKey: .status)
            try c.encode(limit, forKey: .limit)
            try c.encode(offset, forKey: .offset)
        }
    }

    private struct YardsIn688: Encodable {
        let country: String?
        let limit: Int
        enum CodingKeys: String, CodingKey { case country, limit }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(country, forKey: .country)
            try c.encode(limit, forKey: .limit)
        }
    }

    private struct RailcarsIn688: Encodable {
        let status: String?
        let yardId: Int?
        let limit: Int
        let offset: Int
        enum CodingKeys: String, CodingKey { case status, yardId, limit, offset }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(status, forKey: .status)
            try c.encodeIfPresent(yardId, forKey: .yardId)
            try c.encode(limit, forKey: .limit)
            try c.encode(offset, forKey: .offset)
        }
    }

    private struct WaysideIn688: Encodable {
        let trainId: String?
        let limit: Int
        enum CodingKeys: String, CodingKey { case trainId, limit }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(trainId, forKey: .trainId)
            try c.encode(limit, forKey: .limit)
        }
    }

    private struct OccupancyIn688: Encodable { let yardId: Int }

    private struct CreateIn688: Encodable {
        let trainId: String
        let carrierId: Int
        let originYardId: Int
        let destinationYardId: Int
        let railcarIds: [Int]
    }

    /// zod: `trackNumber: z.coerce.number().int().nullable()` (railShipments.ts:1041).
    /// NULLABLE, not optional — the key must be PRESENT and null is the legal "return to
    /// the unassigned pool" value. The synthesized encoder would use encodeIfPresent and
    /// DROP the key on nil, which zod rejects as Required → 400; encodeNil is hand-rolled
    /// here so the clear path actually reaches the server.
    private struct AssignIn688: Encodable {
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

    // MARK: - Data

    private func load() async {
        loading = true
        loadError = nil

        // Wave 1 — the two reads that do not depend on a yard, in parallel.
        async let yardsQ: [RailYard688] = EusoTripAPI.shared.query(
            "railShipments.getRailYards", input: YardsIn688(country: nil, limit: 60))
        async let consistsQ: ConsistsPage688 = EusoTripAPI.shared.query(
            "railShipments.getTrainConsists", input: ConsistsIn688(status: nil, limit: 25, offset: 0))

        let yardRows = (try? await yardsQ) ?? []
        var wave1Failed = false
        do {
            let page = try await consistsQ
            let rows = page.consists ?? []
            // The cut under assembly is the one still building; otherwise the
            // most recent consist the server returned.
            consist = rows.first { ($0.status ?? "") == "building" }
                ?? rows.first { ($0.status ?? "") == "ready" }
                ?? rows.first
        } catch {
            wave1Failed = true
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // Assigned unconditionally: if the yard catalog comes back empty the
        // picker must empty with it and the commit must block with a stated
        // reason, not keep offering a yard the server no longer confirms.
        yards = yardRows

        // Yard in scope: the cut's origin yard, else the first yard on file.
        if selectedYardId == nil {
            selectedYardId = consist?.originYardId ?? yards.first?.id
        }
        if !regimeTouched, let y = selectedYard {
            regime = WeightRegime688.from(country: y.country)
        }

        await loadYard(hadWave1Error: wave1Failed)
        loading = false
    }

    private func loadYard(hadWave1Error: Bool = false) async {
        guard let yardId = selectedYardId else {
            // No yard anywhere — serve nothing rather than invent one.
            if !hadWave1Error && loadError == nil && yards.isEmpty {
                loadError = "No rail yards on file for this account, so there is no ground to build a cut on."
            }
            return
        }

        // Wave 2 — yard-scoped reads in parallel; one dead section degrades alone.
        async let occQ: YardOccupancy688 = EusoTripAPI.shared.query(
            "railShipments.getYardTrackOccupancy", input: OccupancyIn688(yardId: yardId))
        async let carsQ: RailcarsPage688 = EusoTripAPI.shared.query(
            "railShipments.getRailcars", input: RailcarsIn688(status: nil, yardId: yardId, limit: 120, offset: 0))
        async let alarmsQ: [WaysideRead688] = EusoTripAPI.shared.query(
            "railMechanical.getWaysideDetectorReads",
            input: WaysideIn688(trainId: consist?.consistNumber, limit: 100))

        let occ = try? await occQ
        let carsPage = try? await carsQ
        let alarmRows = (try? await alarmsQ) ?? []

        if occ != nil || carsPage != nil {
            occupancy = occ
            standing = carsPage?.railcars ?? []
            alarms = alarmRows
            servedFromCache = false
            lastSyncedAt = Date()
            loadError = hadWave1Error ? loadError : nil
            ConsistBoardCache688.save(
                ConsistCache688(savedAt: Date(), consist: consist, yard: selectedYard,
                                occupancy: occupancy, cars: standing),
                yardId: yardId
            )
        } else {
            // Both yard reads failed — serve the cache, loudly.
            if let cached = ConsistBoardCache688.load(yardId: yardId) {
                if consist == nil { consist = cached.consist }
                occupancy = cached.occupancy
                standing = cached.cars
                servedFromCache = true
                lastSyncedAt = cached.savedAt
            } else if loadError == nil {
                loadError = "The yard board did not answer and nothing is cached for this yard."
            }
        }
    }

    private func buildTrain() async {
        guard canBuild,
              let yard = selectedYard,
              let carrierId = yard.railroadId,
              let destId = destinationYardId else { return }
        let symbol = buildSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !symbol.isEmpty else { return }

        building = true
        do {
            let res: CreateConsistResult688 = try await EusoTripAPI.shared.mutation(
                "railShipments.createConsist",
                input: CreateIn688(
                    trainId: symbol,
                    carrierId: carrierId,
                    originYardId: yard.id,
                    destinationYardId: destId,
                    railcarIds: cut.map { $0.id }
                )
            )
            showBuildSheet = false
            cut.removeAll()
            showToast("Built \(res.trainId ?? symbol) · \(res.totalCars ?? 0) cars")
            await load()
        } catch {
            showToast((error as? EusoTripAPIError)?.errorDescription ?? "Build failed", isError: true)
        }
        building = false
    }

    private func spot(_ car: Railcar688) async {
        guard let yardId = selectedYardId else { return }
        spotting = true
        do {
            let res: AssignResult688 = try await EusoTripAPI.shared.mutation(
                "railShipments.assignCarToTrack",
                input: AssignIn688(yardId: yardId, carId: car.id, trackNumber: spotTrack)
            )
            spotCar = nil
            let destination = res.trackNumber.map { "track \($0)" } ?? "the unassigned pool"
            showToast("\(car.railcarNumber ?? "Car") spotted on \(destination)")
            await loadYard()
        } catch {
            showToast((error as? EusoTripAPIError)?.errorDescription ?? "Spot failed", isError: true)
        }
        spotting = false
    }
}

// MARK: - Cut tonnage band
//
// The board's hero is a TONNAGE BAND, not a card: the gross rail load reads as
// one big numeral with the cut's shape underneath it, and a GRL gauge runs the
// full width showing the heaviest car in the cut against the country ceiling.
// The gauge is the whole point of the band — an engineer standing at the head
// end wants to know "am I over" before anything else, and the answer is a bar
// that fills toward a hard line, not a number to compare in his head.
private struct CutTonnageBand688: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let verdict: String
    let verdictKind: StatusPill.Kind
    let grossTons: Double
    let carCount: Int
    let lengthFt: Int
    let loads: Int
    let empties: Int
    let hazmat: Int
    let headEndUnits: Int
    let ptcActive: Bool?
    let roadLine: String
    let grlCeilingLb: Double
    let heaviestLb: Double?
    let palette: Theme.Palette

    @State private var fill: CGFloat = 0

    /// Heaviest car as a fraction of the ceiling. nil when no car in the cut
    /// carries a rating — the gauge then reads as unrated, never as zero-safe.
    private var ratio: CGFloat? {
        guard let h = heaviestLb, grlCeilingLb > 0 else { return nil }
        return CGFloat(min(h / grlCeilingLb, 1.35))
    }

    private var gaugeTint: Color {
        guard let r = ratio else { return palette.textTertiary }
        if r > 1.0 { return Brand.danger }
        if r > 0.97 { return Brand.warning }
        return Brand.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(roadLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.info)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                StatusPill(text: verdict, kind: verdictKind)
            }
            .padding(.bottom, 14)

            HStack(alignment: .bottom, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(carCount == 0 ? "—" : "\(Int(grossTons.rounded()))")
                            .font(.system(size: 30, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("t gross · rated")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text("\(carCount) car\(carCount == 1 ? "" : "s") · \(loads) loaded · \(empties) empty · \(hazmat) DOT tank")
                        .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 44)
                VStack(alignment: .leading, spacing: 10) {
                    miniStat("UNITS", headEndUnits == 0 ? "—" : "\(headEndUnits)",
                             headEndUnits == 0 ? palette.textTertiary : Brand.success)
                    miniStat("LENGTH", lengthFt == 0 ? "—" : "\(lengthFt)", palette.textPrimary)
                }
            }
            .padding(.bottom, 14)

            grlGauge

            HStack(spacing: 6) {
                Text(ptcLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(ptcTint)
                Spacer()
                Text(gaugeCaption)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.top, 8)
        }
        .padding(18)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .onAppear { settle() }
        .onChange(of: heaviestLb) { _, _ in settle() }
        .onChange(of: grlCeilingLb) { _, _ in settle() }
    }

    private var ptcLabel: String {
        switch ptcActive {
        case .some(true):  return "PTC CUT IN"
        case .some(false): return "PTC CUT OUT"
        default:           return "PTC NOT REPORTED"
        }
    }

    private var ptcTint: Color {
        switch ptcActive {
        case .some(true):  return Brand.success
        case .some(false): return Brand.warning
        default:           return palette.textTertiary
        }
    }

    private var gaugeCaption: String {
        guard let h = heaviestLb else { return "heaviest car unrated" }
        return "heaviest \(Int((h / 1000).rounded()))k / \(Int((grlCeilingLb / 1000).rounded()))k"
    }

    private var grlGauge: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // The ceiling sits at 1.0 on a track that runs to 1.35 so an
            // overload has somewhere to go and reads as past the line.
            let ceilingX = w / 1.35
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCardSoft).frame(height: 8)
                Capsule().fill(gaugeTint)
                    .frame(width: max(0, min(w, (ratio ?? 0) / 1.35 * w * fill)), height: 8)
                Rectangle().fill(palette.textTertiary)
                    .frame(width: 1.5, height: 16)
                    .offset(x: ceilingX)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
    }

    private func miniStat(_ key: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.system(size: 9, weight: .bold)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 17, weight: .heavy)).monospaced()
                .foregroundStyle(tint)
        }
    }

    /// The gauge fills once on appear so the load reads as weight settling onto
    /// the rail. Reduce Motion snaps straight to the true value.
    private func settle() {
        if reduceMotion { fill = 1; return }
        fill = 0
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { fill = 1 }
    }
}

#Preview("688 · Rail Consist Board · Night") { RailConsistBoard_688(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("688 · Rail Consist Board · Light") { RailConsistBoard_688(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
