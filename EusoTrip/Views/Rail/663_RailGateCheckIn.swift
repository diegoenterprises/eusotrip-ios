//
//  663_RailGateCheckIn.swift
//  EusoTrip — Rail Engineer · Rail Gate Check-In (carrier-side gate console).
//
//  TITLE      663 Rail Gate Check-In
//  PURPOSE    Record a railcar's gate move (in / out / flag) at a ramp and read the
//             live gate ledger behind it, so a seal- or AEI-mismatched car is HELD at
//             the gate instead of being reconciled out of a raw move log days later.
//  SOURCE     Verbatim port of 05 Rail/Light-SVG/663 Rail Gate Check-In.svg (Light + Dark).
//             Composition mirrored 1:1 — DETAIL TopBar (back chevron + one ✦ eyebrow +
//             ramp mono caption + 28/-0.4 title) → iridescent hairline → LIVE GATE BOARD
//             hero (state pill + six status tiles + inline IN / OUT / avg-turn flow line)
//             → GATE QUEUE live-feed ledger (flow chip + car + mono sub + IN/OUT pill +
//             tabular time, with a live footer line) → tri-country credential band →
//             Check-in / Check-out CTA pair → BottomNav.
//  ARCHETYPE  COMPLIANCE/GATE — a gate console: one capture affordance and one activity
//             ledger, tight scannable rows, summary band hero. NOT a hero→3-KPI→list→CTA
//             stamp; the SVG draws a board of status tiles over a transaction feed, and
//             the whole screen exists to raise one decision (RELEASE or HOLD).
//
//  WIRING MANIFEST — re-confirmed first-hand against server/routers/railGate.ts this fire:
//    EXISTS  railGate.ts:47    railGate.recordGateEvent  (MUTATION)  → POST via mutation()
//              in  { railcarNumber 1..120, gateType "gate_in"|"gate_out"|"flag",
//                    trainId? ≤120, site? ≤255, sealNumber? ≤64, ediSeal? ≤64, aeiTag? ≤64 }
//              out { success, id "rge_<n>", gateType, anomaly: Bool, anomalyReason: String? }
//              Inserts railGateEvents. ON ANOMALY ONLY it also writes blockchainAuditTrail
//              eventType "rail.gate_anomaly" (railGate.ts:79). NO WebSocket emit — this
//              screen therefore re-reads the ledger after every write; it never claims push.
//    EXISTS  railGate.ts:102   railGate.getGateActivity  (QUERY)     → GET via query()
//              in  { windowHours 1..720 = 24, railcarNumber? ≤120, limit 1..500 = 200 }
//              out { events[], counts { gateIn, gateOut, flags, anomalies }, avgTurnMinutes }
//    EXISTS  railGate.ts:32-41 detectAnomaly() — plain case-insensitive, trimmed compare of
//              sealNumber vs ediSeal, then aeiTag vs ediSeal; both sides must be present.
//              The capture sheet's pre-submit preview reproduces exactly that rule (same
//              trim + uppercase + both-present guard) and is labelled as a preview; the
//              SERVER response is the authority the screen renders.
//    MOUNT   routers.ts:3345   railGate: railGateRouter
//
//  FIRST CALLER: this screen is `railGate.recordGateEvent`'s FIRST caller anywhere in the
//  product. Before it shipped the procedure had zero callers on web or iOS, so an AEI or
//  seal-mismatch HOLD — and its blockchainAuditTrail row — could never fire from any
//  client. That is why this screen exists.
//
//  RBAC   WRITE railGateWriter = roleProcedure(RAIL_ENGINEER, RAIL_CONDUCTOR,
//         RAIL_DISPATCHER, RAIL_CATALYST, ADMIN, SUPER_ADMIN) — railGate.ts:20-27.
//         READ  railProcedure — railGate.ts:102. Both are tenant-scoped by ctx company.
//
//  transportMode = rail. COUNTRY IS CONTENT, one screen, no file fork: the credential band
//  carries the gate credential checked per country — US CBP (TWIC · SCAC · driver ID),
//  CA CBSA (FAST · driver ID), MX Aduanas-VUCEM (CTPAT · pedimento). The selection drives
//  the credential prompt the clerk is shown in the capture sheet.
//
//  OFFLINE POLICY (Encyclopedia v2 · honesty law). A gate event is a field capture at a
//  physical gate with poor signal, so the policy is stated, not assumed:
//    · READ_CACHED(30m) — the activity ledger falls back to a last-good on-disk snapshot
//      when the read fails. Serving cache is NEVER silent: a monospaced 10pt staleness
//      line under the hero flips from palette.textTertiary "LIVE · read HH:mm:ss" to
//      Brand.warning "CACHED · N min old · not live", and the hero state pill flips to
//      CACHED. Past the 30m ttl the cache is refused and the honest error card shows.
//    · ONLINE_ONLY(capture) — recordGateEvent is NOT in the six-path offline-eligibility
//      table at Services/EusoTripAPI.swift:1684, so mutation() cannot enqueue it; offline
//      it would hard-fail and the move would be lost. Both CTAs therefore render visibly
//      disabled offline with an explicit on-screen reason. Nothing is silently swallowed
//      (contrast 566:622) — every failure path raises a toast AND an inline state.
//
//  NAMED GAPS (logged, never faked — see the report for proposed TypeScript shapes):
//    · QUEUE(gate) — proposed: add "railGate.recordGateEvent" to the eligibility switch at
//      EusoTripAPI.swift:1684 + an OfflineQueue.enqueueGateEvent lane. Until then the
//      capture stays ONLINE_ONLY on purpose.
//    · Lane inventory — railGate has no lane/appointment model, so the hero's six tiles are
//      the six most-recent DISTINCT railcars and their latest gate state (real rows), not
//      fabricated lane occupancy. No "OPEN lane" is ever invented.
//    · Appointment window, chassis, driver, reefer/genset — drawn in the SVG sub-lines, but
//      no field exists on railGateEvents. The mono sub renders only real columns.
//    · Country/credential — recordGateEvent has no country field (railGate.ts:48-56), so
//      the selection is a live on-screen prompt and is not stamped on the gate record.
//    · yardManagement.checkInTrailer (yardManagement.ts:848) / checkOutTrailer (:922) /
//      getYardLocations (:281) are the TRAILER lane, not the railcar lane. The prior mockup
//      pointed here with stale cites (739/804/246). This SVG draws no trailer affordance,
//      so nothing on this screen calls them.
//
//  WHY IT HELPS: the gate clerk types the car and the two seal numbers once, and the screen
//  tells them immediately whether to release the car or hold it — instead of waving it
//  through and finding the mismatch after it has already interchanged.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct RailGateCheckIn_663: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailGateCheckInBody663() } nav: {
            // Rail Engineer set. COMPLIANCE is current: this screen's only write is a
            // compliance event — an anomaly capture lands on blockchainAuditTrail as
            // "rail.gate_anomaly" (railGate.ts:79) and its whole output is a HOLD/RELEASE
            // ruling on a car, which is the Compliance hub's job (Rail552), not the
            // Shipments board's (Rail551). The SVG <desc> claims SHIPMENTS(current), but
            // that is the same desc block that mis-routes this screen to the trailer-lane
            // yardManagement procedures — a wireframe-era claim, corrected here.
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

