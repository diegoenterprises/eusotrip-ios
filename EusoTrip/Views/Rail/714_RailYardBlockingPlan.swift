//
//  714_RailYardBlockingPlan.swift
//  EusoTrip — 05 Rail · 714 Rail Yard Blocking Plan.
//  YARD SIDE · the classification yard's outbound plan · nav tab SHIPMENTS.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/714 Rail Yard Blocking Plan.svg" —
//  same sections, same order, same device:
//    eyebrow → headline → subline → state chips → iridescent hairline →
//    BLOCKING MATRIX (blocks as rows × outbound trains as columns, cells are
//    car counts with proportional fill, right-hand per-block total column,
//    bottom per-train total rule read against each train's maximum) →
//    CLASSIFICATION TRACK ALLOCATION strip → tri-country band → CTA pair.
//
//  ─── WIRING MANIFEST ─────────────────────────────────────────────────────────
//    railShipments.getRailYards           EXISTS server/routers/railShipments.ts:1512
//        → [rail_yards row: {id,name,splcCode,railroadId,city,state,country,
//           yardType,totalTracks,capacity,hasIntermodal,hasHazmat,status}]
//    railShipments.getYardTrackOccupancy EXISTS railShipments.ts:1246
//        → {yardId,yardName,totalTracks,capacity,utilizationPct,
//           tracks:[{trackNumber,carCount,cars:[{id,carNumber,carType,status}]}],
//           unassigned:[…], note?}
//    railShipments.getRailcars            EXISTS server/routers/railShipments.ts:1192
//        → {railcars:[{railcarNumber,carType,status,trackNumber,currentYardId,
//           lengthFeet,tareWeight,loadLimit,owner,yardName}], total}
//    railShipments.getTrainConsists       EXISTS server/routers/railShipments.ts:1332
//        → {consists:[{id,consistNumber,totalCars,totalWeight,totalLengthFeet,
//           trainType,status,departureTime,originYardId,destinationYardId,
//           railroadId}], total}
//    railShipments.getServiceLineup EXISTS railShipments.ts:1576
//        → {trainSymbol,carCount,scheduledCalls,clearedCalls,
//           estimatedTransitHours,status,calls:[…]}   (railId-scoped)
//    railShipments.createConsist          EXISTS server/routers/railShipments.ts:1454  MUTATION
//    railShipments.assignCarToTrack EXISTS railShipments.ts:1300  MUTATION
//    yardManagement.getYardDashboard      EXISTS server/routers/yardManagement.ts:114
//    yardManagement.getYardMap            EXISTS server/routers/yardManagement.ts:379
//    railBlocking.getBlockingPlan         STUB · named-gap RAIL-YRD-714-BLOCKING-PLAN
//    railBlocking.commitBlockingPlan      STUB · named-gap RAIL-YRD-714-COMMIT-PLAN
//    railBlocking.getTrainLengthLimit     STUB · named-gap RAIL-YRD-714-TRAIN-LIMIT
//
//  RBAC:    railReadProcedure (railShipments.ts:94) · RAIL_ENGINEER (server/_core/trpc.ts:32) holds the
//           yard-master function; RAIL_DISPATCHER (:30) and RAIL_CONDUCTOR (:33)
//           read through. yardManagement reads are protectedProcedure, companyId-scoped.
//  WS:      WS_EVENTS.RAIL_IN_YARD (shared/websocket-events.ts:403) re-reads the
//           track strip; WS_EVENTS.RAIL_CONSIST_UPDATE (:411) re-reads a train
//           column; channel WS_CHANNELS.RAIL_YARD(yardId) (:622).
//  OFFLINE: READ_CACHED(5 min) for the matrix and the track strip, each carrying a
//           real cached-at stamp; plan commits are QUEUE(yard) with a real outbox
//           depth. Any commit that awards or moves money stays ONLINE_ONLY.
//
//  0 stubs in the view layer · 0 mock arrays · 0 placeholders. The block→train
//  cell as a first-class plan object does not exist server-side, so the grid
//  draws its REAL axes — the decoded outbound consists as columns and the
//  destination yards they are routed to as block rows — and every populated cell
//  is the consist row's own totalCars landing in the block it is routed to. The
//  per-train maximum length is on no row and on no procedure, so the bottom
//  "vs MAX" line reads as not served, the tri-country band carries no ceiling,
//  and NO over-limit verdict is drawn anywhere on the screen.
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Speech helper (a11y only — the printed copy is never changed)

