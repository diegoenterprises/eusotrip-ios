//
//  684_RailTenderHistory.swift
//  EusoTrip — Rail · Tender History (EDI 404 / 990 outcome ledger).
//
//  TITLE      684 Rail Tender History
//  PURPOSE    Read the persisted tender ledger — every EDI 404 that went out and every
//             EDI 990 that came back — and rank the roads by how often, and how fast,
//             they actually take the freight.
//  SOURCE     Verbatim port of 05 Rail/Light-SVG/684 Rail Tender History.svg (Light + Dark).
//             Composition mirrored 1:1 — sparkle eyebrow + mono right register → back chevron +
//             28/-0.4 title + trailing glyph → numbers-first subline → outcome chip row →
//             full-bleed iridescent hairline → WIN-RATE hero (gradient rim, ok-wash top
//             band, ↑delta pill, 30pt tabular rate, legend line, 3-SEGMENT SPLIT BAR) →
//             section register "TENDER OUTCOMES · n" / "newest first" + faint rule →
//             one LEDGER card of divider-separated rows (mono date · lane · road ·
//             outcome chip · reply time · right-aligned mono rate) → tri-country regime
//             band → CTA pair (Export ledger / Filter) → BottomNav.
//             Dark twin read and confirmed: identical geometry, pure palette swap, so
//             every surface here comes from `palette` and every accent from `Brand`.
//  ARCHETYPE  LEDGER — an outcome / win-rate board. The SVG's geometry decides it: there
//             is no live subject to detail, no map, no gate. It draws ONE ratio (the split
//             bar) over a dense chronological transaction register whose rows are
//             date-led, tabular, and right-aligned on money. That is a ledger, not a
//             detail card and not a timeline: a timeline would thread ONE tender's events
//             on a spine, and this screen deliberately collapses each tender's events to a
//             single settled line so twenty-four outcomes can be scanned at once.
//             It is also explicitly NOT the hero → 3-KPI-grid → list → CTA stamp: there is
//             no KPI grid on this screen at all — the hero IS the ratio, and the roads
//             band under it is a horizontal register of per-carrier server reads.
//
//  WIRING MANIFEST — re-confirmed first-hand against server/routers/railTenderWorkflow.ts
//  this fire (562 lines, every procedure `protectedProcedure`):
//    EXISTS  railTenderWorkflow.ts:435  tenderHistory           (QUERY)    → GET via query()
//              in  z.object({ shipmentId?: coerce.number, carrier?: string,
//                             status?: enum(submitted|accepted|declined|cancelled|pending),
//                             limit: number.min(1).max(200).default(50) }).partial()
//                  — `.partial()` makes EVERY key optional, so the input is hand-encoded
//                    with encodeIfPresent (a synthesized `null` would be rejected).
//              out BARE ARRAY of mapped tender-event rows (:469-495). Feeds the hero,
//                  the split bar, the roads band denominator, and every ledger line.
//              USED BY: initial load, pull-to-refresh, the Filter sheet's road picker
//                  (its `carrier` value is sent as the REAL server-side filter), and the
//                  reload after a successful cancel.
//    EXISTS  railTenderWorkflow.ts:514  carrierAcceptanceRate   (QUERY)    → GET via query()
//              in  { carrier: string (REQUIRED), commodityStcc?: string,
//                    windowDays: number.min(1).max(3650).default(180) }
//              out { carrier, acceptanceRate (0-100, one decimal), accepted, total, windowDays }
//              USED BY: the ROADS band — one call per distinct road in the window, fanned
//                  out in a bounded task group (max 8, the server's own carrier enum size).
//                  A road whose call fails degrades to an em-dash on that tile alone.
//    EXISTS  railTenderWorkflow.ts:346  cancelTender            (MUTATION) → POST via mutation()
//              in  { tenderId: string }   out { tenderId, status: "cancelled" }
//              USED BY: the only write on this screen — the confirm sheet reached by
//                  tapping a still-AWAITING-990 ledger line. Idempotent server-side;
//                  CONFLICTs if the road already answered.
//    NOT CALLED HERE (deliberate, to keep the lane's screens distinct):
//              submitTender (:85, MUTATION) — re-tender is 008's CTA and the failover
//                  ladder is 683's whole reason to exist. 684 reads outcomes; it does not
//                  originate them.
//              receiveTenderResponse (:220, MUTATION) — the carrier's 990 reply belongs to
//                  the live desk (569). Note for the record: it IS a MUTATION, and until
//                  2026-08-10 iOS GET-`query()`ed it, so Accept/Decline was dead on iOS
//                  while it worked on web. That S4 seam is cured in 569; nothing on this
//                  screen re-opens it — the single write here goes through `mutation()`.
//    STUB · named-gap  expireStaleTenders — see NAMED GAPS below.
//    STUB · named-gap  tenderHistory `since` / date-range input — see NAMED GAPS below.
//
//  DB ROW / AUDIT / SOCKET — stated plainly, because the brief for this screen asserted the
//  opposite and the file on disk does not support it:
//    · The two procedures THIS screen reads write NOTHING and broadcast NOTHING. They are
//      reads. `tenderHistory` selects from rail_shipment_events; `carrierAcceptanceRate`
//      counts over the same table. No row, no blockchainAuditTrail entry, no WS emit.
//    · `carrierAcceptanceRate` (:518) takes `{ input }` ONLY — it never touches `ctx`, so
//      unlike every other procedure in this router it is NOT tenant-scoped. Its counts are
//      network-wide for that road across all shippers. This screen therefore labels it
//      "network" and never blends it into the caller's own win rate. Logged as a finding.
//    · The ONE write here, cancelTender (:393-427), inserts a `rail_shipment_events`
//      row (eventType "tender_cancelled"), writes blockchainAuditTrail eventType
//      "rail.tender_cancelled" (:407, best-effort try/catch), and broadcasts
//      WS_EVENTS.RAIL_TENDER_CANCELLED on WS_CHANNELS.RAIL_SHIPMENT(shipmentId) (:417).
//      For completeness: submitTender writes blockchainAuditTrail "rail.tender_submitted"
//      + WS_EVENTS.RAIL_TENDER_SUBMITTED, and receiveTenderResponse writes
//      "rail.tender_response" + WS_EVENTS.RAIL_TENDER_RESPONSE — but only when it can
//      correlate the 990 to a real shipment (:278), otherwise it persists nothing.
//    · This screen does NOT subscribe to that socket. It claims no push anywhere in its
//      copy; it re-reads after its own write and on pull-to-refresh. Nothing on screen
//      implies live streaming.
//
//  RBAC   protectedProcedure on all five procedures (auth-gated). The reads are further
//         narrowed server-side by ownedShipmentIds() (:70-82) — a dual-leg tenant scope of
//         railShipments.shipperId == caller OR railShipments.companyId == caller's company.
//         cancelTender re-checks that same ownership before writing (:376-379). So the
//         ledger is the caller's company's tender book no matter which chrome it is
//         reached through; the screen's copy says exactly that and claims nothing wider.
//
//  transportMode = rail. COUNTRY IS CONTENT, one screen, no file fork: the regime band
//  carries the settlement jurisdiction for the rate column — US STB · FRA (USD),
//  CA Transport Canada · CTA (CAD), MX ARTF · SICT (MXN). The selection sets the currency
//  the rate column is labelled and formatted in, prints the regulator line, and sorts the
//  roads band so in-jurisdiction roads lead. The road→regulator registry is a regulatory
//  fact table over the server's own carrier enum (:87), not server data, and is labelled
//  as such on screen.
//
//  HONEST BLANKS — three, all disclosed on screen rather than filled in:
//    · rate — `tenderHistory` hard-codes rateUsd: null (:492, "no rate stored on a tender
//      event"). Every rate cell renders an em-dash and the ledger footer says why. A rate
//      is NEVER fabricated from the SVG sample values.
//    · reply time — derived ONLY where a tenderId has BOTH a tender_submitted event and a
//      later decided event with parseable stamps. Otherwise em-dash.
//    · EXPIRED — the SVG draws an EXPIRED chip; the server's status vocabulary
//      (:56-65) is submitted | accepted | declined | cancelled | pending. There is no
//      expiry. This screen renders the real third terminal state, CANCELLED, and shows
//      still-open tenders as AWAITING 990. See NAMED GAPS.
//
//  OFFLINE POLICY (Encyclopedia v2 · honesty law). A 180-day analytics read is the ideal
//  cached surface; the one commit on it is not:
//    · READ_CACHED(15m) — the tender ledger falls back to a last-good on-disk snapshot
//      when the read fails. Serving cache is NEVER silent: the header's mono 10pt right
//      register flips from palette.textTertiary "180-DAY · LIVE 14:32" to Brand.warning
//      "180-DAY · CACHED 6m · not live", and the hero's delta pill is suppressed so a
//      stale trend can never be read as a live one. Past the 15m ttl the cache is refused
//      outright and the honest error card shows instead of stale numbers dressed as live.
//      The roads band is NOT cached — a per-road rate that cannot be re-read renders an
//      em-dash rather than a remembered number.
//    · ONLINE_ONLY(cancel) — railTenderWorkflow.cancelTender is absent from the six-path
//      offline-eligibility table at Services/EusoTripAPI.swift:1684 (hos.changeStatus,
//      messages.sendMessage, pod.submitPOD, loadLifecycle.executeTransition,
//      drivers.acceptLoad, location.telemetry.geofenceEvent). NO rail path is eligible, so
//      no rail mutation can queue today. Cancelling a tender also races a carrier's
//      inbound 990 — a cancel replayed hours later could contradict an acceptance the road
//      already sent. The confirm button therefore disables offline with that reason
//      printed on it; nothing is queued and no success is ever implied.
//
//  NAMED GAPS (never fabricated, never wired to a lookalike):
//    1. `expireStaleTenders` / an `expired` status. A tender that never receives a 990
//       stays "submitted" forever — there is no sweep and no expiry state, so the SVG's
//       EXPIRED chip has no server counterpart. Proposed TS:
//         expireStaleTenders: protectedProcedure
//           .input(z.object({ olderThanHours: z.number().min(1).max(720).default(72) }))
//           .mutation(...)  // insert eventType "tender_expired" for every tenderId whose
//                           // newest event is tender_submitted/tender_pending older than
//                           // the cutoff; extend TENDER_EVENTS + statusForEvent with
//                           // "expired"; audit "rail.tender_expired"; broadcast
//                           // WS_EVENTS.RAIL_TENDER_EXPIRED.
//    2. `tenderHistory` has no date-range input — only `limit` (max 200). The 30/90/180/365
//       window on this screen is therefore applied CLIENT-side over the newest 200 rows,
//       which is honest but silently truncates a very busy book. Proposed TS: add
//       `since: z.string().datetime().optional()` to the input and an
//       `sql\`${railShipmentEvents.timestamp} >= ${new Date(input.since)}\`` condition
//       alongside the existing inArray filters (:462-465).
//    3. `carrierAcceptanceRate` is not tenant-scoped (:518 destructures `{ input }` only).
//       Proposed TS: take `{ ctx, input }`, resolve ownedShipmentIds(), and add
//       `inArray(railShipmentEvents.shipmentId, owned)` to `conds` — then return BOTH the
//       owned rate and the network rate so a shipper can see their own bias against the
//       market without the router leaking cross-tenant aggregates by default.
//
//  PRODUCTIVITY — one sentence: it tells a rail buyer, in one screen, which road actually
//  takes their freight and how fast it answers, so the next EDI 404 goes to the road most
//  likely to say yes instead of the one that happens to be first in the list.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