// MARK: - Decodable models (railGate.getGateActivity — railGate.ts:102)

private struct GateEvent663: Codable, Identifiable {
    let id: String                  // "rge_<n>" — always emitted (railGate.ts:119)
    let railcarNumber: String?
    let trainId: String?
    let gateType: String?           // "gate_in" | "gate_out" | "flag"
    let site: String?
    let sealNumber: String?
    let ediSeal: String?
    let aeiTag: String?
    let anomaly: Bool?
    let anomalyReason: String?
    let occurredAt: String?         // ISO-8601
}

private struct GateCounts663: Codable {
    let gateIn: Int?
    let gateOut: Int?
    let flags: Int?
    let anomalies: Int?
}

private struct GateActivity663: Codable {
    let events: [GateEvent663]?
    let counts: GateCounts663?
    let avgTurnMinutes: Int?
}

// MARK: - Mutation shapes (railGate.recordGateEvent — railGate.ts:47)

/// Mirrors the zod input at railGate.ts:48-56 exactly. Optionals are written with
/// `encodeIfPresent` so an unset field is ABSENT from the body — `z.string().optional()`
/// rejects an explicit `null`, and this screen is the procedure's first caller, so there
/// is no prior traffic that would have surfaced that.
private struct RecordGateInput663: Encodable {
    let railcarNumber: String
    let gateType: String
    let trainId: String?
    let site: String?
    let sealNumber: String?
    let ediSeal: String?
    let aeiTag: String?