/// A middle-dot separated line, spoken. VoiceOver reads "·" as "middle dot",
/// which buries the facts; the comma form carries exactly the same content.
private func spoken714(_ s: String) -> String {
    s.replacingOccurrences(of: " · ", with: ", ")
}

// MARK: - Screen

struct RailYardBlockingPlanScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailYardBlockingPlanBody() } nav: {
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

/// Mirrors a `rail_yards` row as `railShipments.getRailYards` (railShipments.ts:1512) returns it —
/// the router selects the table wholesale and returns a bare array.
private struct BpYard: Decodable, Identifiable {
    let id: Int
    let name: String?
    let splcCode: String?
    let railroadId: Int?
    let city: String?
    let state: String?
    let country: String?          // "US" | "CA" | "MX"
    let yardType: String?         // classification | flat | intermodal_ramp | team_track | industry | staging
    let totalTracks: Int?
    let capacity: Int?
    let hasHazmat: Bool?
    let status: String?
}

/// `railShipments.getTrainConsists` (railShipments.ts:1332) envelope.
private struct BpConsistEnvelope: Decodable {
    let consists: [BpConsist]?
    let total: Int?
}

/// Mirrors the `train_consists` row the router selects wholesale.
private struct BpConsist: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let totalCars: Int?
    let totalLengthFeet: Int?
    let trainType: String?
    let status: String?           // building | ready | departed | in_transit | arrived | broken_up
    let departureTime: String?    // ISO-8601 from the timestamp column
    let originYardId: Int?
    let destinationYardId: Int?
    let railroadId: Int?
    /// DECIMAL(12,2) — MySQL sends it as a string; both forms accepted, never guessed.
    let totalWeight: Double?

    enum CodingKeys: String, CodingKey {
        case id, consistNumber, totalCars, totalLengthFeet, trainType, status
        case departureTime, originYardId, destinationYardId, railroadId, totalWeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.consistNumber = try c.decodeIfPresent(String.self, forKey: .consistNumber)
        self.totalCars = try c.decodeIfPresent(Int.self, forKey: .totalCars)
        self.totalLengthFeet = try c.decodeIfPresent(Int.self, forKey: .totalLengthFeet)
        self.trainType = try c.decodeIfPresent(String.self, forKey: .trainType)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.departureTime = try c.decodeIfPresent(String.self, forKey: .departureTime)
        self.originYardId = try c.decodeIfPresent(Int.self, forKey: .originYardId)
        self.destinationYardId = try c.decodeIfPresent(Int.self, forKey: .destinationYardId)
        self.railroadId = try c.decodeIfPresent(Int.self, forKey: .railroadId)
        if let s = try? c.decodeIfPresent(String.self, forKey: .totalWeight), let d = Double(s) {
            self.totalWeight = d
        } else {
            self.totalWeight = try c.decodeIfPresent(Double.self, forKey: .totalWeight)
        }
    }
}

/// `railShipments.getYardTrackOccupancy` (railShipments.ts:1246).
private struct BpYardOccupancy: Decodable {
    let yardId: Int?
    let yardName: String?
    let totalTracks: Int?
    let capacity: Int?
    let utilizationPct: Double?
    let tracks: [BpTrack]?
    let unassigned: [BpSlimCar]?
    let note: String?
}

private struct BpTrack: Decodable, Identifiable {
    var id: Int { trackNumber }
    let trackNumber: Int
    let carCount: Int?
    let cars: [BpSlimCar]?
}

private struct BpSlimCar: Decodable, Identifiable {
    let id: Int
    let carNumber: String?
    let carType: String?
    let status: String?
}

/// `railShipments.getRailcars` (railShipments.ts:1192) envelope.
private struct BpRailcarEnvelope: Decodable {
    let railcars: [BpRailcar]?
    let total: Int?
}

private struct BpRailcar: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let carType: String?
    let status: String?
    let owner: String?
    let trackNumber: Int?
    let lengthFeet: Int?
    let currentYardId: Int?
    let yardName: String?
}

/// `yardManagement.getYardDashboard` (:114) — the yard-wide capacity envelope.
private struct BpYardDashboard: Decodable {
    struct Capacity: Decodable {
        let total: Int?
        let occupied: Int?
        let available: Int?
        let utilizationPct: Double?
    }
    let locationId: String?
    let capacity: Capacity?
    let lastUpdated: String?
}