// MARK: - Screen

struct RailTenderHistory_684: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailTenderHistoryBody684() } nav: {
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

// MARK: - Server shapes

/// One mapped row from `railTenderWorkflow.tenderHistory` (railTenderWorkflow.ts:469-495).
/// The server returns ONE ROW PER TENDER-LIFECYCLE EVENT, not one per tender — a single
/// tenderId yields a `tender_submitted` row and, once the road answers, a decided row.
/// Every field is Optional except `id`; `Encodable` exists only so the READ_CACHED(15m)
/// snapshot can be written back to disk.
private struct TenderEvent684: Codable, Identifiable {
    let id: Int
    let tenderId: String?
    let controlNumber: String?
    let shipmentId: Int?
    let carrier: String?
    let origin: String?
    let destination: String?
    let originScac: String?
    let destinationScac: String?
    let railId: String?
    let commodityStcc: String?
    let carType: String?
    let railcarCount: Int?
    let pickupDate: String?
    let outcome: String?
    let status: String?
    let outcomeNote: String?
    let rateUsd: Double?
    let submittedAt: String?
    let timestamp: String?

    /// Server status string, normalised. `status` and `outcome` are the same value on the
    /// mapped row (:489-490); read both so a future divergence does not blank the chip.
    var state: String { (status ?? outcome ?? "").lowercased() }
    var laneOrigin: String? { originScac ?? origin }
    var laneDestination: String? { destinationScac ?? destination }
}

/// Return shape of `railTenderWorkflow.carrierAcceptanceRate` (railTenderWorkflow.ts:554-560).
/// `carrier` is echoed from the input so it is always present and serves as the identity;
/// the counts stay Optional so a shape change degrades to an em-dash instead of throwing.
private struct RoadRate684: Codable, Identifiable, Sendable {
    let carrier: String
    let acceptanceRate: Double?
    let accepted: Int?
    let total: Int?
    let windowDays: Int?