    private enum CodingKeys: String, CodingKey {
        case railcarNumber, gateType, trainId, site, sealNumber, ediSeal, aeiTag
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(railcarNumber, forKey: .railcarNumber)
        try c.encode(gateType, forKey: .gateType)
        try c.encodeIfPresent(trainId, forKey: .trainId)
        try c.encodeIfPresent(site, forKey: .site)
        try c.encodeIfPresent(sealNumber, forKey: .sealNumber)
        try c.encodeIfPresent(ediSeal, forKey: .ediSeal)
        try c.encodeIfPresent(aeiTag, forKey: .aeiTag)
    }
}

private struct GateEventResult663: Decodable, Identifiable {
    let id: String                  // "rge_<n>"
    let success: Bool?
    let gateType: String?
    let anomaly: Bool?
    let anomalyReason: String?
}

// MARK: - Local vocabulary

/// The three server gate verbs (railGate.ts:50). The SVG's CTA pair pre-selects the two
/// directional verbs; `flag` is reachable from the capture sheet's move picker so the full
/// server enum is expressible without inventing a third CTA the wireframe does not draw.
private enum GateMove663: String, CaseIterable, Identifiable {
    case gateIn  = "gate_in"
    case gateOut = "gate_out"
    case flag    = "flag"

    var id: String { rawValue }

    var pill: String {
        switch self {
        case .gateIn:  return "IN"
        case .gateOut: return "OUT"
        case .flag:    return "FLAG"
        }
    }

    var verb: String {
        switch self {
        case .gateIn:  return "Check in"
        case .gateOut: return "Check out"
        case .flag:    return "Flag"
        }
    }

    var icon: String {
        switch self {
        case .gateIn:  return "arrow.right.to.line"
        case .gateOut: return "arrow.right.from.line"
        case .flag:    return "flag.fill"
        }
    }
}

/// Country is content, not a fork: the gate credential a clerk physically checks before
/// the move is recorded. `recordGateEvent` has no country field (railGate.ts:48-56), so
/// this drives the on-screen prompt only — declared as a named gap in the header.
private enum GateCountry663: String, CaseIterable, Identifiable {
    case us, ca, mx

    var id: String { rawValue }

    var title: String {
        switch self {
        case .us: return "US · TWIC"
        case .ca: return "CA · FAST"
        case .mx: return "MX · CTPAT"
        }
    }

    var sub: String {
        switch self {
        case .us: return "SCAC · driver ID"
        case .ca: return "CBSA · driver ID"
        case .mx: return "VUCEM · pedimento"
        }
    }

    var prompt: String {
        switch self {
        case .us: return "US CBP gate — check TWIC card, carrier SCAC and driver ID before recording."
        case .ca: return "CA CBSA gate — check FAST card and driver ID before recording."
        case .mx: return "MX Aduanas-VUCEM gate — check CTPAT status and the pedimento before recording."
        }
    }
}

private enum ToastKind663 {
    case ok, hold, fail

    var color: Color {
        switch self {
        case .ok:   return Brand.success
        case .hold: return Brand.danger
        case .fail: return Brand.warning
        }
    }
}

// MARK: - READ_CACHED(30m) store
//
// Last-good on-disk snapshot of the gate ledger. Present so the honesty law can be kept:
// a cached read is rendered, but visibly marked, and refused outright past the ttl. There
// is no write-side cache here on purpose — captures are ONLINE_ONLY (see header).

private struct GateActivityEnvelope663: Codable {
    let capturedAt: Date
    let value: GateActivity663
}

private enum RailGateCache663 {
    static let ttl: TimeInterval = 30 * 60
    static let ttlLabel = "30m"

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("rail-gate-663", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gate-activity.json")
    }