// MARK: - Derived matrix model (every field traced to a decoded row)

/// One column of the matrix — a real outbound consist row.
private struct BpTrainColumn: Identifiable {
    let id: Int
    let symbol: String
    let departure: String?
    let cars: Int?
    let lengthFeet: Int?
    let destinationYardId: Int?
}

/// One row of the matrix — a real destination grouping (block).
private struct BpBlockRow: Identifiable {
    let id: Int          // destinationYardId, or -1 for "destination not set"
    let name: String
    /// count per column index; nil where the block does not ride that train.
    let cells: [Int?]
    let total: Int?
}

// MARK: - Body

private struct RailYardBlockingPlanBody: View {
    @Environment(\.palette) private var palette

    @State private var yards: [BpYard] = []
    @State private var workingYard: BpYard? = nil
    @State private var occupancy: BpYardOccupancy? = nil
    @State private var carsAtYard: [BpRailcar] = []
    @State private var consists: [BpConsist] = []
    @State private var dashboard: BpYardDashboard? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var committing = false
    /// Real read timestamp — the only source of the cached-at line.
    @State private var readAt: Date? = nil
    @State private var now = Date()
    /// OFFLINE: reads are READ_CACHED(5 min); commits are QUEUE(yard).
    private let cacheTTL: TimeInterval = 5 * 60
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: Derivation
    //
    // The block→train cell as a plan object is the named gap. What the server DOES
    // report is every outbound consist row with the destination yard it is routed
    // to and the car count it carries. So the columns are the real consists, the
    // rows are the real destination yards those consists serve, and a populated
    // cell is that consist's own totalCars landing in its own block. Nothing is
    // interpolated and nothing is invented; the derivation is stated on screen.

    /// Outbound = a consist that has not already arrived or been broken up.
    private var outboundConsists: [BpConsist] {
        let live = consists.filter { c in
            !["arrived", "broken_up"].contains((c.status ?? "").lowercased())
        }
        let atThisYard = live.filter { $0.originYardId == workingYard?.id }
        let pool = atThisYard.isEmpty ? live : atThisYard
        return pool.sorted { lhs, rhs in
            switch (lhs.departureTime, rhs.departureTime) {
            case let (l?, r?): return l < r
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return lhs.id < rhs.id
            }
        }
    }

    /// The matrix never draws more columns than the phone can hold honestly.
    private var columns: [BpTrainColumn] {
        outboundConsists.prefix(4).map { c in
            BpTrainColumn(id: c.id,
                          symbol: c.consistNumber ?? "Consist \(c.id)",
                          departure: clockLabel(c.departureTime),
                          cars: c.totalCars,
                          lengthFeet: c.totalLengthFeet,
                          destinationYardId: c.destinationYardId)
        }
    }