    var id: String { carrier }
    /// The window held at least one DECIDED tender for this road. When false the tile
    /// prints an em-dash rather than the server's honest-zero dressed up as a real 0%.
    var hasData: Bool { (total ?? 0) > 0 }
}

private struct CancelResult684: Decodable {
    let tenderId: String?
    let status: String?
}

// MARK: - Encodable inputs (hand-rolled where the zod key is optional)

/// `tenderHistory` input. The zod object is `.partial()` (railTenderWorkflow.ts:440), so
/// every key is optional and a synthesized `null` from Swift's default encoder would be
/// rejected — `carrier` is written with encodeIfPresent and omitted entirely when unset.
private struct TenderHistoryIn684: Encodable {
    let carrier: String?
    let limit: Int

    enum CodingKeys: String, CodingKey { case carrier, limit }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(carrier, forKey: .carrier)
        try c.encode(limit, forKey: .limit)
    }
}

/// `carrierAcceptanceRate` input — both keys always sent, no optionals, no hand-roll
/// needed. `commodityStcc` is deliberately omitted: this screen asks the road-level
/// question, not the commodity-level one (that is 008's advisory).
private struct RoadRateIn684: Encodable {
    let carrier: String
    let windowDays: Int
}

/// `cancelTender` input — one required key.
private struct CancelIn684: Encodable {
    let tenderId: String
}

// MARK: - Derived ledger line

/// One tender, reduced from all of its lifecycle events. The ledger renders these, not the
/// raw event rows, so twenty-four outcomes read as twenty-four lines.
private struct TenderLine684: Identifiable {
    let id: String
    let tenderId: String?
    let controlNumber: String?
    let shipmentId: Int?
    let carrier: String?
    let originScac: String?
    let destinationScac: String?
    let stcc: String?
    let railcarCount: Int?
    let outcome: TenderOutcome684
    let submittedAt: Date?
    let settledAt: Date?
    let replyMinutes: Int?
    let rateUsd: Double?

    var lane: String {
        let o = (originScac?.isEmpty == false) ? originScac! : "—"
        let d = (destinationScac?.isEmpty == false) ? destinationScac! : "—"
        return "\(o) → \(d)"
    }
    /// Timestamp the ledger sorts and windows on — the newest event for this tender.
    var sortStamp: Date? { settledAt ?? submittedAt }
}

/// The REAL outcome vocabulary. Mapped from the server's `statusForEvent` set
/// (railTenderWorkflow.ts:56-65). There is no `expired` — see the header's NAMED GAPS.
private enum TenderOutcome684: String, CaseIterable, Identifiable {
    case accepted, declined, cancelled, awaiting

    var id: String { rawValue }

    var chip: String {
        switch self {
        case .accepted:  return "ACCEPTED"
        case .declined:  return "DECLINED"
        case .cancelled: return "CANCELLED"
        case .awaiting:  return "AWAITING 990"
        }
    }
    var filterLabel: String {
        switch self {
        case .accepted:  return "Accepted"
        case .declined:  return "Declined"
        case .cancelled: return "Cancelled"
        case .awaiting:  return "Awaiting"
        }
    }
    var tint: Color {
        switch self {
        case .accepted:  return Brand.success
        case .declined:  return Brand.danger
        case .cancelled: return Brand.neutral
        case .awaiting:  return Brand.warning
        }
    }
    /// Matches the server's DECIDED set exactly (railTenderWorkflow.ts:528) so the win rate
    /// on this screen and the one carrierAcceptanceRate computes are the same arithmetic.
    var isDecided: Bool { self != .awaiting }

    static func from(_ serverState: String) -> TenderOutcome684 {
        switch serverState {
        case "accepted":  return .accepted
        case "declined":  return .declined
        case "cancelled": return .cancelled
        default:          return .awaiting   // "submitted" | "pending" | anything new
        }
    }
}

// MARK: - Window register

private enum HistoryWindow684: Int, CaseIterable, Identifiable {
    case d30 = 30, d90 = 90, d180 = 180, d365 = 365

    var id: Int { rawValue }
    var days: Int { rawValue }
    var register: String { "\(rawValue)-DAY" }
    var label: String { rawValue == 365 ? "1 year" : "\(rawValue) days" }
}

// MARK: - Country-as-content registry

/// Settlement jurisdiction for the rate column. A regulatory fact table over the server's
/// own carrier enum (railTenderWorkflow.ts:87) — labelled on screen as a jurisdiction
/// registry, never presented as server data. Roads with cross-border Class I operations
/// appear under more than one regulator, which is the real-world state.
private enum RailRegime684: String, CaseIterable, Identifiable {
    case us, ca, mx

    var id: String { rawValue }