    static func store(_ value: GateActivity663) {
        guard let fileURL else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(GateActivityEnvelope663(capturedAt: Date(), value: value)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Snapshot + its age, only while inside the ttl. Past the ttl this returns nil so the
    /// caller must show its offline/error state instead of stale numbers dressed as live.
    static func load() -> (value: GateActivity663, age: TimeInterval)? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let env = try? dec.decode(GateActivityEnvelope663.self, from: data) else { return nil }
        let age = Date().timeIntervalSince(env.capturedAt)
        guard age >= 0, age <= ttl else { return nil }
        return (env.value, age)
    }
}

// MARK: - Hero board tile

private struct GateBoardTile663: Identifiable {
    let id: String
    let mark: String
    let state: String
    let tint: Color
}

// MARK: - Body

private struct RailGateCheckInBody663: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    // Request parameters for getGateActivity (server defaults, railGate.ts:103-106).
    private static let windowHours = 24
    private static let rowLimit    = 200
    /// The SVG draws six status tiles in the hero band. Layout constant, not a data value.
    private static let boardTileCount = 6

    // Ledger state
    @State private var data: GateActivity663? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var lastLiveAt: Date? = nil
    @State private var cacheAge: TimeInterval? = nil

    // Capture state (all live user input — nothing is pre-filled)
    @State private var showCapture = false
    @State private var move: GateMove663 = .gateIn
    @State private var railcarText = ""
    @State private var trainText   = ""
    @State private var siteText    = ""
    @State private var sealText    = ""
    @State private var ediSealText = ""
    @State private var aeiText     = ""
    @State private var isSubmitting = false
    @State private var submitError: String? = nil
    @State private var holdResult: GateEventResult663? = nil

    // Country credential (content)
    @State private var country: GateCountry663 = .us

    // Toast
    @State private var toastText: String? = nil
    @State private var toastKind: ToastKind663 = .ok

    // MARK: Derived — every value below resolves from a decoded server field

    private var events: [GateEvent663] { data?.events ?? [] }
    private var counts: GateCounts663? { data?.counts }
    private var anomalyCount: Int { counts?.anomalies ?? 0 }
    private var isCached: Bool { cacheAge != nil }
    private var canCapture: Bool { reach.isOnline && !isSubmitting }

    private var dominantSite: String? {
        var tally: [String: Int] = [:]
        for e in events {
            guard let s = e.site?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { continue }
            tally[s, default: 0] += 1
        }
        return tally.max { $0.value < $1.value }?.key
    }

    private var siteCaption: String { (dominantSite ?? "—").uppercased() }

    private var avgTurnLabel: String {
        guard let m = data?.avgTurnMinutes else { return "—" }
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }

    /// The six most-recent DISTINCT railcars and their latest gate state. Real rows only —
    /// railGate has no lane inventory, so no empty lane is ever fabricated (named gap).
    private var boardTiles: [GateBoardTile663] {
        var seen = Set<String>()
        var out: [GateBoardTile663] = []
        for e in events {
            guard let car = e.railcarNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !car.isEmpty, !seen.contains(car) else { continue }
            seen.insert(car)
            let k = kind(e)
            out.append(GateBoardTile663(id: car, mark: reportingMark(car), state: k.label, tint: k.color))
            if out.count == Self.boardTileCount { break }
        }
        return out
    }

    private func reportingMark(_ car: String) -> String {
        let head = car.split(separator: " ").first.map(String.init) ?? car
        return String(head.prefix(6)).uppercased()
    }

    private func kind(_ e: GateEvent663) -> (label: String, color: Color, icon: String) {
        if e.anomaly == true { return ("HOLD", Brand.danger, "exclamationmark.octagon.fill") }
        switch e.gateType {
        case GateMove663.gateIn.rawValue:  return ("IN",   Brand.success, GateMove663.gateIn.icon)
        case GateMove663.gateOut.rawValue: return ("OUT",  Brand.rail,    GateMove663.gateOut.icon)
        case GateMove663.flag.rawValue:    return ("FLAG", Brand.warning, GateMove663.flag.icon)
        default:                           return ("MOVE", palette.textTertiary, "circle")
        }
    }

    /// Hero state pill. HOLD outranks everything — that is the ruling this screen exists to
    /// make. Otherwise it reports the honest freshness of the ledger under it.
    private var statePill: (text: String, color: Color) {
        if anomalyCount > 0 { return ("HOLD", Brand.danger) }
        if !reach.isOnline  { return ("OFFLINE", palette.textTertiary) }
        if isCached         { return ("CACHED", Brand.warning) }
        if data == nil      { return ("NO READ", palette.textTertiary) }
        return ("LIVE", Brand.success)
    }