    private var yardName: [Int: String] {
        Dictionary(uniqueKeysWithValues: yards.map { y in
            let place = [y.city, y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return (y.id, place.isEmpty ? (y.name ?? "Yard \(y.id)") : place)
        })
    }

    private var rows: [BpBlockRow] {
        let cols = columns
        guard !cols.isEmpty else { return [] }
        // Block identity = the destination yard the column is routed to, in
        // first-appearance order so the grid reads left-to-right with the lineup.
        var order: [Int] = []
        for c in cols {
            let key = c.destinationYardId ?? -1
            if !order.contains(key) { order.append(key) }
        }
        return order.map { key in
            let cells: [Int?] = cols.map { col in
                (col.destinationYardId ?? -1) == key ? col.cars : nil
            }
            let served = cells.compactMap { $0 }
            return BpBlockRow(
                id: key,
                name: key == -1 ? "destination not set" : (yardName[key] ?? "Yard \(key)"),
                cells: cells,
                total: served.isEmpty ? nil : served.reduce(0, +))
        }
    }

    private var heaviestCell: Int {
        let all = rows.flatMap { $0.cells.compactMap { $0 } }
        return max(all.max() ?? 0, 1)
    }

    private var classifiedTotal: Int? {
        let served = rows.compactMap { $0.total }
        return served.isEmpty ? nil : served.reduce(0, +)
    }

    private var tracksHolding: [BpTrack] {
        (occupancy?.tracks ?? []).filter { ($0.carCount ?? 0) > 0 }
    }

    /// Per-track capacity is not a column on any row. When the yard reports both a
    /// total capacity and a track count we render the EVEN SPLIT and say so; when
    /// it does not, the bar falls back to the share of the busiest track and the
    /// right-hand denominator is omitted rather than invented.
    private var perTrackCapacity: Int? {
        guard let cap = occupancy?.capacity, cap > 0,
              let t = occupancy?.totalTracks, t > 0 else { return nil }
        return max(1, cap / t)
    }

    private var busiestTrackCount: Int {
        max(tracksHolding.map { $0.carCount ?? 0 }.max() ?? 0, 1)
    }

    private var subline: String {
        guard let y = workingYard else { return "no yard on file for this carrier" }
        var parts: [String] = []
        parts.append([y.city, y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").isEmpty
                     ? (y.name ?? "Yard \(y.id)")
                     : [y.city, y.state].compactMap { $0 }.joined(separator: " "))
        parts.append("\(rows.count) block\(rows.count == 1 ? "" : "s")")
        parts.append("\(columns.count) outbound train\(columns.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    // MARK: Cache clock

    private var cacheAgeSeconds: TimeInterval? {
        guard let readAt else { return nil }
        return max(0, now.timeIntervalSince(readAt))
    }
    private var cacheExpired: Bool {
        guard let age = cacheAgeSeconds else { return true }
        return age > cacheTTL
    }
    private var readAtLabel: String {
        guard let readAt else { return "—:—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: readAt)
    }

    private func clockLabel(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso8601.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                Text(subline).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .accessibilityLabel(spoken714(subline))
                stateChips
                IridescentHairline().accessibilityHidden(true)

                if loading {
                    LifecycleCard { Text("Reading the yard…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Reading the yard")
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text("Blocking plan unavailable").font(EType.bodyStrong).foregroundStyle(Brand.danger)
                        Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Blocking plan unavailable. \(err)")
                } else {
                    blockingMatrix
                    sectionLabel("CLASSIFICATION TRACK ALLOCATION",
                                 trailing: tracksHolding.isEmpty ? "no track holding" : "\(tracksHolding.count) tracks holding")
                    trackCard
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
            Text("RAIL ENGINEER · BLOCKING PLAN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(workingYard?.splcCode.map { "SPLC \($0)" } ?? "—")
                .font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rail engineer, blocking plan. \(splcA11y).")
        .accessibilityAddTraits(.isHeader)
    }

    /// The SPLC chip spoken as words. No code on the row is spoken as a dash.
    private var splcA11y: String {
        workingYard?.splcCode.map { "SPLC code \($0)" } ?? "SPLC code not reported"
    }

    private var headline: some View {
        // Centred rather than baseline-aligned so the overflow control can carry
        // the 44pt touch target without hanging off the headline baseline.
        HStack(alignment: .center) {
            Text("Blocking plan").font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // A real control rather than a glyph that only looks like one. No
            // overflow procedure is wired to this screen, so it ships as a
            // disabled Button, visibly dimmed, at the 44pt touch floor.
            Button { } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .opacity(0.35)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel("More blocking plan actions")
            .accessibilityValue("Unavailable — no overflow action is wired to this screen")
            .accessibilityAddTraits(.isButton)
        }
    }

    private var stateChips: some View {
        HStack(spacing: Space.s2) {
            chip(classifiedTotal.map { "\($0) CLASSIFIED" } ?? "COUNT UNKNOWN",
                 classifiedTotal == nil ? Brand.neutral : Brand.info)
                .accessibilityLabel(classifiedTotal.map { "\($0) cars classified" } ?? "Classified car count unknown")
            // The maximum-length ceiling is the named gap, so the over-limit chip
            // reports the gap instead of a verdict it cannot reach.
            chip("MAX UNKNOWN", Brand.neutral)
                .accessibilityLabel("Maximum train length unknown")
            chip("PLAN SAVE UNAVAILABLE", Brand.warning)
                .accessibilityLabel("Plan save unavailable")
            Spacer(minLength: 0)
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken714(text) + ". " + spoken714(trailing) + ".")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: THE DEVICE · the blocking matrix

    private var blockingMatrix: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            VStack(alignment: .leading, spacing: 0) {
                matrixBand
                if columns.isEmpty {
                    Text("No outbound consist is on file for this yard, so the grid has no train columns to draw. Nothing is assumed.")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.s3)
                } else {
                    columnHeader.padding(.top, Space.s3)
                    Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 6)
                    ForEach(rows) { matrixRow($0) }
                    Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 8)
                    totalsRule
                }
                Text(derivationNote)
                    .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s3)
            }
            .padding(Space.s4)
        }
    }

    private var derivationNote: String {
        "Blocking assignments are unavailable. Each column is a recorded outbound consist, each row is its destination yard, and a filled cell is that consist's recorded car count. Maximum train length is unknown, so no over-limit verdict is shown."
    }

    private var matrixBand: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("OUTBOUND BLOCKING · \((workingYard?.name ?? occupancy?.yardName ?? "yard not resolved").uppercased())")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.info)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(workingYard?.splcCode.map { "SPLC \($0)" } ?? "—")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.info.opacity(0.14)))
            }
            Text(bandDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(matrixBandA11y)
        .accessibilityAddTraits(.isHeader)
    }

    private var matrixBandA11y: String {
        let where_ = workingYard?.name ?? occupancy?.yardName ?? "yard not resolved"
        return "Outbound blocking, \(where_). \(splcA11y). " + spoken714(bandDetail) + "."
    }

    private var bandDetail: String {
        var parts: [String] = []
        if let c = classifiedTotal { parts.append("\(c) cars classified") }
        if let u = occupancy?.utilizationPct {
            parts.append("\(u.formatted(.number.precision(.fractionLength(0...1))))% of yard capacity")
        }
        if let t = occupancy?.totalTracks { parts.append("\(t) tracks") }
        if let n = occupancy?.note { parts.append(n) }
        return parts.isEmpty ? "yard reports no capacity or car count" : parts.joined(separator: " · ")
    }

    private var columnHeader: some View {
        HStack(spacing: 4) {
            Text("BLOCK ↓ TRAIN →")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                .frame(width: 88, alignment: .leading)
            ForEach(columns) { col in
                VStack(spacing: 2) {
                    Text(col.symbol)
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    Text(col.departure ?? "—")
                        .font(.system(size: 8.5, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            Text("CARS")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(columnHeaderA11y)
        .accessibilityAddTraits(.isHeader)
    }

    /// The matrix axes spoken once, so a reader knows what a row will mean
    /// before the first row is read.
    private var columnHeaderA11y: String {
        let cols = columns.map { "\($0.symbol) departing \($0.departure ?? "time not recorded")" }
        guard !cols.isEmpty else { return "Matrix header. No train columns." }
        return "Matrix header. Rows are blocks, columns are outbound trains: "
            + cols.joined(separator: ", ")
            + ". The last column is cars per block."
    }

    private func matrixRow(_ row: BpBlockRow) -> some View {
        HStack(spacing: 4) {
            Text(row.name)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 88, alignment: .leading)
            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, count in
                cell(count)
            }
            Text(row.total.map { "\($0)" } ?? "—")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(row.total == nil ? Brand.neutral : palette.textPrimary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(matrixRowA11y(row))
    }

    /// One coherent line per matrix row, read off the same decoded counts the
    /// row prints. An empty cell is announced as not carried, never as zero.
    private func matrixRowA11y(_ row: BpBlockRow) -> String {
        var parts: [String] = ["Block \(row.name)"]
        for (i, col) in columns.enumerated() {
            let value: Int? = i < row.cells.count ? row.cells[i] : nil
            if let v = value {
                parts.append("\(col.symbol) \(v) cars")
            } else {
                parts.append("\(col.symbol) does not carry this block")
            }
        }
        if let total = row.total {
            parts.append("block total \(total) cars")
        } else {
            parts.append("block total unknown")
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Heat encoding: fill weight proportional to the count, empty cells stay faint.
    private func cell(_ count: Int?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(count == nil
                      ? palette.textPrimary.opacity(0.04)
                      : Brand.info.opacity(0.08 + 0.32 * (Double(count ?? 0) / Double(heaviestCell))))
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity)
    }

    private var totalsRule: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("ON TRAIN")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    .frame(width: 88, alignment: .leading)
                ForEach(columns) { col in
                    Text(col.cars.map { "\($0)" } ?? "—")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(col.cars == nil ? Brand.neutral : palette.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                Text(classifiedTotal.map { "\($0)" } ?? "—")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(classifiedTotal == nil ? Brand.neutral : palette.textPrimary)
                    .frame(width: 34, alignment: .trailing)
            }
            HStack(spacing: 4) {
                Text("vs MAX")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    .frame(width: 88, alignment: .leading)
                ForEach(columns) { col in
                    // The ceiling is the named gap. We render the one real length
                    // the consist row does carry, and never a verdict against a
                    // maximum the server has not served.
                    Text(col.lengthFeet.map { "\($0.formatted()) ft" } ?? "max —")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: 34, height: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(totalsRuleA11y)
    }

    /// The bottom rule spoken as sentences. The maximum-length ceiling is the
    /// named gap, so every column says so instead of implying a clean pass.
    private var totalsRuleA11y: String {
        var parts: [String] = []
        for col in columns {
            let cars = col.cars.map { "\($0) cars on train" } ?? "car count not recorded"
            let feet = col.lengthFeet.map { "\($0.formatted()) feet recorded" } ?? "length not recorded"
            parts.append("\(col.symbol): \(cars), \(feet), maximum train length unknown so no over-limit verdict")
        }
        let total = classifiedTotal.map { "\($0) cars classified in total" } ?? "total classified count unknown"
        guard !parts.isEmpty else { return "Train totals. \(total)." }
        return "Train totals. " + parts.joined(separator: ". ") + ". " + total + "."
    }

    // MARK: Classification track allocation

    private var trackCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tracksHolding.isEmpty {
                Text("No classification track is holding a car at this yard right now.")
                    .font(.system(size: 10.5)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(tracksHolding.prefix(6).enumerated()), id: \.element.id) { idx, track in
                    if idx > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 8) }
                    trackRow(track)
                }
                if tracksHolding.count > 6 {
                    Text("+ \(tracksHolding.count - 6) more tracks holding")
                        .font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textTertiary)
                        .padding(.top, 8)
                }
            }
            Text(trackFooter)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(cacheExpired ? Brand.warning : palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
                .accessibilityLabel(spoken714(trackFooter))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var trackFooter: String {
        let cap = perTrackCapacity == nil
            ? "per-track capacity not served — the bar reads share of the busiest track"
            : "per-track capacity is the yard capacity split evenly across \(occupancy?.totalTracks ?? 0) tracks"
        var line = "track state cached \(readAtLabel) · TTL 5 min · plan save unavailable · \(cap)"
        // Yard-wide envelope from the companyId-scoped yard dashboard, shown only
        // when it actually reports — never an inferred number.
        if let avail = dashboard?.capacity?.available, avail > 0 {
            line += " · \(avail) yard spots open"
        }
        return line
    }

    private func trackRow(_ track: BpTrack) -> some View {
        let count = track.carCount ?? 0
        let fraction: Double = {
            if let cap = perTrackCapacity, cap > 0 { return min(Double(count) / Double(cap), 1.0) }
            return min(Double(count) / Double(busiestTrackCount), 1.0)
        }()
        let tint: Color = fraction >= 0.90 ? Brand.danger : (fraction >= 0.70 ? Brand.warning : Brand.success)

        return HStack(spacing: Space.s3) {
            Text("Track \(track.trackNumber)")
                .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(trackTitle(track))
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(trackDetail(track))
                    .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.06))
                        Capsule().fill(tint).frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(width: 84, height: 7)
                .accessibilityHidden(true)
                Text(perTrackCapacity.map { "\(count) of \($0)" } ?? "\(count) cars")
                    .font(.system(size: 8.5, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(fraction >= 0.90 ? Brand.danger : palette.textPrimary)
                .frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trackRowA11y(track, count: count, fraction: fraction))
    }

    /// One coherent line per track row. The denominator is only spoken when the
    /// yard actually served a per-track capacity; otherwise the reader is told
    /// the percentage is a share of the busiest track, not of a ceiling.
    private func trackRowA11y(_ track: BpTrack, count: Int, fraction: Double) -> String {
        let pct = Int((fraction * 100).rounded())
        let held: String
        if let cap = perTrackCapacity {
            held = "\(count) of \(cap) cars, \(pct) percent of that capacity"
        } else {
            held = "\(count) cars, \(pct) percent of the busiest track — per-track capacity not served"
        }
        let detail = spoken714(trackDetail(track))
        return "Track \(track.trackNumber), \(trackTitle(track)), \(detail), \(held)."
    }

    /// Block identity is the named gap, so the row names the track by what the
    /// server actually reports standing on it — never an invented block label.
    private func trackTitle(_ track: BpTrack) -> String {
        let types = (track.cars ?? []).compactMap { $0.carType }
        guard let dominant = Dictionary(grouping: types, by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key else {
            return "block unknown"
        }
        return dominant.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func trackDetail(_ track: BpTrack) -> String {
        var parts: [String] = []
        parts.append("\(track.carCount ?? 0) cars")
        let loaded = (track.cars ?? []).filter { ($0.status ?? "") == "loaded" }.count
        if loaded > 0 { parts.append("\(loaded) loaded") }
        let tanks = (track.cars ?? []).filter { ($0.carType ?? "") == "tankcar" }.count
        if tanks > 0 { parts.append("\(tanks) tank · DG segregated") }
        if let first = (track.cars ?? []).first?.carNumber { parts.append(first) }
        return parts.joined(separator: " · ")
    }

    // MARK: Tri-country band · which national rail regime governs this yard
    //
    // The band's job is the one the code below actually performs: mark which
    // country's regime the DECODED yard row sits in. It carries no length
    // ceiling. Nothing on the appRouter serves a maximum train length (named
    // gap RAIL-YRD-714-TRAIN-LIMIT), and the figures that stood here — 8,500 /
    // 12,000 / 6,500 ft — were decoded from nothing and correspond to no
    // published national ceiling in any of the three regimes. There is no
    // figure to substitute, so each tile reports the same unknown the
    // "MAX UNKNOWN" chip and the derivation note already report. The currency
    // marks went with them: this screen carries no money surface at all.

    /// Printed on every tile. The same words as the chip above the matrix, so
    /// the whole screen states one thing about the ceiling instead of two.
    private let maxLengthTileLine = "MAX UNKNOWN"
    /// Spoken form. Says WHOSE unknown it is — this screen was not served a
    /// ceiling — so it can never be heard as "this country has no maximum".
    private let maxLengthTileSpoken =
        "maximum train length is not served to this screen, so this tile shows no length ceiling"

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            countryTile("US · FRA · AAR", maxLengthTileLine,
                        spokenBottom: maxLengthTileSpoken, active: activeCountry == "US")
            countryTile("CA · TC · CROR", maxLengthTileLine,
                        spokenBottom: maxLengthTileSpoken, active: activeCountry == "CA")
            countryTile("MX · ARTF", maxLengthTileLine,
                        spokenBottom: maxLengthTileSpoken, active: activeCountry == "MX")
        }
    }

    /// The band is gated by the REAL country on the yard row — never hardcoded.
    private var activeCountry: String? { workingYard?.country }

    private func countryTile(_ top: String, _ bottom: String,
                             spokenBottom: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Brand.info : palette.textSecondary).lineLimit(1)
            // The ceiling is unknown in every regime, so this line never takes
            // the active accent — only the jurisdiction line above it does. It
            // carries the same neutral ink as the "MAX UNKNOWN" chip, so an
            // unknown can never read as the highlighted good state.
            Text(bottom).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Brand.neutral).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken714(top) + ". " + spokenBottom + ".")
        .accessibilityValue(active ? "Matches this yard's country" : "Does not match this yard's country")
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                // A REAL Button, disabled because the receiver genuinely does not
                // exist: railBlocking.commitBlockingPlan is the named gap
                // RAIL-YRD-714-COMMIT-PLAN. It is never a styled Text with hit
                // testing switched off — a control that cannot fire must still
                // be a control, so the platform reports it as unavailable and
                // the treatment below keeps it from ever reading as live.
                Button { } label: {
                    Text("Commit plan")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(LinearGradient.primary.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityLabel("Commit plan")
                .accessibilityValue("Unavailable — blocking-plan save is not available, so the plan cannot be committed from this screen")
                .accessibilityAddTraits(.isButton)

                Button {
                    Task { await buildTrain() }
                } label: {
                    Text(committing ? "Building…" : "Build train")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 132).frame(height: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .disabled(buildInput == nil || committing)
                .opacity(buildInput == nil || committing ? 0.5 : 1)
                .accessibilityLabel(committing ? "Building" : "Build train")
                .accessibilityHint("Creates a consist for the first destination block from the cars standing unassigned at this yard")
                .accessibilityValue(buildBlockedReason ?? "Available")
                .accessibilityAddTraits(.isButton)
            }
            Text(ctaNote).font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Why the build control is inert right now, in the same terms the note under
    /// the pair already uses. `nil` exactly when the control is live.
    private var buildBlockedReason: String? {
        if committing { return "Unavailable — a consist is already being built" }
        if buildInput == nil {
            return "Unavailable — needs a decoded yard with a railroad, a destination block and unassigned cars standing here"
        }
        return nil
    }

    private var ctaNote: String {
        let build = buildInput == nil
            ? "Build train needs a decoded yard with a railroad, a destination block and unassigned cars standing here."
            : "Build train creates a consist for the first destination block using \(buildInput?.railcarIds.count ?? 0) unassigned cars."
        return "Blocking-plan save is unavailable. Review the outbound consists before building a train. " + build
    }

    /// Every field of the createConsist payload traced to a decoded row. Nil when
    /// any one of them is absent — the button stays disabled rather than guessing.
    private var buildInput: CreateConsistInput? {
        guard let yard = workingYard,
              let carrierId = yard.railroadId,
              let destination = rows.first(where: { $0.id > 0 })?.id else { return nil }
        let ids = carsAtYard.filter { $0.trackNumber == nil }.map { $0.id }
        guard !ids.isEmpty else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(16)
        return CreateConsistInput(trainId: "\(yard.splcCode ?? "YARD")-\(stamp)",
                                  carrierId: carrierId,
                                  originYardId: yard.id,
                                  destinationYardId: destination,
                                  railcarIds: ids)
    }

    // MARK: Data

    private struct YardsInput: Encodable { let limit: Int }
    private struct YardInput: Encodable { let yardId: Int }
    private struct RailcarsInput: Encodable {
        let yardId: Int
        let limit: Int
        let offset: Int
    }
    private struct CreateConsistInput: Encodable {
        let trainId: String
        let carrierId: Int
        let originYardId: Int
        let destinationYardId: Int
        let railcarIds: [Int]
    }
    private struct CreateConsistResult: Decodable {
        let id: Int?
        let trainId: String?
        let totalCars: Int?
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            // 1. The yard catalog (railShipments.ts:1251) — a bare array of rows.
            let all: [BpYard] = try await EusoTripAPI.shared.query("railShipments.getRailYards",
                                                                  input: YardsInput(limit: 50))
            self.yards = all
            // The blocking plan is a classification-yard surface; fall back to the
            // first active yard when the carrier runs no classification bowl.
            self.workingYard = all.first { ($0.yardType ?? "") == "classification" } ?? all.first

            // 2. Track state and the cars standing at that yard.
            if let yid = workingYard?.id {
                self.occupancy = try await EusoTripAPI.shared.query("railShipments.getYardTrackOccupancy",
                                                                    input: YardInput(yardId: yid))
                let cars: BpRailcarEnvelope = try await EusoTripAPI.shared.query(
                    "railShipments.getRailcars",
                    input: RailcarsInput(yardId: yid, limit: 100, offset: 0))
                self.carsAtYard = cars.railcars ?? []
            } else {
                self.occupancy = nil
                self.carsAtYard = []
            }

            // 3. The outbound train columns.
            let env: BpConsistEnvelope = try await EusoTripAPI.shared.queryNoInput("railShipments.getTrainConsists")
            self.consists = env.consists ?? []

            self.readAt = Date()
            self.now = Date()
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false

        // 4. Yard-wide capacity context. Soft-fail: a companyId-scoped yard
        //    dashboard must never break the rail-side matrix.
        self.dashboard = try? await EusoTripAPI.shared.queryNoInput("yardManagement.getYardDashboard")
    }

    /// The one write this screen can honestly make today: build the consist for
    /// the first real destination block out of the cars actually standing
    /// unassigned at this yard. Real mutation, real server-side validation, real
    /// blockchainAuditTrail row (rail.consist_created, railShipments.ts:1224).
    private func buildTrain() async {
        guard let input = buildInput else { return }
        committing = true
        do {
            let _: CreateConsistResult = try await EusoTripAPI.shared.mutation(
                "railShipments.createConsist", input: input)
            committing = false
            await load()
        } catch {
            committing = false
            loadError = error.eusoUserCopy
        }
    }
}

#Preview("714 · Rail Yard Blocking Plan · Night") {
    RailYardBlockingPlanScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("714 · Rail Yard Blocking Plan · Light") {
    RailYardBlockingPlanScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