    /// Verbatim SVG chip text.
    var chipTop: String {
        switch self {
        case .us: return "US · USD"
        case .ca: return "CA · CAD"
        case .mx: return "MX · MXN"
        }
    }
    var chipBottom: String {
        switch self {
        case .us: return "STB rate"
        case .ca: return "CTA rate"
        case .mx: return "ARTF tarifa"
        }
    }
    var currencyCode: String {
        switch self {
        case .us: return "USD"
        case .ca: return "CAD"
        case .mx: return "MXN"
        }
    }
    var regulator: String {
        switch self {
        case .us: return "US · Surface Transportation Board · FRA · 49 CFR"
        case .ca: return "CA · Transport Canada · Canadian Transportation Agency · TDG"
        case .mx: return "MX · ARTF · SICT · NOM"
        }
    }
    var tag: String {
        switch self {
        case .us: return "STB"
        case .ca: return "TC"
        case .mx: return "ARTF"
        }
    }
    /// Class I marks that operate under this regulator.
    var roads: Set<String> {
        switch self {
        case .us: return ["BNSF", "UP", "NS", "CSX", "KCS", "CPKC", "CN"]
        case .ca: return ["CN", "CPKC"]
        case .mx: return ["FXE", "CPKC"]
        }
    }
    static func tags(for mark: String) -> String {
        let m = mark.uppercased()
        let hits = RailRegime684.allCases.filter { $0.roads.contains(m) }.map { $0.tag }
        return hits.isEmpty ? "—" : hits.joined(separator: " · ")
    }
}

// MARK: - Roads-band tile (derived, one per road in the window)

private struct RoadTile684: Identifiable {
    let id: String
    let mark: String
    let mineAccepted: Int
    let mineDecided: Int
    let mineRate: Double?
    let medianReplyMinutes: Int?
    let networkRate: Double?
    let networkTotal: Int?
    let regulatorTags: String
    let inRegime: Bool
}

// MARK: - READ_CACHED(15m) store
//
// Last-good on-disk snapshot of the tender ledger, so the honesty law can be kept: a cached
// read is rendered but visibly marked, and refused outright past the ttl. Read-side only —
// the cancel is ONLINE_ONLY (see the header), so there is deliberately no write cache.

private struct TenderLedgerEnvelope684: Codable {
    let capturedAt: Date
    let value: [TenderEvent684]
}

private enum TenderLedgerCache684 {
    static let ttl: TimeInterval = 15 * 60
    static let ttlLabel = "15m"

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("rail-tender-ledger-684", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tender-history.json")
    }

    static func store(_ value: [TenderEvent684]) {
        guard let fileURL else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(TenderLedgerEnvelope684(capturedAt: Date(), value: value))
        else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Snapshot + its age, only while inside the ttl. Past the ttl this returns nil so the
    /// caller shows its honest error state instead of stale numbers dressed as live.
    static func load() -> (value: [TenderEvent684], age: TimeInterval)? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let env = try? dec.decode(TenderLedgerEnvelope684.self, from: data) else { return nil }
        let age = Date().timeIntervalSince(env.capturedAt)
        guard age >= 0, age <= ttl else { return nil }
        return (env.value, age)
    }
}

// MARK: - File-scope helpers

/// ISO-8601 with and without fractional seconds. The server stamps both flavours —
/// `metadata.submittedAt` from `new Date().toISOString()` and `timestamp` from
/// `new Date(r.ts).toISOString()` (railTenderWorkflow.ts:494).
private func railTenderDate684(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFraction.date(from: raw) { return d }
    let plain = ISO8601DateFormatter()
    return plain.date(from: raw)
}

/// "14 Jun" — the SVG's ledger date register.
private func railTenderDayLabel684(_ date: Date?) -> String {
    guard let date else { return "—" }
    let f = DateFormatter()
    f.dateFormat = "dd MMM"
    return f.string(from: date)
}

/// Compact elapsed label: "12m" · "3h 12m" · "2d 4h". Never rounds a real gap to zero.
private func railTenderElapsed684(_ minutes: Int?) -> String {
    guard let minutes, minutes >= 0 else { return "—" }
    if minutes < 60 { return "\(max(minutes, 1))m" }
    let hours = minutes / 60
    if hours < 24 {
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }
    let days = hours / 24
    let remH = hours % 24
    return remH == 0 ? "\(days)d" : "\(days)d \(remH)h"
}

/// 0-100 one-decimal rate → "79%" / "78.5%". Drops a trailing ".0".
private func railTenderRate684(_ value: Double?) -> String {
    guard let value else { return "—" }
    if value == value.rounded() { return "\(Int(value))%" }
    return String(format: "%.1f%%", value)
}

// MARK: - Body