    /// READ_CACHED staleness line — monospaced 10pt, tertiary when live, Brand.warning the
    /// moment the screen is painting a snapshot instead of a live read.
    private var staleness: (text: String, warn: Bool) {
        if let age = cacheAge {
            let mins = max(Int(age / 60), 0)
            let old = mins < 1 ? "under a minute" : (mins == 1 ? "1 min" : "\(mins) min")
            return ("READ_CACHED(\(RailGateCache663.ttlLabel)) · CACHED · \(old) old · not live", true)
        }
        guard let at = lastLiveAt else {
            return ("READ_CACHED(\(RailGateCache663.ttlLabel)) · awaiting first read", false)
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return ("READ_CACHED(\(RailGateCache663.ttlLabel)) · LIVE · read \(f.string(from: at))", false)
    }

    private func shortTime(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return out.string(from: d) }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: iso) { return out.string(from: d) }
        return String(iso.prefix(16))
    }

    /// Mono sub-line for a ledger row — only columns the server actually returned.
    private func subLine(_ e: GateEvent663) -> String {
        var parts: [String] = []
        if let s = e.site, !s.isEmpty { parts.append(s) }
        if let t = e.trainId, !t.isEmpty { parts.append("train \(t)") }
        if let s = e.sealNumber, !s.isEmpty { parts.append("seal \(s)") }
        if let s = e.ediSeal, !s.isEmpty { parts.append("EDI-322 \(s)") }
        if let a = e.aeiTag, !a.isEmpty { parts.append("AEI \(a)") }
        return parts.isEmpty ? "gate move · no site recorded" : parts.joined(separator: " · ")
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                if loading && data == nil {
                    LifecycleCard {
                        Text("Loading the gate ledger…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError, data == nil {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        Text("Pull to retry. Nothing is being shown from cache — the last snapshot is older than \(RailGateCache663.ttlLabel).")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else {
                    heroBoard
                    stalenessRow
                    if anomalyCount > 0 { holdBand }
                    gateQueue
                }
                countryBand
                ctaPair
                if !reach.isOnline { onlineOnlyNotice }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showCapture) { captureSheet }
    }

    // MARK: - TopBar (DETAIL)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("\u{2726} RAIL ENGINEER · GATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: 8)
                Text("RAMP · \(siteCaption)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Gate check-in")
                    .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - LIVE GATE BOARD hero

    private var heroBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("LIVE GATE · \(siteCaption) · \(boardTiles.count) CAR\(boardTiles.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle().fill(statePill.color).frame(width: 6, height: 6)
                    Text(statePill.text)
                        .font(.system(size: 10, weight: .heavy)).kerning(0.4)
                        .foregroundStyle(statePill.color)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(statePill.color.opacity(0.14)))
            }

            if boardTiles.isEmpty {
                Text("No cars have crossed this gate in the last \(Self.windowHours)h.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    ForEach(boardTiles) { tile in boardTile(tile) }
                }
            }

            HStack(spacing: 0) {
                flowStat("IN · \(Self.windowHours)h", "\(counts?.gateIn ?? 0)", Brand.success)
                flowStat("OUT · \(Self.windowHours)h", "\(counts?.gateOut ?? 0)", Brand.rail)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Text("avg turn").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    Text(avgTurnLabel)
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func boardTile(_ tile: GateBoardTile663) -> some View {
        VStack(spacing: 6) {
            Text(tile.mark)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(tile.tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Circle().fill(tile.tint).frame(width: 8, height: 8)
            Text(tile.state)
                .font(.system(size: 9, weight: .bold)).kerning(0.4)
                .foregroundStyle(tile.tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity).frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tile.tint.opacity(0.12))
        )
    }

    private func flowStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.trailing, 12)
    }

    // MARK: - Staleness line (READ_CACHED honesty)

    private var stalenessRow: some View {
        let s = staleness
        return HStack(spacing: 6) {
            Image(systemName: s.warn ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
            Text(s.text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    // MARK: - HOLD band (the ruling this screen exists to make)

    private var holdBand: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 3) {
                Text("HOLD · \(anomalyCount) seal / AEI mismatch\(anomalyCount == 1 ? "" : "es")")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("The seal or AEI tag read at the gate disagrees with the EDI-322 seal of record. Hold the car for a re-read before it interchanges.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Text("logged to the immutable audit trail · rail.gate_anomaly")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.30))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - GATE QUEUE · live feed

    private var gateQueue: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("GATE QUEUE · LIVE FEED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\(events.count) move\(events.count == 1 ? "" : "s") · last \(Self.windowHours)h")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.bottom, Space.s3)

            if events.isEmpty {
                LifecycleCard {
                    Text("No railcar gate moves in the last \(Self.windowHours)h.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("Check a car in or out below and the move lands here.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            } else {
                VStack(spacing: 0) {
                    // SVG draws a hairline after every row, including the last, so the
                    // footer line reads as part of the same ledger card.
                    ForEach(events) { e in
                        moveRow(e)
                        Divider().padding(.leading, 68).overlay(palette.borderFaint)
                    }
                    queueFooter
                }
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func moveRow(_ e: GateEvent663) -> some View {
        let k = kind(e)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(k.color.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: k.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(k.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.railcarNumber ?? "—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(subLine(e))
                        .font(.system(size: 11, weight: .regular, design: .monospaced)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(k.label)
                        .font(.system(size: 11, weight: .bold)).kerning(0.6)
                        .foregroundStyle(k.color)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(k.color.opacity(0.14)))
                    Text(shortTime(e.occurredAt))
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }

            // The HOLD, inline and verbatim from the server.
            if e.anomaly == true {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                        Text(e.anomalyReason ?? "Seal / AEI disagreement recorded at the gate.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(sealTriple(e))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.danger.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Brand.danger.opacity(0.30))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .padding(.leading, 52)
            }
        }
        .padding(16)
    }

    /// The three values detectAnomaly() compares (railGate.ts:32-41), so the clerk can see
    /// which two disagreed rather than taking the sentence on faith.
    private func sealTriple(_ e: GateEvent663) -> String {
        "read \(e.sealNumber ?? "—") · EDI-322 \(e.ediSeal ?? "—") · AEI \(e.aeiTag ?? "—")"
    }

    /// The SVG's footer line. Live: the newest held car when there is one, otherwise the
    /// newest move. No appointment model exists on railGate (named gap), so nothing about
    /// a "next appointment" is claimed.
    private var queueFooter: some View {
        let held = events.first { $0.anomaly == true }
        let latest = events.first
        let tint: Color = held != nil ? Brand.danger : Brand.blue

        return HStack(spacing: 10) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Group {
                if let h = held {
                    (Text("Held ").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                     + Text(h.railcarNumber ?? "—").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.danger)
                     + Text(" · \(h.anomalyReason ?? "seal / AEI mismatch")").font(.system(size: 11)).foregroundStyle(palette.textSecondary))
                } else if let l = latest {
                    (Text("Last move ").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                     + Text(l.railcarNumber ?? "—").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                     + Text(" · \(kind(l).label.lowercased()) · \(shortTime(l.occurredAt))").font(.system(size: 11)).foregroundStyle(palette.textSecondary))
                } else {
                    Text("No moves in this window.").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - Tri-country credential band (country is content)

    private var countryBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("GATE CHECK-IN · CREDENTIAL BY COUNTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(GateCountry663.allCases) { c in countryTile(c) }
            }
            Text("Credential prompt only — the gate record carries no country field yet.")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
    }

    private func countryTile(_ c: GateCountry663) -> some View {
        let selected = c == country
        return Button { country = c } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? palette.textOnGradient : palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(c.sub)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(selected ? palette.textOnGradient.opacity(0.9) : palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.clear : palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(c.title) gate credential")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - CTA pair (the first callers of recordGateEvent)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { openCapture(.gateIn) } label: {
                HStack(spacing: 8) {
                    Image(systemName: GateMove663.gateIn.icon)
                        .font(.system(size: 14, weight: .heavy))
                    Text("Check in").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(palette.textOnGradient)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(LinearGradient.primary))
                .opacity(canCapture ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canCapture)
            .accessibilityLabel(canCapture ? "Check a railcar in at the gate"
                                           : "Check in unavailable — offline")

            Button { openCapture(.gateOut) } label: {
                Text("Check out")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(width: 148, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .opacity(canCapture ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canCapture)
            .accessibilityLabel(canCapture ? "Check a railcar out at the gate"
                                           : "Check out unavailable — offline")
        }
    }

    /// ONLINE_ONLY(capture), stated in full. Nothing queues, so nothing pretends to.
    private var onlineOnlyNotice: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Offline · gate capture is ONLINE_ONLY")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("A gate move cannot be queued on this device — recording it is not one of the six actions the offline outbox can replay, so the capture would be lost rather than held. Reconnect to record. The ledger above is a stored snapshot.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.30))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Capture sheet

    private func openCapture(_ m: GateMove663) {
        move = m
        submitError = nil
        holdResult = nil
        showCapture = true
    }

    private var trimmedRailcar: String {
        railcarText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedRailcar.isEmpty && reach.isOnline && !isSubmitting
    }

    /// Local preview of detectAnomaly() (railGate.ts:32-41) with the SAME rule: trim,
    /// upper-case, and only compare when BOTH sides are present. The server remains the
    /// authority — this only warns the clerk before they commit.
    private var anomalyPreview: String? {
        let norm: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let seal = norm(sealText), edi = norm(ediSealText), aei = norm(aeiText)
        if !edi.isEmpty, !seal.isEmpty, edi != seal {
            return "Seal mismatch: read \(seal) vs EDI-322 \(edi)"
        }
        if !edi.isEmpty, !aei.isEmpty, aei != edi {
            return "AEI tag \(aei) disagrees with EDI-322 seal \(edi)"
        }
        return nil
    }

    private var captureSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: move.icon)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("GATE CAPTURE · EDI-322 SEAL CHECK")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }

                Text("\(move.verb) \(trimmedRailcar.isEmpty ? "a railcar" : trimmedRailcar)")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7)

                Text("The seal read at the gate and the AEI tag are compared against the EDI-322 seal of record. A disagreement holds this car and writes the hold to the immutable audit trail.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let hold = holdResult {
                    holdResultPanel(hold)
                } else {
                    movePicker
                    captureFields
                    if let preview = anomalyPreview { previewBanner(preview) }
                    credentialLine
                    if let err = submitError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    confirmButton(
                        title: "\(move.verb) · record gate move",
                        busy: isSubmitting,
                        enabled: canSubmit
                    ) {
                        Task { await recordGateEvent() }
                    }
                    if !reach.isOnline {
                        Text("Offline — this capture cannot be queued and will not be sent.")
                            .font(EType.caption).foregroundStyle(Brand.warning)
                    } else if trimmedRailcar.isEmpty {
                        Text("Enter the railcar number to record a move.")
                            .font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                }
                Color.clear.frame(height: 24)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var movePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("MOVE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(GateMove663.allCases) { m in
                    Button { move = m } label: {
                        HStack(spacing: 6) {
                            Image(systemName: m.icon).font(.system(size: 11, weight: .heavy))
                            Text(m.verb).font(.system(size: 12, weight: .heavy))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(move == m ? Brand.blue : palette.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(move == m ? Brand.blue.opacity(0.14) : palette.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(move == m ? Brand.blue.opacity(0.45) : palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var captureFields: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            field("RAILCAR NUMBER · required", text: $railcarText, placeholder: "e.g. reporting mark + number")
            field("TRAIN ID · optional", text: $trainText, placeholder: "train symbol")
            field("SITE / RAMP · optional", text: $siteText, placeholder: "gate or ramp name")
            field("SEAL READ AT GATE · optional", text: $sealText, placeholder: "physical seal")
            field("EDI-322 SEAL OF RECORD · optional", text: $ediSealText, placeholder: "seal on the 322")
            field("AEI TAG · optional", text: $aeiText, placeholder: "AEI tag read")
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func previewBanner(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("This will raise a HOLD")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text(reason)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Local preview of the gate rule — the server makes the ruling.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.30))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var credentialLine: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Brand.info)
            Text(country.prompt)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// The server's ruling, rendered decisively. This is the state that could never be
    /// reached from any client before this screen shipped.
    private func holdResultPanel(_ hold: GateEventResult663) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("HOLD RAISED")
                    .font(.system(size: 18, weight: .heavy)).kerning(0.4)
                    .foregroundStyle(Brand.danger)
            }
            Text(hold.anomalyReason ?? "The seal or AEI read disagrees with the EDI-322 seal of record.")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("read \(sealText.isEmpty ? "—" : sealText) · EDI-322 \(ediSealText.isEmpty ? "—" : ediSealText) · AEI \(aeiText.isEmpty ? "—" : aeiText)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Do not interchange \(trimmedRailcar.isEmpty ? "this car" : trimmedRailcar). The move was recorded as \(hold.id) and the hold is on the immutable audit trail as rail.gate_anomaly.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showCapture = false
                holdResult = nil
                clearCaptureFields()
            } label: {
                HStack {
                    Spacer()
                    Text("Acknowledge hold")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textOnGradient)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Brand.danger)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func confirmButton(title: String, busy: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if busy {
                    ProgressView().tint(palette.textOnGradient)
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textOnGradient)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func clearCaptureFields() {
        railcarText = ""; trainText = ""; siteText = ""
        sealText = ""; ediSealText = ""; aeiText = ""
        submitError = nil
    }

    // MARK: - Toast

    private var toastView: some View {
        Group {
            if let t = toastText {
                Text(t)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textOnGradient)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(toastKind.color))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ msg: String, kind: ToastKind663) {
        toastKind = kind
        withAnimation(.easeOut(duration: 0.18)) { toastText = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toastText = nil }
        }
    }

    // MARK: - Data

    /// GET railGate.getGateActivity (railGate.ts:102, query). On failure the READ_CACHED
    /// snapshot is served and visibly marked; past ttl the honest error card shows instead.
    private func load() async {
        loading = true
        struct In: Encodable { let windowHours: Int; let limit: Int }
        do {
            let fresh: GateActivity663 = try await EusoTripAPI.shared.query(
                "railGate.getGateActivity",
                input: In(windowHours: Self.windowHours, limit: Self.rowLimit)
            )
            data = fresh
            cacheAge = nil
            lastLiveAt = Date()
            loadError = nil
            RailGateCache663.store(fresh)
        } catch {
            let message = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            if let cached = RailGateCache663.load() {
                data = cached.value
                cacheAge = cached.age
                loadError = nil
            } else {
                data = nil
                cacheAge = nil
                loadError = message
            }
        }
        loading = false
    }

    /// POST railGate.recordGateEvent (railGate.ts:47, MUTATION — mutation(), never query();
    /// the server has no method override, so a GET here would be fault class S4).
    ///
    /// ONLINE_ONLY: the path is absent from the offline-eligibility table at
    /// EusoTripAPI.swift:1684, so an offline attempt hard-fails and nothing queues — the
    /// CTAs are already disabled offline, and this guard is the second lock.
    private func recordGateEvent() async {
        let car = String(trimmedRailcar.prefix(120))
        guard !car.isEmpty else {
            submitError = "Enter the railcar number."
            return
        }
        guard reach.isOnline else {
            submitError = "Offline — a gate move cannot be queued on this device. Reconnect to record it."
            showToast("Offline — gate capture not sent", kind: .fail)
            return
        }

        func opt(_ s: String, _ max: Int) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : String(t.prefix(max))
        }

        let input = RecordGateInput663(
            railcarNumber: car,
            gateType: move.rawValue,
            trainId: opt(trainText, 120),
            site: opt(siteText, 255),
            sealNumber: opt(sealText, 64),
            ediSeal: opt(ediSealText, 64),
            aeiTag: opt(aeiText, 64)
        )

        isSubmitting = true
        submitError = nil
        do {
            let res: GateEventResult663 = try await EusoTripAPI.shared.mutation(
                "railGate.recordGateEvent", input: input
            )
            if res.anomaly == true {
                holdResult = res
                showToast("HOLD raised on \(car) — do not interchange", kind: .hold)
            } else {
                showCapture = false
                clearCaptureFields()
                showToast("\(move.pill) recorded · \(car)", kind: .ok)
            }
            await load()
        } catch {
            let message = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            submitError = message
            showToast("Gate move not recorded — \(message)", kind: .fail)
        }
        isSubmitting = false
    }
}

#Preview("663 · Rail Gate Check-In · Night") {
    RailGateCheckIn_663(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("663 · Rail Gate Check-In · Light") {
    RailGateCheckIn_663(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