private struct RailTenderHistoryBody684: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    /// Server ceiling on `tenderHistory.limit` (railTenderWorkflow.ts:439, .max(200)).
    private static let rowLimit = 200
    /// The server's own carrier enum is eight marks (:87) — the hard cap on the fan-out.
    private static let maxRoadCalls = 8
    /// The roads this router can tender to — the server's `carrier` z.enum verbatim
    /// (railTenderWorkflow.ts:87). Used for the Filter sheet's road picker so a road can be
    /// selected even when the current window holds none of its tenders (which then returns
    /// an honest empty ledger rather than hiding the option).
    private static let serverRoads = ["BNSF", "UP", "NS", "CSX", "CPKC", "CN", "KCS", "FXE"]

    // Ledger state
    @State private var events: [TenderEvent684] = []
    @State private var roadRates: [String: RoadRate684] = [:]
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var cacheAge: TimeInterval? = nil
    @State private var lastLiveAt: Date? = nil

    // Filters
    @State private var window: HistoryWindow684 = .d180
    @State private var roadFilter: String? = nil          // real server-side `carrier` input
    @State private var outcomeFilter: TenderOutcome684? = nil
    @State private var regime: RailRegime684 = .us
    @State private var showFilter = false

    // The one write
    @State private var cancelTarget: TenderLine684? = nil
    @State private var cancelling = false
    @State private var cancelError: String? = nil
    @State private var toast: String? = nil

    // MARK: Derived — reduction

    /// Collapse the server's per-EVENT rows to one line per tender. Rows arrive newest-first
    /// (`orderBy desc(timestamp)`, :466), so the first row seen for a key is its newest event.
    private var allLines: [TenderLine684] {
        var order: [String] = []
        var newest: [String: TenderEvent684] = [:]
        var submitted: [String: TenderEvent684] = [:]
        var rate: [String: Double] = [:]

        for e in events {
            // Group on tenderId; an event with none (older rows) stays its own line rather
            // than being merged into an unrelated tender.
            let tid: String = (e.tenderId ?? "").trimmingCharacters(in: .whitespaces)
            let key: String = tid.isEmpty ? "row-\(e.id)" : tid
            if newest[key] == nil {
                newest[key] = e
                order.append(key)
            }
            if e.state == "submitted", submitted[key] == nil { submitted[key] = e }
            if let r = e.rateUsd, rate[key] == nil { rate[key] = r }
        }

        return order.compactMap { key -> TenderLine684? in
            guard let head = newest[key] else { return nil }
            let out = TenderOutcome684.from(head.state)
            let submitEvent = submitted[key]
            let submitStamp = railTenderDate684(submitEvent?.submittedAt ?? submitEvent?.timestamp)
                ?? railTenderDate684(head.submittedAt)
            let settleStamp = railTenderDate684(head.timestamp)

            // Reply latency is only real when the SAME tender carries both a submitted
            // event and a later decided event with parseable stamps. Anything else is an
            // em-dash — never an estimate.
            var reply: Int? = nil
            if out.isDecided, let s = submitStamp, let d = settleStamp, d >= s {
                reply = Int(d.timeIntervalSince(s) / 60.0)
            }

            return TenderLine684(
                id: key,
                tenderId: head.tenderId,
                controlNumber: head.controlNumber,
                shipmentId: head.shipmentId,
                carrier: head.carrier,
                originScac: head.laneOrigin,
                destinationScac: head.laneDestination,
                stcc: head.commodityStcc,
                railcarCount: head.railcarCount,
                outcome: out,
                submittedAt: submitStamp,
                settledAt: settleStamp,
                replyMinutes: reply,
                rateUsd: rate[key]
            )
        }
    }

    /// `tenderHistory` has no date-range input (NAMED GAP 2) — the window is applied here,
    /// over the newest `rowLimit` rows the server returned.
    private var windowedLines: [TenderLine684] {
        let cutoff = Date().addingTimeInterval(-Double(window.days) * 86_400)
        return allLines.filter { line in
            guard let stamp = line.sortStamp else { return true }   // undated rows are never hidden
            return stamp >= cutoff
        }
    }

    private var visibleLines: [TenderLine684] {
        guard let f = outcomeFilter else { return windowedLines }
        return windowedLines.filter { $0.outcome == f }
    }

    // MARK: Derived — hero arithmetic

    private var decidedLines: [TenderLine684] { windowedLines.filter { $0.outcome.isDecided } }
    private var acceptedCount:  Int { windowedLines.filter { $0.outcome == .accepted }.count }
    private var declinedCount:  Int { windowedLines.filter { $0.outcome == .declined }.count }
    private var cancelledCount: Int { windowedLines.filter { $0.outcome == .cancelled }.count }
    private var awaitingCount:  Int { windowedLines.filter { $0.outcome == .awaiting }.count }

    /// accepted / decided × 100 — the server's exact DECIDED arithmetic
    /// (railTenderWorkflow.ts:528, :552), so this figure and every roads-band figure are
    /// computed the same way and are legitimately comparable.
    private var winRate: Double? {
        guard !decidedLines.isEmpty else { return nil }
        return (Double(acceptedCount) / Double(decidedLines.count)) * 100.0
    }
    private var winRateLabel: String { railTenderRate684(winRate.map { ($0 * 10).rounded() / 10 }) }

    /// Delta against the older half of the SAME window, from real timestamps only.
    /// Suppressed entirely when either half has no decided tender, and suppressed while
    /// serving cache so a stale trend can never be read as a live one.
    private var winRateDelta: Double? {
        guard cacheAge == nil else { return nil }
        let midpoint = Date().addingTimeInterval(-Double(window.days) * 86_400 / 2)
        let recent = decidedLines.filter { ($0.sortStamp ?? .distantPast) >= midpoint }
        let older  = decidedLines.filter { ($0.sortStamp ?? .distantFuture) < midpoint }
        guard !recent.isEmpty, !older.isEmpty else { return nil }
        let r = Double(recent.filter { $0.outcome == .accepted }.count) / Double(recent.count)
        let o = Double(older.filter  { $0.outcome == .accepted }.count) / Double(older.count)
        return ((r - o) * 100.0 * 10).rounded() / 10
    }

    private var legendLine: String {
        var parts = ["\(acceptedCount) acc", "\(declinedCount) dec", "\(cancelledCount) cxl"]
        var tail = "of \(decidedLines.count) decided"
        if awaitingCount > 0 { tail += " · \(awaitingCount) awaiting 990" }
        parts.append(tail)
        return parts.joined(separator: " · ")
    }

    private var subline: String {
        let roads = Set(windowedLines.compactMap { $0.carrier }.filter { !$0.isEmpty }).count
        let tenderWord = windowedLines.count == 1 ? "tender" : "tenders"
        let roadWord   = roads == 1 ? "road" : "roads"
        return "\(windowedLines.count) \(tenderWord) · \(roads) \(roadWord) · \(window.label)"
    }

    /// Outcome chips are drawn from the states ACTUALLY present in the window, in the SVG's
    /// order. With only accepted + declined present this renders exactly the SVG's three
    /// chips; it never hides a real row behind a chip that was not drawn.
    private var presentOutcomes: [TenderOutcome684] {
        let present = Set(windowedLines.map { $0.outcome })
        return TenderOutcome684.allCases.filter { present.contains($0) }
    }

    // MARK: Derived — roads band

    private var roadTiles: [RoadTile684] {
        let marks = Set(windowedLines.compactMap { $0.carrier }.filter { !$0.isEmpty })
        let tiles: [RoadTile684] = marks.map { mark in
            let mine = windowedLines.filter { $0.carrier == mark }
            let mineDecided = mine.filter { $0.outcome.isDecided }
            let mineAccepted = mine.filter { $0.outcome == .accepted }.count
            let replies = mine.compactMap { $0.replyMinutes }.sorted()
            let median: Int? = replies.isEmpty ? nil : replies[replies.count / 2]
            let server = roadRates[mark]
            return RoadTile684(
                id: mark,
                mark: mark,
                mineAccepted: mineAccepted,
                mineDecided: mineDecided.count,
                mineRate: mineDecided.isEmpty
                    ? nil
                    : ((Double(mineAccepted) / Double(mineDecided.count)) * 1000).rounded() / 10,
                medianReplyMinutes: median,
                networkRate: (server?.hasData == true) ? server?.acceptanceRate : nil,
                networkTotal: server?.total,
                regulatorTags: RailRegime684.tags(for: mark),
                inRegime: regime.roads.contains(mark.uppercased())
            )
        }
        // In-jurisdiction roads lead, then the ones the caller tenders to most.
        return tiles.sorted { a, b in
            if a.inRegime != b.inRegime { return a.inRegime }
            if a.mineDecided != b.mineDecided { return a.mineDecided > b.mineDecided }
            return a.mark < b.mark
        }
    }

    // MARK: Derived — offline honesty

    private var isCached: Bool { cacheAge != nil }

    /// The SVG's mono right register, carrying the READ_CACHED staleness line. Tertiary
    /// when live, Brand.warning the moment a cached snapshot is on screen.
    private var register: (text: String, warn: Bool) {
        if let age = cacheAge {
            let mins = max(Int(age / 60), 1)
            return ("\(window.register) · CACHED \(mins)m · not live", true)
        }
        if !reach.isOnline {
            return ("\(window.register) · OFFLINE · awaiting reconnect", true)
        }
        guard let at = lastLiveAt else {
            return ("\(window.register) · READ_CACHED(\(TenderLedgerCache684.ttlLabel))", false)
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return ("\(window.register) · LIVE \(f.string(from: at))", false)
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                headerBlock
                IridescentHairline()
                if loading && events.isEmpty {
                    LifecycleCard {
                        Text("Loading tender ledger…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError, events.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    winRateHero
                    roadsBand
                    ledgerSection
                    regimeBand
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(item: $cancelTarget) { line in cancelSheet(line) }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("✦ RAIL · TENDER HISTORY · EDI 404 / 990")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s2)
                Text(register.text)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(register.warn ? Brand.warning : palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                Text("Tender history")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s2)
                Button { showFilter = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter tender ledger")
            }

            Text(subline)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)

            outcomeChips
        }
    }

    private var outcomeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip(label: "All", active: outcomeFilter == nil, tint: Brand.blue) {
                    outcomeFilter = nil
                }
                ForEach(presentOutcomes) { o in
                    chip(label: o.filterLabel, active: outcomeFilter == o, tint: o.tint) {
                        outcomeFilter = (outcomeFilter == o) ? nil : o
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(label: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(active ? tint : palette.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(active ? tint.opacity(0.14) : palette.bgCard))
                .overlay(Capsule().strokeBorder(active ? tint.opacity(0.45) : palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Win-rate hero (gradient rim + 3-segment split bar)

    private var winRateHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroTopBand
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(winRateLabel)
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("accepted")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                        Text(legendLine)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                    Spacer(minLength: 0)
                }
                SplitBar684(
                    accepted: acceptedCount,
                    declined: declinedCount,
                    cancelled: cancelledCount,
                    track: palette.tintNeutral
                )
                Text("accepted ÷ decided — the same arithmetic behind the network figure. Your company's book only.")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var heroBandTitle: String {
        if let road = roadFilter { return "WIN RATE · " + road + " · LAST \(window.days) DAYS" }
        return "WIN RATE · LAST \(window.days) DAYS"
    }

    /// The SVG's ok-wash band across the top of the hero.
    private var heroTopBand: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.success)
            Text(heroBandTitle)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.success)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s2)
            if let d = winRateDelta {
                let up: Bool = d >= 0
                let deltaTint: Color = up ? Brand.success : Brand.danger
                Text((up ? "↑ " : "↓ ") + railTenderRate684(abs(d)))
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(deltaTint)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(deltaTint.opacity(0.14)))
            } else if isCached {
                Text("TREND HELD")
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.14)))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Brand.success.opacity(0.14), Brand.blue.opacity(0.06)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }

    // MARK: - Roads band (the analytic spine — one carrierAcceptanceRate call per road)

    private var roadsBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ROADS · WHO TAKES THE FREIGHT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("carrierAcceptanceRate")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if roadTiles.isEmpty {
                LifecycleCard {
                    Text("No road has been tendered in this window.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(roadTiles) { tile in roadTileView(tile) }
                    }
                    .padding(.vertical, 1)
                }
                Text("The big figure is YOUR accept rate with that road. \"network\" counts that road across every shipper, not just yours, so the two are different populations and are never blended. Tap a road to filter the ledger to it.")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "network 74% · n=312" — the server-computed rate with its own sample size, so the
    /// figure can never be mistaken for the caller's own book. Reads "network —" when the
    /// road had no decided tender in the window or the read failed.
    private func networkLabel(_ tile: RoadTile684) -> String {
        let rate = railTenderRate684(tile.networkRate)
        guard let n = tile.networkTotal, n > 0, tile.networkRate != nil else {
            return "network " + rate
        }
        return "network " + rate + " · n=\(n)"
    }

    private func roadTileView(_ tile: RoadTile684) -> some View {
        let selected = (roadFilter == tile.mark)
        return Button {
            roadFilter = selected ? nil : tile.mark
            Task { await load() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(tile.mark)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 4)
                    Text(tile.regulatorTags)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(tile.inRegime ? Brand.blue : palette.textTertiary)
                }
                Text(railTenderRate684(tile.mineRate))
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("\(tile.mineAccepted) of \(tile.mineDecided) yours")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
                Divider().overlay(palette.borderFaint)
                Text(networkLabel(tile))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(tile.networkRate == nil ? palette.textTertiary : Brand.blue)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("median reply " + railTenderElapsed684(tile.medianReplyMinutes))
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(12)
            .frame(width: 132, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(palette.borderFaint),
                                  lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ledger

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TENDER OUTCOMES · \(visibleLines.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("newest first")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            if visibleLines.isEmpty {
                EusoEmptyState(
                    systemImage: "tray",
                    title: "No tenders in this window",
                    subtitle: "Every EDI 404 you send and every EDI 990 a road sends back lands here, newest first."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.element.id) { idx, line in
                        ledgerRow(line)
                        if idx < visibleLines.count - 1 {
                            Divider().padding(.leading, 16).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )

                Text("The rate column is blank on every line by design: no rate is recorded against a tender event. It fills the moment a settlement links a rate; it is never estimated here.")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func ledgerRow(_ line: TenderLine684) -> some View {
        if line.outcome == .awaiting, line.tenderId?.isEmpty == false {
            Button { cancelError = nil; cancelTarget = line } label: {
                ledgerRowContent(line).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            ledgerRowContent(line)
        }
    }

    private func ledgerRowContent(_ line: TenderLine684) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(railTenderDayLabel684(line.sortStamp))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line.lane)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(line.carrier ?? "—")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(line.outcome.chip)
                    .font(.system(size: 9.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(line.outcome.tint)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .background(Capsule().fill(line.outcome.tint.opacity(0.14)))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(railTenderElapsed684(line.replyMinutes))
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.textTertiary)
                    Text(rateCell(line))
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                if line.outcome == .awaiting, line.tenderId?.isEmpty == false {
                    HStack(spacing: 3) {
                        Text("Cancel tender")
                            .font(.system(size: 9.5, weight: .heavy))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .heavy))
                    }
                    .foregroundStyle(Brand.warning)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// The rate cell. `rateUsd` is null on every tender event today (railTenderWorkflow
    /// .ts:492), so this reads an em-dash — a rate is never fabricated. The currency the
    /// cell WOULD render in comes from the selected regime.
    private func rateCell(_ line: TenderLine684) -> String {
        guard let r = line.rateUsd else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = regime.currencyCode
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: r)) ?? "—"
    }

    // MARK: - Tri-country regime band

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                ForEach(RailRegime684.allCases) { r in
                    Button { regime = r } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.chipTop)
                                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                            Text(r.chipBottom)
                                .font(.system(size: 9, weight: .heavy))
                        }
                        .foregroundStyle(regime == r ? Brand.blue : palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(regime == r ? Brand.blue.opacity(0.12) : palette.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(regime == r ? Brand.blue.opacity(0.35) : palette.borderFaint)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("\(regime.regulator) · rate column reads \(regime.currencyCode). Road → regulator is EusoTrip's own jurisdiction registry over the reporting marks — the tender itself never carries it.")
                .font(.system(size: 9))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            ShareLink(item: exportLedger) {
                Text("Export ledger")
                    .font(EType.title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(visibleLines.isEmpty)
            .opacity(visibleLines.isEmpty ? 0.5 : 1)

            Button { showFilter = true } label: {
                Text("Filter")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148).frame(minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Local export of what is already loaded and already authorised — a real on-device
    /// effect, never a dead tap and never a server call this router does not have.
    private var exportLedger: String {
        var out: [String] = []
        out.append("EusoTrip · rail tender ledger · EDI 404 / 990")
        out.append("Window \(window.label) · \(subline)")
        out.append("Scope: your company's owned rail shipments (shipperId or companyId).")
        out.append("Win rate \(winRateLabel) — \(legendLine)")
        if let d = winRateDelta {
            let sign: String = d >= 0 ? "+" : "-"
            out.append("Trend " + sign + railTenderRate684(abs(d)) + " vs the prior half-window")
        }
        if isCached { out.append("SERVED FROM CACHE — not a live read.") }
        out.append("")
        out.append("ROADS (yours ÷ decided · network via carrierAcceptanceRate \(window.days)d)")
        for t in roadTiles {
            // Built from pre-resolved locals rather than one long interpolation so the
            // Swift type-checker never has to solve a seven-term string in one pass.
            let mine: String = railTenderRate684(t.mineRate)
            let net: String = railTenderRate684(t.networkRate)
            let reply: String = railTenderElapsed684(t.medianReplyMinutes)
            let counts: String = "\(t.mineAccepted)/\(t.mineDecided)"
            let cells: [String] = ["  " + t.mark, "[" + t.regulatorTags + "]",
                                   "yours " + mine + " (" + counts + ")",
                                   "network " + net, "median reply " + reply]
            out.append(cells.joined(separator: " · "))
        }
        out.append("")
        out.append(["DATE", "LANE", "ROAD", "OUTCOME", "REPLY",
                    "RATE (" + regime.currencyCode + ")", "TENDER"].joined(separator: "\t"))
        for l in visibleLines {
            let cells: [String] = [
                railTenderDayLabel684(l.sortStamp),
                l.lane,
                l.carrier ?? "—",
                l.outcome.chip,
                railTenderElapsed684(l.replyMinutes),
                rateCell(l),
                l.tenderId ?? "—"
            ]
            out.append(cells.joined(separator: "\t"))
        }
        out.append("")
        out.append("Rate column is blank by design: tenderHistory stores no rate on a tender event.")
        out.append(regime.regulator)
        return out.joined(separator: "\n")
    }

    // MARK: - Filter sheet

    private var filterSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("TENDER LEDGER · FILTER")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }

                    Text("Window")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: Space.s2) {
                        ForEach(HistoryWindow684.allCases) { w in
                            chip(label: w.label, active: window == w, tint: Brand.blue) {
                                window = w
                                Task { await load() }
                            }
                        }
                    }
                    Text("Applied on the device over the newest \(Self.rowLimit) events — tenderHistory has no date-range input today. It IS the real window sent to carrierAcceptanceRate.")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Road")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Space.s2)],
                              spacing: Space.s2) {
                        chip(label: "All roads", active: roadFilter == nil, tint: Brand.blue) {
                            roadFilter = nil
                            Task { await load() }
                        }
                        ForEach(Self.serverRoads, id: \.self) { mark in
                            chip(label: mark, active: roadFilter == mark, tint: Brand.blue) {
                                roadFilter = (roadFilter == mark) ? nil : mark
                                Task { await load() }
                            }
                        }
                    }
                    Text("The ledger itself is filtered, not this device — the history is narrowed before it reaches you. These eight reporting marks are the only ones rail tendering recognises.")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Outcome")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: Space.s2) {
                        chip(label: "All", active: outcomeFilter == nil, tint: Brand.blue) {
                            outcomeFilter = nil
                        }
                        ForEach(presentOutcomes) { o in
                            chip(label: o.filterLabel, active: outcomeFilter == o, tint: o.tint) {
                                outcomeFilter = (outcomeFilter == o) ? nil : o
                            }
                        }
                    }
                }
                .padding(Space.s4)
            }
            .background(palette.bgSheet.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFilter = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cancel sheet (the one write — ONLINE_ONLY)

    private func cancelSheet(_ line: TenderLine684) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CANCEL TENDER · EDI 404 WITHDRAWN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text(line.lane)
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                cancelFact("ROAD", line.carrier ?? "—")
                cancelFact("TENDER", line.tenderId ?? "—")
                cancelFact("CONTROL", line.controlNumber ?? "—")
                cancelFact("SHIPMENT", line.shipmentId.map(String.init) ?? "—")
                cancelFact("STCC", line.stcc ?? "—")
                cancelFact("CARS", line.railcarCount.map(String.init) ?? "—")
                cancelFact("SENT", railTenderDayLabel684(line.submittedAt))
            }

            Text("Withdraws the EDI 404 before the road answers. It is refused once a 990 has landed, and repeating it on an already-cancelled tender changes nothing. The withdrawal is written to the shipment's event history, sealed into the audit trail, and announced to everyone watching this tender.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let err = cancelError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await cancelTender(line) }
            } label: {
                HStack {
                    Spacer()
                    if cancelling {
                        ProgressView().tint(.white)
                    } else {
                        Text(reach.isOnline ? "Cancel this tender" : "Offline — cancel unavailable")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(reach.isOnline ? AnyShapeStyle(LinearGradient.diagonal)
                                           : AnyShapeStyle(Brand.neutral))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(cancelling || !reach.isOnline)

            Text(reach.isOnline
                 ? "Sent now, over the network — nothing is held on this device."
                 : "No rail action is eligible for offline queuing, and a held cancel could contradict a 990 the road sends while you are dark. Nothing is held. Reconnect to withdraw.")
                .font(.system(size: 10))
                .foregroundStyle(reach.isOnline ? palette.textTertiary : Brand.warning)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func cancelFact(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(key)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Toast

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: - Data

    /// GET railTenderWorkflow.tenderHistory (railTenderWorkflow.ts:435, .query). On failure
    /// the READ_CACHED(15m) snapshot is served and visibly marked; past the ttl the honest
    /// error card shows instead of stale numbers dressed as live.
    private func load() async {
        loading = true
        do {
            let fresh: [TenderEvent684] = try await EusoTripAPI.shared.query(
                "railTenderWorkflow.tenderHistory",
                input: TenderHistoryIn684(carrier: roadFilter, limit: Self.rowLimit)
            )
            events = fresh
            cacheAge = nil
            lastLiveAt = Date()
            loadError = nil
            TenderLedgerCache684.store(fresh)
        } catch {
            let message = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            if let cached = TenderLedgerCache684.load() {
                events = cached.value
                cacheAge = cached.age
                loadError = nil
            } else {
                events = []
                cacheAge = nil
                loadError = message
            }
        }
        loading = false
        await loadRoadRates()
    }

    /// GET railTenderWorkflow.carrierAcceptanceRate (railTenderWorkflow.ts:514, .query),
    /// one bounded call per road present in the window. `carrier` is REQUIRED by the zod
    /// input, so there is no all-roads form of this read — the fan-out IS the contract.
    /// A road whose call fails degrades to an em-dash on that tile alone; nothing is
    /// remembered from a previous window, so a stale rate can never be shown as current.
    private func loadRoadRates() async {
        let marks = Array(Set(windowedLines.compactMap { $0.carrier }.filter { !$0.isEmpty }))
            .sorted()
            .prefix(Self.maxRoadCalls)
        guard !marks.isEmpty else {
            roadRates = [:]
            return
        }
        let days = window.days
        var next: [String: RoadRate684] = [:]
        await withTaskGroup(of: (String, RoadRate684?).self) { group in
            for mark in marks {
                group.addTask {
                    do {
                        let rate: RoadRate684 = try await EusoTripAPI.shared.query(
                            "railTenderWorkflow.carrierAcceptanceRate",
                            input: RoadRateIn684(carrier: mark, windowDays: days)
                        )
                        return (mark, rate)
                    } catch {
                        return (mark, nil)
                    }
                }
            }
            for await (mark, rate) in group {
                if let rate { next[mark] = rate }
            }
        }
        roadRates = next
    }

    /// POST railTenderWorkflow.cancelTender (railTenderWorkflow.ts:346, MUTATION — sent
    /// with mutation(), never query(). The server has no method override, so a GET here
    /// would be the S4 fault class that killed Accept/Decline on 569 until 2026-08-10).
    ///
    /// ONLINE_ONLY: the path is absent from the offline-eligibility table at
    /// Services/EusoTripAPI.swift:1684, so nothing can queue. The button is already
    /// disabled offline; this guard is the second lock.
    private func cancelTender(_ line: TenderLine684) async {
        guard let tid = line.tenderId, !tid.isEmpty else {
            cancelError = "This row carries no tender id, so a withdrawal cannot be matched to it."
            return
        }
        guard reach.isOnline else {
            cancelError = "Offline — a rail tender cancel cannot be queued on this device. Reconnect to withdraw the EDI 404."
            return
        }
        cancelling = true
        cancelError = nil
        do {
            let result: CancelResult684 = try await EusoTripAPI.shared.mutation(
                "railTenderWorkflow.cancelTender",
                input: CancelIn684(tenderId: tid)
            )
            cancelTarget = nil
            showToast("Tender \(result.tenderId ?? tid) \(result.status ?? "cancelled")")
            await load()
        } catch {
            cancelError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        cancelling = false
    }
}

// MARK: - Three-segment split bar
//
// The SVG's signature element. Segments are the server's DECIDED set exactly
// (railTenderWorkflow.ts:528): accepted · declined · cancelled. Still-open tenders are
// deliberately NOT a fourth segment — they have no outcome yet, so they are counted in the
// legend line above instead of being drawn as if they were one.
//
// Colour note: the SVG paints the middle segment amber while its DECLINED row chip is red.
// Here every segment matches its own chip (success · danger · neutral) so the bar and the
// ledger cannot be read as saying two different things.

private struct SplitBar684: View {
    let accepted: Int
    let declined: Int
    let cancelled: Int
    let track: Color

    private var total: Int { accepted + declined + cancelled }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if total > 0 {
                    HStack(spacing: 2) {
                        segment(Brand.success, accepted, width)
                        segment(Brand.danger, declined, width)
                        segment(Brand.neutral, cancelled, width)
                    }
                }
            }
        }
        .frame(height: 9)
        .accessibilityElement()
        .accessibilityLabel("Tender outcomes")
        .accessibilityValue("\(accepted) accepted, \(declined) declined, \(cancelled) cancelled")
    }

    @ViewBuilder
    private func segment(_ color: Color, _ count: Int, _ width: CGFloat) -> some View {
        if count > 0, total > 0 {
            Capsule()
                .fill(color)
                .frame(width: max(5, (width - 4) * CGFloat(count) / CGFloat(total)))
        }
    }
}

// MARK: - Previews

#Preview("684 · Rail Tender History · Night") {
    RailTenderHistory_684(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("684 · Rail Tender History · Light") {
    RailTenderHistory_684(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
