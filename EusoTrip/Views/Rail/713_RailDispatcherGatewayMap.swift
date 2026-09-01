//
//  713_RailDispatcherGatewayMap.swift
//  EusoTrip — Rail Dispatcher · Gateway Network Map (DISPATCHER SIDE).
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/713 Rail Dispatcher Gateway Map.svg"
//  and its Dark twin. Same sections, same order, same encodings. Every value
//  below is decoded from a real procedure or derived from decoded state — no
//  mock arrays, no placeholder rows, no fabricated dwell.
//
//  ARCHETYPE: GATEWAY POSITION PLOT. The hero places each interchange gateway
//  NODE from its published coordinate; the node RADIUS is scaled by cars-on-hand
//  and the node is ringed by a
//  CONGESTION ARC whose sweep and colour encode dwell against the interchange
//  SLA. Below it, a gateway ranking where every row carries a horizontal DWELL
//  BAR against an SLA threshold tick, cars-on-hand in tabular mono, and the
//  interchange partner's SCAC. Deliberately unlike its siblings: not 693's
//  geographic slow-order polyline, not 628's yard-slot track grid, not 585's
//  live corridor pin map, not 681's single radial countdown ring.
//
//  ── WIRING MANIFEST ────────────────────────────────────────────────────────
//    railShipments.getCrossBorderInterchangePoints  EXISTS railShipments.ts:2967
//        → crossBorderRail.getInterchangePoints crossBorderRail.ts:68 — the
//          gateway catalog: id, name, countryA/B, stateProvinceA/B,
//          railroadsA[], railroadsB[], lat, lng, interchangeType, customsOffice.
//          Node POSITION and the partner SCAC both come from this row.
//    railShipments.getRailShipments                 EXISTS railShipments.ts:421
//        → the anchor shipment (getInterchangeHandoff and getServiceLineup are
//          both per-shipment; without an anchor there is nothing to key on).
//    railShipments.getInterchangeHandoff EXISTS railShipments.ts:2780
//        → cars[]{railcarNumber, interchangePointId, deliveringRoad,
//          receivingRoad, status, acceptedAt} + counts. Un-accepted cars per
//          interchangePointId ARE the cars-on-hand that scale the node radius.
//    railShipments.getRailYards                     EXISTS railShipments.ts:1512
//        → yard anchors for gateways that resolve to a yard (name/city/state).
//    railShipments.getServiceLineup EXISTS railShipments.ts:1576
//        → the next service call behind the anchor, shown in the subline.
//    railShipments.getRailcars                      EXISTS railShipments.ts:1192
//        → {railcars[], total}; yardName/yardCoordinates joined. Secondary
//          cars-on-hand source when the handoff board is empty.
//    yardManagement.getDetentionTracking            EXISTS yardManagement.ts:2083
//        → records[]{carrierName, arrivalTime, freeTimeHours, totalTimeHours,
//          detentionHours, accruedCharge, status} — the ONLY dwell clock on
//          disk. A gateway with no matching record gets a HOLLOW ring and the
//          words "dwell unreported". Never a green ring by default.
//    railShipments.notifyConsigneeAtInterchange EXISTS railShipments.ts:2650
//        (mutation) The primary CTA, wired for real. Richest fan-out in rail:
//        notificationService push + a notifications row + emitRailAtInterchange
//        broadened to the consignee room + blockchainAuditTrail eventType
//        rail.consignee_notified. Returns either
//        {sent,notificationId,channels[],errors[],consigneeId} or the honest
//        {sent:false, reason:"no_consignee_on_file", channels:[], consigneeId:null}.
//        VERIFIED against the appRouter runtime procedure manifest
//        (appRouter._def.procedures, 6,518 entries): the procedure is PRESENT.
//        The prior "0 client callers" finding was DEAD AIR — no initiating
//        surface — NOT a missing endpoint.
//        GATED: the notify asserts to a third party that cars are on hand at a
//        named gateway and writes that claim into an immutable audit row, so it
//        only fires against a gateway whose cars are recorded on the
//        interchange handoff board. A yard-name inference never authorises it.
//        RECORD CORRECTION: this procedure is NOT dead air — 695 Rail
//        At-Interchange Notification and 707 Rail Verified Receiver Gate both
//        already call it on the CARRIER side. What was missing is a
//        DISPATCHER-side, network-level initiator; 713 is that initiator.
//
//    STUB · named-gap RAIL-DSP-713-GATEWAY-LOAD
//        No procedure returns cars-on-hand + dwell-vs-SLA aggregated PER
//        interchange point. 713 composes it client-side from the reads above
//        and says so on screen when a component is missing.
//    STUB · named-gap RAIL-DSP-713-IXN-SLA-HOURS
//        The per-corridor interchange SLA hours value is not on disk. The
//        screen holds the conservative AAR 48h basis and labels it as such.
//
//    Realtime: WS_EVENTS.RAIL_AT_INTERCHANGE (websocket-events.ts:402) on
//        WS_CHANNELS.RAIL_DISPATCH (websocket-events.ts:623) is what re-ticks
//        this canvas; notifyConsigneeAtInterchange broadcasts on it.
//    RBAC: railReadProcedure (railShipments.ts:94) · RAIL_DISPATCHER (trpc.ts:31); assertOwnsRailShipment
//        gates the notify.
//    OFFLINE: READ_CACHED(60s) — canvas + ranking render from the last good
//        tick behind a visible staleness line. The notify action is
//        ONLINE_ONLY: it fans out to a third party and writes an immutable
//        audit row, so it is NEVER queued — on failure it reports and stops.
//    NAV (carrier family): HOME(current) · SHIPMENTS · [orb] · COMPLIANCE · ME.
//

import SwiftUI

// MARK: - Screen

struct RailDispatcherGatewayMapScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDispatcherGatewayMapBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Flexible decode helpers (the wire mixes DECIMAL strings and numbers)

private func flex713Double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
    return nil
}

private func flex713Int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
    if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) }
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
    return nil
}

private func parse713Date(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: s) { return d }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: s)
}

/// "41h48" — the dwell format the wireframe uses. Never rounded up past the SLA.
private func hhmm713(_ hours: Double) -> String {
    let h = Int(hours)
    let m = Int(((hours - Double(h)) * 60).rounded())
    return String(format: "%dh%02d", h, min(m, 59))
}

// MARK: - Speech helpers (a11y only — the printed copy is never changed)

/// A middle-dot separated line, spoken. VoiceOver reads "·" as "middle dot",
/// which buries the facts; the comma form carries exactly the same content.
private func spoken713(_ s: String) -> String {
    s.replacingOccurrences(of: " · ", with: ", ")
}

/// The delivering → receiving mark, spoken. Same two roads, same direction.
private func spokenRoads713(_ s: String) -> String {
    s.replacingOccurrences(of: "→", with: "to")
}

// MARK: - Data shapes

/// `railShipments.getCrossBorderInterchangePoints` (railShipments.ts:2967) → RailInterchangePoint.
private struct InterchangePoint713: Decodable, Identifiable {
    let id: String
    let name: String
    let countryA: String?
    let countryB: String?
    let stateProvinceA: String?
    let stateProvinceB: String?
    let railroadsA: [String]?
    let railroadsB: [String]?
    let lat: Double?
    let lng: Double?
    let interchangeType: String?
    let customsOffice: String?
    let hasIntermodal: Bool?
    let hazmatAllowed: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, countryA, countryB, stateProvinceA, stateProvinceB
        case railroadsA, railroadsB, lat, lng, interchangeType, customsOffice
        case hasIntermodal, hazmatAllowed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name            = (try? c.decode(String.self, forKey: .name)) ?? "Interchange"
        countryA        = try? c.decodeIfPresent(String.self, forKey: .countryA)
        countryB        = try? c.decodeIfPresent(String.self, forKey: .countryB)
        stateProvinceA  = try? c.decodeIfPresent(String.self, forKey: .stateProvinceA)
        stateProvinceB  = try? c.decodeIfPresent(String.self, forKey: .stateProvinceB)
        railroadsA      = try? c.decodeIfPresent([String].self, forKey: .railroadsA)
        railroadsB      = try? c.decodeIfPresent([String].self, forKey: .railroadsB)
        lat             = flex713Double(c, .lat)
        lng             = flex713Double(c, .lng)
        interchangeType = try? c.decodeIfPresent(String.self, forKey: .interchangeType)
        customsOffice   = try? c.decodeIfPresent(String.self, forKey: .customsOffice)
        hasIntermodal   = try? c.decodeIfPresent(Bool.self, forKey: .hasIntermodal)
        hazmatAllowed   = try? c.decodeIfPresent(Bool.self, forKey: .hazmatAllowed)
    }

    /// The handoff board keys cars by a NUMERIC interchangePointId while the
    /// catalog id is "INT-009". The trailing digits are the join. Derived from
    /// decoded text — never invented.
    var numericId: Int? { Int(id.filter(\.isNumber)) }

    /// "Laredo" from "Laredo/Nuevo Laredo" — the token used to match a yard or
    /// a detention facility name back to this gateway.
    var placeToken: String {
        let head = name.split(whereSeparator: { $0 == "/" || $0 == "," }).first.map(String.init) ?? name
        return head.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Delivering → receiving marks, straight off railroadsA/railroadsB.
    var scacPair: String {
        let a = railroadsA?.first
        let b = railroadsB?.first
        switch (a, b) {
        case let (x?, y?): return "\(x) → \(y)"
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return "roads unreported"
        }
    }

    /// The far side of the gateway — the country the consignee sits in, and the
    /// value notifyConsigneeAtInterchange localizes on.
    var farCountry: String { (countryB ?? countryA ?? "US").uppercased() }
}

/// `railShipments.getRailShipments` (railShipments.ts:421) — only the fields the anchor needs.
private struct RailShipmentRow713: Decodable {
    let id: String
    let railRef: String?
    let origin: String?
    let destination: String?
    let status: String?
    var numericId: Int? { Int(id.filter(\.isNumber)) }
}

/// `railShipments.getInterchangeHandoff` (railShipments.ts:2780).
private struct HandoffEnvelope713: Decodable {
    let shipmentId: Int?
    let cars: [HandoffCar713]?
    let counts: [String: Int]?
}

private struct HandoffCar713: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let interchangePointId: Int?
    let deliveringRoad: String?
    let receivingRoad: String?
    let status: String?
    let exceptionReason: String?
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, railcarNumber, interchangePointId, deliveringRoad
        case receivingRoad, status, exceptionReason, acceptedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = flex713Int(c, .id) ?? 0
        railcarNumber      = try? c.decodeIfPresent(String.self, forKey: .railcarNumber)
        interchangePointId = flex713Int(c, .interchangePointId)
        deliveringRoad     = try? c.decodeIfPresent(String.self, forKey: .deliveringRoad)
        receivingRoad      = try? c.decodeIfPresent(String.self, forKey: .receivingRoad)
        status             = try? c.decodeIfPresent(String.self, forKey: .status)
        exceptionReason    = try? c.decodeIfPresent(String.self, forKey: .exceptionReason)
        acceptedAt         = try? c.decodeIfPresent(String.self, forKey: .acceptedAt)
    }

    /// A car still on hand at the gateway: custody has not transferred.
    var onHand: Bool { acceptedAt == nil && (status ?? "").lowercased() != "accepted" }
}

/// `railShipments.getRailYards` (railShipments.ts:1512) — a rail_yards row.
private struct YardRow713: Decodable, Identifiable {
    let id: Int
    let name: String?
    let city: String?
    let state: String?
    let country: String?
    let splcCode: String?

    enum CodingKeys: String, CodingKey { case id, name, city, state, country, splcCode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = flex713Int(c, .id) ?? 0
        name     = try? c.decodeIfPresent(String.self, forKey: .name)
        city     = try? c.decodeIfPresent(String.self, forKey: .city)
        state    = try? c.decodeIfPresent(String.self, forKey: .state)
        country  = try? c.decodeIfPresent(String.self, forKey: .country)
        splcCode = try? c.decodeIfPresent(String.self, forKey: .splcCode)
    }

    var haystack: String {
        [name, city, state].compactMap { $0 }.joined(separator: " ").lowercased()
    }
}

/// `railShipments.getRailcars` (railShipments.ts:1192).
private struct RailcarEnvelope713: Decodable {
    let railcars: [Railcar713]?
    let total: Int?
}

private struct Railcar713: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let status: String?
    let currentYardId: Int?
    let yardName: String?

    enum CodingKeys: String, CodingKey { case id, railcarNumber, status, currentYardId, yardName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = flex713Int(c, .id) ?? 0
        railcarNumber = try? c.decodeIfPresent(String.self, forKey: .railcarNumber)
        status        = try? c.decodeIfPresent(String.self, forKey: .status)
        currentYardId = flex713Int(c, .currentYardId)
        yardName      = try? c.decodeIfPresent(String.self, forKey: .yardName)
    }
}

/// `yardManagement.getDetentionTracking` (:2083) — the only dwell clock on disk.
private struct DetentionEnvelope713: Decodable {
    let records: [DetentionRecord713]?
    let summary: DetentionSummary713?
}

private struct DetentionSummary713: Decodable {
    let activeDetentions: Int?
    let totalAccruedCharges: Double?
    let avgDetentionHours: Double?
    let criticalCount: Int?

    enum CodingKeys: String, CodingKey {
        case activeDetentions, totalAccruedCharges, avgDetentionHours, criticalCount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeDetentions    = flex713Int(c, .activeDetentions)
        totalAccruedCharges = flex713Double(c, .totalAccruedCharges)
        avgDetentionHours   = flex713Double(c, .avgDetentionHours)
        criticalCount       = flex713Int(c, .criticalCount)
    }
}

private struct DetentionRecord713: Decodable, Identifiable {
    let id: String
    let trailerNumber: String?
    let carrierName: String?
    let arrivalTime: String?
    let freeTimeHours: Double?
    let totalTimeHours: Double?
    let detentionHours: Double?
    let accruedCharge: Double?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, trailerNumber, carrierName, arrivalTime
        case freeTimeHours, totalTimeHours, detentionHours, accruedCharge, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        trailerNumber  = try? c.decodeIfPresent(String.self, forKey: .trailerNumber)
        carrierName    = try? c.decodeIfPresent(String.self, forKey: .carrierName)
        arrivalTime    = try? c.decodeIfPresent(String.self, forKey: .arrivalTime)
        freeTimeHours  = flex713Double(c, .freeTimeHours)
        totalTimeHours = flex713Double(c, .totalTimeHours)
        detentionHours = flex713Double(c, .detentionHours)
        accruedCharge  = flex713Double(c, .accruedCharge)
        status         = try? c.decodeIfPresent(String.self, forKey: .status)
    }

    var haystack: String {
        [carrierName, trailerNumber].compactMap { $0 }.joined(separator: " ").lowercased()
    }

    /// Elapsed dwell. The server's own totalTimeHours when it carried one,
    /// else the same derivation getDetentionTracking uses internally —
    /// now minus the real geofence arrival. nil when neither exists.
    var elapsedHours: Double? {
        if let t = totalTimeHours { return t }
        guard let at = parse713Date(arrivalTime) else { return nil }
        let h = Date().timeIntervalSince(at) / 3600
        return h >= 0 ? h : nil
    }
}

/// `railShipments.getServiceLineup` (railShipments.ts:1576) — only the header fields.
private struct ServiceLineup713: Decodable {
    let trainSymbol: String?
    let carCount: Int?
    let status: String?
    let nextCallLabel: String?
    let nextCallYardName: String?

    enum CodingKeys: String, CodingKey {
        case trainSymbol, carCount, status, nextCallLabel, nextCallYardName
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trainSymbol      = try? c.decodeIfPresent(String.self, forKey: .trainSymbol)
        carCount         = flex713Int(c, .carCount)
        status           = try? c.decodeIfPresent(String.self, forKey: .status)
        nextCallLabel    = try? c.decodeIfPresent(String.self, forKey: .nextCallLabel)
        nextCallYardName = try? c.decodeIfPresent(String.self, forKey: .nextCallYardName)
    }
}

/// `railShipments.notifyConsigneeAtInterchange` (railShipments.ts:2650) — BOTH documented returns.
private struct NotifyResult713: Decodable {
    let sent: Bool?
    let reason: String?
    let notificationId: Int?
    let channels: [String]?
    let errors: [String]?
    let consigneeId: Int?

    enum CodingKeys: String, CodingKey {
        case sent, reason, notificationId, channels, errors, consigneeId
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sent           = try? c.decodeIfPresent(Bool.self, forKey: .sent)
        reason         = try? c.decodeIfPresent(String.self, forKey: .reason)
        notificationId = flex713Int(c, .notificationId)
        channels       = try? c.decodeIfPresent([String].self, forKey: .channels)
        errors         = try? c.decodeIfPresent([String].self, forKey: .errors)
        consigneeId    = flex713Int(c, .consigneeId)
    }
}

// MARK: - Assembled gateway (composed only from decoded rows)

private enum DwellState713 { case onTime, atRisk, breached, unreported }

/// Where a gateway's cars-on-hand figure came from. The handoff board is a
/// custody record keyed to THIS interchange point by its own numeric id; the
/// yard-name match is only an inference from a place token and is never strong
/// enough to assert an arrival to a counter-party or to write one into an
/// immutable audit row.
private enum CarsBasis713: Equatable { case handoffBoard, yardNameMatch, unreported }

private struct Gateway713: Identifiable {
    let id: String
    let name: String
    let scacPair: String
    let lat: Double?
    let lng: Double?
    let roads: Set<String>
    let farCountry: String
    /// nil = no source reported cars for this gateway (never rendered as zero).
    let carsOnHand: Int?
    /// How `carsOnHand` was established. Gates the outbound notify: only the
    /// handoff board is a custody record for this interchange point.
    let carsBasis: CarsBasis713
    /// nil = no detention record matched this gateway (ring drawn hollow).
    let dwellHours: Double?
    let slaHours: Double
    let accruedCharge: Double?
    let detentionFacility: String?

    var dwellFraction: Double? {
        guard let d = dwellHours, slaHours > 0 else { return nil }
        return min(d / slaHours, 1.0)
    }

    var state: DwellState713 {
        guard let d = dwellHours else { return .unreported }
        if d >= slaHours { return .breached }
        if d >= slaHours * 0.80 { return .atRisk }
        return .onTime
    }

    var dwellLabel: String {
        guard let d = dwellHours else { return "dwell unreported" }
        return "\(hhmm713(d)) / \(Int(slaHours))h"
    }

    var carsLabel: String {
        guard let c = carsOnHand else { return "cars unreported" }
        return "\(c) cars"
    }
}

// MARK: - Body

private struct RailDispatcherGatewayMapBody: View {
    @Environment(\.palette) private var palette

    // Country tiles gate the gateway SCOPE — a real input to
    // getCrossBorderInterchangePoints, not decoration.
    private enum Regime713: String, CaseIterable {
        case us = "US", ca = "CA", mx = "MX"
        var top: String {
            switch self {
            case .us: return "US · CBP / STB"
            case .ca: return "CA · CBSA / TC"
            case .mx: return "MX · SAT / ARTF"
            }
        }
        var bottom: String {
            switch self {
            case .us: return "AAR 48h · USD"
            case .ca: return "CN–CPKC · CAD"
            case .mx: return "FXE · MXN"
            }
        }
    }

    @State private var regime: Regime713 = .us
    @State private var points: [InterchangePoint713] = []
    @State private var anchor: RailShipmentRow713? = nil
    @State private var handoff: HandoffEnvelope713? = nil
    @State private var yards: [YardRow713] = []
    @State private var railcars: [Railcar713] = []
    @State private var detention: DetentionEnvelope713? = nil
    @State private var lineup: ServiceLineup713? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    /// The READ_CACHED tick. `nil` until the first successful read.
    @State private var lastGoodTick: Date? = nil
    @State private var notifying = false
    @State private var notifyNotice: (text: String, ok: Bool)? = nil

    /// STUB · named-gap RAIL-DSP-713-IXN-SLA-HOURS — no per-corridor SLA value
    /// exists on disk, so the conservative AAR 48h basis is held and labelled.
    private let slaHours: Double = 48.0
    /// READ_CACHED(60s): past this the tick is stale and the ONLINE_ONLY notify
    /// is disabled rather than fired against a network we can no longer see.
    private let cacheTTL: TimeInterval = 60

    // MARK: Derived

    private var staleSeconds: TimeInterval? {
        lastGoodTick.map { Date().timeIntervalSince($0) }
    }
    private var isStale: Bool { (staleSeconds ?? .greatestFiniteMagnitude) > cacheTTL }

    private var stalenessLine: String {
        guard let s = staleSeconds else { return "READ_CACHED(60s) · no tick yet · nothing cached to show" }
        let mins = Int(s / 60)
        let age = mins >= 1 ? "\(mins)m" : "\(Int(s))s"
        return "READ_CACHED(60s) · last at-interchange tick \(age) ago · showing cached network"
    }

    /// Un-accepted handoff cars grouped by the numeric interchangePointId.
    private var carsByPoint: [Int: Int] {
        var m: [Int: Int] = [:]
        for car in (handoff?.cars ?? []) where car.onHand {
            guard let pid = car.interchangePointId else { continue }
            m[pid, default: 0] += 1
        }
        return m
    }

    /// Secondary cars-on-hand: railcars whose joined yard name carries the
    /// gateway's place token. Only used when the handoff board has nothing.
    private func railcarsAt(_ token: String) -> Int? {
        guard !railcars.isEmpty, !token.isEmpty else { return nil }
        let yardIds = Set(yards.filter { $0.haystack.contains(token) }.map(\.id))
        let n = railcars.filter { car in
            if let y = car.currentYardId, yardIds.contains(y) { return true }
            return (car.yardName ?? "").lowercased().contains(token)
        }.count
        return n > 0 ? n : nil
    }

    /// The one detention record that belongs to this gateway, if any. No match
    /// means no dwell — the ring stays hollow and the row says so.
    private func detentionAt(_ token: String) -> DetentionRecord713? {
        guard !token.isEmpty else { return nil }
        return (detention?.records ?? [])
            .filter { $0.haystack.contains(token) }
            .max { ($0.elapsedHours ?? 0) < ($1.elapsedHours ?? 0) }
    }

    private var gateways: [Gateway713] {
        points.map { p in
            let token = p.placeToken
            // The handoff board is the custody record — it keys cars to this
            // interchange point by its own id. The yard-name match is only an
            // inference from a place token. Which one answered is carried
            // forward so the outbound notify can refuse to speak for the weaker
            // source rather than silently treating the two as the same fact.
            let boardCars = p.numericId.flatMap { carsByPoint[$0] }
            let cars = boardCars ?? railcarsAt(token)
            let basis: CarsBasis713 = boardCars != nil
                ? .handoffBoard
                : (cars != nil ? .yardNameMatch : .unreported)
            let det = detentionAt(token)
            return Gateway713(
                id: p.id,
                name: p.name,
                scacPair: p.scacPair,
                lat: p.lat,
                lng: p.lng,
                roads: Set((p.railroadsA ?? []) + (p.railroadsB ?? [])),
                farCountry: p.farCountry,
                carsOnHand: cars,
                carsBasis: basis,
                dwellHours: det?.elapsedHours,
                slaHours: slaHours,
                accruedCharge: det?.accruedCharge,
                detentionFacility: det?.carrierName)
        }
    }

    /// Ranked worst-first: a breached gateway outranks an at-risk one, and a
    /// gateway with no dwell reading sorts last (it cannot be ranked on a clock
    /// that does not exist).
    private var ranked: [Gateway713] {
        gateways.sorted { a, b in
            switch (a.dwellHours, b.dwellHours) {
            case let (x?, y?):
                if x != y { return x > y }
                return (a.carsOnHand ?? 0) > (b.carsOnHand ?? 0)
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.carsOnHand ?? 0) > (b.carsOnHand ?? 0)
            }
        }
    }

    /// The gateway the notify CTA may act on. The notify tells a third party
    /// that cars are on hand at this gateway and writes that claim into an
    /// immutable audit row, so the target must be a gateway whose cars are
    /// recorded on the interchange HANDOFF BOARD — the one source that keys
    /// cars to this interchange point rather than inferring them from a yard
    /// name. There is deliberately NO fallback: a gateway with unknown cars,
    /// zero cars, or cars inferred only from a name match is not a notify
    /// target, and the control reports that instead of quietly picking one.
    private var focusGateway: Gateway713? {
        ranked.first { $0.carsBasis == .handoffBoard && ($0.carsOnHand ?? 0) > 0 }
    }

    private var totalCars: Int? {
        let vals = gateways.compactMap(\.carsOnHand)
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }

    private var subline: String {
        var bits: [String] = []
        bits.append(gateways.count == 1 ? "1 interchange gateway" : "\(gateways.count) interchange gateways")
        bits.append(totalCars.map { "\($0) cars on hand" } ?? "cars unreported")
        bits.append("dwell vs AAR \(Int(slaHours))h")
        if let call = lineup?.nextCallYardName ?? lineup?.nextCallLabel { bits.append("next call \(call)") }
        return bits.joined(separator: " · ")
    }

    private func color(_ s: DwellState713) -> Color {
        switch s {
        case .onTime:     return Brand.success
        case .atRisk:     return Brand.warning
        case .breached:   return Brand.danger
        case .unreported: return palette.textTertiary
        }
    }

    private func pillText(_ s: DwellState713) -> String {
        switch s {
        case .onTime:     return "ON TIME"
        case .atRisk:     return "AT RISK"
        case .breached:   return "BREACHED"
        case .unreported: return "NO CLOCK"
        }
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline().accessibilityHidden(true)

                if loading && points.isEmpty {
                    LifecycleCard {
                        Text("Loading the gateway network…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading the gateway network")
                } else if let err = loadError, points.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("The gateway network could not be read. \(err)")
                } else if gateways.isEmpty {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No gateways in \(regime.rawValue)")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("No interchange points are available for this country, so the network cannot be displayed.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No gateways in \(regime.rawValue). No interchange points are available for this country, so the network cannot be displayed.")
                } else {
                    networkHero
                    if let n = notifyNotice { noticeCard(n) }
                    sectionLabel("GATEWAY RANKING · DWELL vs SLA",
                                 trailing: "\(gateways.count) gateways · top \(min(4, ranked.count))")
                    rankingCard
                    triCountryBand
                    onlineOnlyNote
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                .accessibilityHidden(true)
            Text("RAIL DISPATCHER · GATEWAY NETWORK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: 0)
            Text(anchor?.railRef ?? "no anchor")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).monospaced()
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rail dispatcher, gateway network. Anchor \(anchor?.railRef ?? "no anchor").")
        .accessibilityAddTraits(.isHeader)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Gateway network")
                    .font(.system(size: 34, weight: .bold)).kerning(-0.6)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // A real control rather than a glyph that only looks like one.
                // No overflow procedure is wired to this screen, so it ships as
                // a disabled Button, visibly dimmed, at the 44pt touch floor.
                Button { } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .opacity(0.35)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityLabel("More gateway actions")
                .accessibilityValue("Unavailable — no overflow action is wired to this screen")
                .accessibilityAddTraits(.isButton)
            }
            Text(subline)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(spoken713(subline))
        }
    }

    // MARK: HERO — gateway position evidence
    //
    // Node POSITION comes from the decoded lat/lng of the interchange point,
    // normalised into the canvas; node RADIUS is scaled by cars-on-hand; the
    // ring arc is dwell against the SLA. Railroad membership is metadata, not
    // route geometry: no nearest-neighbour chord or inferred track is drawn.

    private var networkHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NODE = CARS ON HAND · RING = DWELL vs SLA · POSITION = CATALOG")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(Brand.info)
                Spacer(minLength: 8)
                Text(cacheChipText)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(isStale ? Brand.danger : Brand.warning)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill((isStale ? Brand.danger : Brand.warning).opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 38)
            .background(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Plot key. Node size is cars on hand, ring is dwell against the interchange basis, position is the published catalog coordinate. \(cacheChipA11y).")

            // A map has no meaning to VoiceOver on its own, so the canvas is one
            // element carrying a text alternative read off the same decoded
            // values it draws. Nothing is described that is not on screen.
            networkCanvas
                .frame(height: 206)
                .padding(.horizontal, 14).padding(.top, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gateway position plot")
                .accessibilityValue(canvasTextEquivalent)

            Divider().overlay(palette.borderFaint).padding(.horizontal, 14).padding(.top, 4)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                legendDot(Brand.success, "on time")
                legendDot(Brand.warning, "at risk").padding(.leading, 18)
                legendDot(Brand.danger, "breached").padding(.leading, 18)
                Spacer(minLength: 6)
                Text("\(gateways.count) nodes · no track geometry")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 14).padding(.top, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ring colour key: on time, at risk, breached. \(gateways.count) nodes, no track geometry.")

            Text(stalenessLine)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(isStale ? Brand.danger : Brand.warning)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14)
                .accessibilityLabel(spoken713(stalenessLine))
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var cacheChipText: String {
        guard let s = staleSeconds else { return "NO TICK" }
        let mins = Int(s / 60)
        return mins >= 1 ? "CACHED \(mins)m" : "CACHED \(Int(s))s"
    }

    /// The cache chip spoken as words rather than as an abbreviation.
    private var cacheChipA11y: String {
        guard let s = staleSeconds else { return "No tick has been read yet" }
        let mins = Int(s / 60)
        if mins >= 1 {
            let unit = mins == 1 ? "minute" : "minutes"
            return "Cached \(mins) \(unit) ago"
        }
        let secs = Int(s)
        let unit = secs == 1 ? "second" : "seconds"
        return "Cached \(secs) \(unit) ago"
    }

    /// The textual equivalent of the position plot, for VoiceOver and for any
    /// reader who cannot use the canvas. Every clause is read off the same
    /// decoded values the canvas draws: a gateway with no reading is announced
    /// as unread, never as zero, never as on time.
    private var canvasTextEquivalent: String {
        let all = gateways
        guard !all.isEmpty else { return "No gateway nodes are plotted." }
        var lines: [String] = []
        let located = all.filter { $0.lat != nil && $0.lng != nil }.count
        let nodeWord = all.count == 1 ? "node" : "nodes"
        var head = "\(all.count) gateway \(nodeWord) plotted"
        if located == all.count {
            head += ", all placed from published catalog coordinates"
        } else {
            head += ", \(located) placed from published catalog coordinates and \(all.count - located) with no coordinate, laid out along the bottom edge"
        }
        head += ". No track geometry is drawn between nodes"
        lines.append(head)
        for g in ranked.prefix(6) {
            let roads = spokenRoads713(g.scacPair)
            let verdict = pillText(g.state).lowercased()
            lines.append("\(g.name), \(roads), \(g.carsLabel), \(g.dwellLabel), \(verdict)")
        }
        let rest = ranked.count - 6
        if rest > 0 {
            lines.append(rest == 1 ? "1 further node is not read out" : "\(rest) further nodes are not read out")
        }
        return lines.joined(separator: ". ") + "."
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().strokeBorder(c, lineWidth: 2.4).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(label).font(.system(size: 9)).foregroundStyle(palette.textSecondary)
        }
    }

    /// Node radius from cars-on-hand. A gateway with NO reported cars gets the
    /// floor radius and a hollow body — it is never inflated to fake load.
    private func radius(for g: Gateway713) -> CGFloat {
        guard let c = g.carsOnHand, c > 0 else { return 7 }
        let maxCars = max(gateways.compactMap(\.carsOnHand).max() ?? c, 1)
        let t = Double(c) / Double(maxCars)
        return 7 + CGFloat(t) * 8
    }

    private var networkCanvas: some View {
        GeometryReader { geo in
            let g = gateways
            let pts = normalisedPoints(in: geo.size)
            ZStack {
                // Points only. A shared railroad mark does not prove a physical
                // edge between two gateways, so the plot never manufactures one.
                ForEach(Array(g.enumerated()), id: \.element.id) { pair in
                    if let c = pts[pair.offset] { node(pair.element).position(c) }
                }
            }
        }
    }

    /// lat/lng normalised into the canvas. Gateways with no coordinate are laid
    /// out on the bottom rail rather than dropped — an unlocated gateway still
    /// carries cars.
    private func normalisedPoints(in size: CGSize) -> [Int: CGPoint] {
        let g = gateways
        let pad: CGFloat = 26
        let located = g.enumerated().filter { $0.element.lat != nil && $0.element.lng != nil }
        var out: [Int: CGPoint] = [:]
        if !located.isEmpty {
            let lats = located.map { $0.element.lat! }
            let lngs = located.map { $0.element.lng! }
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLng = lngs.min()!, maxLng = lngs.max()!
            let dLat = max(maxLat - minLat, 0.0001)
            let dLng = max(maxLng - minLng, 0.0001)
            for (i, gw) in located {
                let x = pad + CGFloat((gw.lng! - minLng) / dLng) * (size.width - pad * 2)
                // Latitude increases north; the canvas y increases down.
                let y = pad + CGFloat((maxLat - gw.lat!) / dLat) * (size.height - pad * 2 - 12)
                out[i] = CGPoint(x: x, y: y)
            }
        }
        let unlocated = g.indices.filter { out[$0] == nil }
        for (k, i) in unlocated.enumerated() {
            let step = size.width / CGFloat(max(unlocated.count, 1) + 1)
            out[i] = CGPoint(x: step * CGFloat(k + 1), y: size.height - 14)
        }
        return out
    }

    private func node(_ g: Gateway713) -> some View {
        let r = radius(for: g)
        let ringR = r + 5
        let c = color(g.state)
        return VStack(spacing: 3) {
            ZStack {
                Circle().stroke(palette.textPrimary.opacity(0.10), lineWidth: 3)
                    .frame(width: ringR * 2, height: ringR * 2)
                if let f = g.dwellFraction {
                    Circle().trim(from: 0, to: CGFloat(f))
                        .stroke(c, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: ringR * 2, height: ringR * 2)
                }
                Circle().fill(palette.bgCard).frame(width: r * 2, height: r * 2)
                Circle().fill(c.opacity(0.16)).frame(width: r * 2, height: r * 2)
                Circle().strokeBorder(c, lineWidth: 1.4).frame(width: r * 2, height: r * 2)
                if let cars = g.carsOnHand {
                    Text("\(cars)")
                        .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                        .monospacedDigit().foregroundStyle(c)
                }
            }
            Text(g.name.split(separator: "/").first.map(String.init)?.uppercased() ?? g.name.uppercased())
                .font(.system(size: 7, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(palette.bgCard))
        }
    }

    // MARK: Ranking list — dwell bar against the SLA tick

    private var rankingCard: some View {
        VStack(spacing: 0) {
            let rows = Array(ranked.prefix(4))
            ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                rankingRow(pair.element)
                if pair.offset < rows.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 12)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func rankingRow(_ g: Gateway713) -> some View {
        let c = color(g.state)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(g.scacPair)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                // Pill sits in its own column so it can never collide with the
                // right-hand tabular figures.
                Text(pillText(g.state))
                    .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(c)
                    .padding(.horizontal, 9).frame(height: 18)
                    .background(Capsule().fill(c.opacity(0.14)))
                    .fixedSize()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(g.carsLabel)
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(g.dwellLabel)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit().foregroundStyle(c)
                }
                .fixedSize()
            }
            dwellBar(g).padding(.top, 10).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rankingRowA11y(g))
    }

    /// One coherent line per ranking row, spoken from the same decoded values
    /// the row prints. A gateway with no dwell record is never given a verdict.
    private func rankingRowA11y(_ g: Gateway713) -> String {
        let roads = spokenRoads713(g.scacPair)
        let head = "\(g.name), \(roads), \(g.carsLabel)"
        if case .unreported = g.state {
            return head + ", no dwell clock on file, so no status is claimed."
        }
        let basis = Int(g.slaHours)
        let verdict = pillText(g.state).lowercased()
        return head + ", \(g.dwellLabel) against the \(basis) hour basis, \(verdict)."
    }

    /// Bar scale runs to 56h so a breach past the 48h SLA tick is visible as
    /// overrun rather than a bar that simply pins at full.
    private func dwellBar(_ g: Gateway713) -> some View {
        let span = 56.0
        let c = color(g.state)
        return GeometryReader { geo in
            let w = geo.size.width
            let filled: CGFloat? = g.dwellHours.map { CGFloat(min($0 / span, 1.0)) * w }
            let tick = CGFloat(g.slaHours / span) * w
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textPrimary.opacity(0.10)).frame(height: 8)
                if let filled, filled > 0 {
                    Capsule().fill(c).frame(width: filled, height: 8)
                } else if g.dwellHours == nil {
                    // No detention record matched this gateway. An empty lane
                    // would read as zero dwell — the best possible reading —
                    // so the lane is dashed instead, carrying the same "no
                    // reading" mark the pill and the figures already carry.
                    Capsule()
                        .strokeBorder(palette.textTertiary,
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 8)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.textTertiary)
                    .frame(width: 2, height: 14)
                    .offset(x: tick - 1)
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }

    // MARK: Tri-country band — gates the gateway SCOPE and the SLA basis

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            ForEach(Regime713.allCases, id: \.self) { r in
                regimeButton(r)
            }
        }
    }

    private func regimeButton(_ target: Regime713) -> some View {
        let selected = target == regime
        return Button {
            regime = target
            Task { await load() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.top)
                    .font(.system(size: 8, weight: .heavy))
                    .kerning(0.3)
                Text(target.bottom)
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(selected ? Brand.info : palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(selected ? Brand.blue.opacity(0.12) : palette.bgCardSoft)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.clear : palette.borderSoft)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken713(target.top) + ". " + spoken713(target.bottom) + ".")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Re-reads the gateway network scoped to \(target.rawValue)")
        .accessibilityAddTraits(.isButton)
    }

    private var onlineOnlyNote: some View {
        Text("ONLINE ONLY · notify fans out to the consignee · never queued")
            .font(.system(size: 8.5, weight: .bold, design: .monospaced)).kerning(0.3)
            .foregroundStyle(palette.textTertiary)
            .accessibilityLabel("Online only. Notify fans out to the consignee. Never queued.")
    }

    // MARK: CTA pair

    /// notifyConsigneeAtInterchange is ONLINE_ONLY. It pushes to a third party
    /// and writes an immutable audit row, so a queued replay could notify the
    /// same consignee twice for a car that has since moved. On failure we
    /// report and stop — we never retain it for later.
    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                Button {
                    Task { await notifyConsignee() }
                } label: {
                    HStack(spacing: 8) {
                        if notifying { ProgressView().controlSize(.small).tint(.white) }
                        Text(notifying ? "Notifying…" : "Notify consignee")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
                    .opacity(notifyEnabled ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!notifyEnabled)
                .accessibilityLabel(notifying ? "Notifying" : "Notify consignee")
                .accessibilityHint("Sends the at-interchange notification to the consignee on the waybill. Online only, so it is never queued.")
                .accessibilityValue(notifyBlockedReason ?? "Available")
                .accessibilityAddTraits(.isButton)

                Button {
                    notifyNotice = handoffBoardNotice
                } label: {
                    Text("Handoff board")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 148)
                        .frame(minHeight: 48)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Handoff board")
                .accessibilityHint("Shows the per-car handoff counts recorded against the anchor shipment")
                .accessibilityAddTraits(.isButton)
            }
            Text(notifyIntentNote)
                .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(spoken713(notifyIntentNote))
        }
    }

    /// What the notify will actually put in front of the consignee and into the
    /// immutable audit row, stated BEFORE it is sent. When it cannot be sent,
    /// the same named reason the control itself carries.
    private var notifyIntentNote: String {
        if let blocked = notifyBlockedReason { return blocked }
        guard let g = focusGateway else {
            return "No gateway currently qualifies as a notify target."
        }
        let cars = g.carsOnHand.map { "\($0) cars" } ?? "cars"
        let head = "Notify will tell the consignee that \(cars) are on hand at \(g.name), recorded on the interchange handoff board"
        if g.dwellHours == nil {
            return head + ". No interchange free-time figure is included — no detention record matched this gateway, so none is claimed. The send writes an immutable audit row."
        }
        return head + ", with \(g.dwellLabel) against the \(Int(g.slaHours)) hour basis. The send writes an immutable audit row."
    }

    /// Why the notify control is inert right now, in the same terms the screen
    /// already uses. `nil` exactly when the control is live — the single source
    /// of truth behind both `.disabled` and the spoken value.
    private var notifyBlockedReason: String? {
        if notifying { return "Unavailable — a notification is already being sent" }
        if isStale { return "Unavailable — the cached network tick is older than 60 seconds and this action is online only" }
        if anchor?.numericId == nil { return "Unavailable — no anchor shipment is on file to notify against" }
        if focusGateway == nil {
            // The send asserts an arrival to the consignee and writes that
            // assertion into an immutable audit row. With no handoff-board
            // record there is no arrival to report, so the control stays inert
            // and names the record that has to exist first.
            if gateways.contains(where: { $0.carsBasis == .yardNameMatch }) {
                return "Unavailable — cars near these gateways are matched only by yard name, not recorded against an interchange point on the handoff board, so there is no arrival to report to a consignee. Record the 322 handoff for the arriving cars first."
            }
            return "Unavailable — the interchange handoff board records no cars on hand at any gateway, so there is no arrival to report to a consignee. Record the 322 handoff for the arriving cars first."
        }
        return nil
    }

    private var notifyEnabled: Bool { notifyBlockedReason == nil }

    private var handoffBoardNotice: (text: String, ok: Bool) {
        guard let counts = handoff?.counts, !counts.isEmpty else {
            return ("No 322 handoff rows on the anchor shipment, so there is no per-car board to open.", false)
        }
        let line = counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: " · ")
        return ("Handoff board: \(line).", true)
    }

    private func noticeCard(_ n: (text: String, ok: Bool)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: n.ok ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(n.ok ? Brand.success : Brand.warning)
                .accessibilityHidden(true)
            Text(n.text).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background((n.ok ? Brand.success : Brand.warning).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder((n.ok ? Brand.success : Brand.warning).opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(n.text)
    }

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(trailing).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken713(title) + ". " + spoken713(trailing) + ".")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Data

    private struct CountryInput713: Encodable { let country: String }
    private struct ShipmentsStatusInput713: Encodable { let status: String; let limit: Int }
    private struct ShipmentsAnyInput713: Encodable { let limit: Int }
    private struct HandoffInput713: Encodable { let shipmentId: Int }
    private struct YardsInput713: Encodable { let country: String; let limit: Int }
    private struct RailcarsInput713: Encodable { let limit: Int; let offset: Int }
    private struct DetentionInput713: Encodable { let onlyActive: Bool }
    private struct LineupInput713: Encodable { let railId: String }
    private struct NotifyInput713: Encodable {
        let shipmentId: Int
        let interchangePointName: String
        /// Optional on the wire. Left nil — and therefore off the payload —
        /// whenever no dwell clock backs a timing claim, so nothing about
        /// arrival timing reaches the consignee or the audit row.
        let etaText: String?
        let country: String
    }

    private func load() async {
        loading = true; loadError = nil

        // 1 · The gateway catalog for the active regime. This is the network.
        do {
            points = try await EusoTripAPI.shared.query(
                "railShipments.getCrossBorderInterchangePoints",
                input: CountryInput713(country: regime.rawValue))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // 2 · The anchor shipment. getInterchangeHandoff and getServiceLineup
        //     are both per-shipment; without an anchor neither can be asked.
        if let rows: [RailShipmentRow713] = try? await EusoTripAPI.shared.query(
            "railShipments.getRailShipments",
            input: ShipmentsStatusInput713(status: "at_interchange", limit: 1)), let first = rows.first {
            anchor = first
        } else if let rows: [RailShipmentRow713] = try? await EusoTripAPI.shared.query(
            "railShipments.getRailShipments", input: ShipmentsAnyInput713(limit: 1)) {
            anchor = rows.first
        }

        // 3 · Per-car custody at the gateways — the cars-on-hand that size the nodes.
        if let sid = anchor?.numericId {
            handoff = try? await EusoTripAPI.shared.query(
                "railShipments.getInterchangeHandoff", input: HandoffInput713(shipmentId: sid))
        } else {
            handoff = nil
        }

        // 4 · Yard anchors for the gateways that resolve to a yard.
        yards = (try? await EusoTripAPI.shared.query(
            "railShipments.getRailYards",
            input: YardsInput713(country: regime.rawValue, limit: 100))) ?? []

        // 5 · Secondary cars-on-hand source when the handoff board is empty.
        if let env: RailcarEnvelope713 = try? await EusoTripAPI.shared.query(
            "railShipments.getRailcars", input: RailcarsInput713(limit: 200, offset: 0)) {
            railcars = env.railcars ?? []
        } else {
            railcars = []
        }

        // 6 · The dwell clock. No match for a gateway means no ring — never a
        //     default-green one.
        detention = try? await EusoTripAPI.shared.query(
            "yardManagement.getDetentionTracking", input: DetentionInput713(onlyActive: true))

        // 7 · The next service call behind the anchor, for the subline.
        if let ref = anchor?.railRef, !ref.isEmpty {
            lineup = try? await EusoTripAPI.shared.query(
                "railShipments.getServiceLineup", input: LineupInput713(railId: ref))
        } else {
            lineup = nil
        }

        if loadError == nil || !points.isEmpty { lastGoodTick = Date() }
        loading = false
    }

    private func notifyConsignee() async {
        guard let sid = anchor?.numericId, let g = focusGateway else {
            notifyNotice = (notifyBlockedReason ?? "There is nothing to notify against.", false)
            return
        }
        notifying = true; notifyNotice = nil
        defer { notifying = false }

        // The free-time figure is composed from decoded state only. A nil
        // dwellHours means NO detention record matched this gateway — there is
        // no arrival timestamp and no clock. So nothing is claimed: etaText is
        // left off the payload entirely rather than asserting an arrival that
        // was never logged into a consignee push, a notifications row and an
        // immutable blockchainAuditTrail row.
        let eta: String? = { () -> String? in
            guard let d = g.dwellHours else { return nil }
            let remaining = g.slaHours - d
            return remaining > 0
                ? "\(hhmm713(remaining)) of interchange free time remaining"
                : "interchange free time exhausted \(hhmm713(-remaining)) ago"
        }()

        do {
            let res: NotifyResult713 = try await EusoTripAPI.shared.mutation(
                "railShipments.notifyConsigneeAtInterchange",
                input: NotifyInput713(shipmentId: sid,
                                      interchangePointName: g.name,
                                      etaText: eta,
                                      country: g.farCountry))
            if res.sent == true {
                let ch = (res.channels ?? []).joined(separator: ", ")
                var line = ch.isEmpty
                    ? "Consignee notified for \(g.name)."
                    : "Consignee notified for \(g.name) on \(ch)."
                if eta == nil {
                    // The audit row is immutable, so the operator is told
                    // exactly what it does and does not now assert.
                    line += " No interchange free-time figure was sent — no detention record matched this gateway, so none was claimed."
                }
                notifyNotice = (line, true)
            } else if res.reason == "no_consignee_on_file" {
                notifyNotice = ("No consignee on the waybill for this shipment — nothing was sent. Add a consignee before notifying.", false)
            } else {
                let errs = (res.errors ?? []).joined(separator: "; ")
                notifyNotice = (errs.isEmpty
                    ? "The notification was not sent."
                    : "The notification was not sent: \(errs)", false)
            }
        } catch {
            // ONLINE_ONLY: the failure is reported and dropped. It is never
            // queued — a replayed third-party fan-out is worse than no send.
            let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            notifyNotice = ("Notify failed and was NOT queued (online-only action): \(msg)", false)
        }
    }
}

#Preview("713 · Rail Dispatcher Gateway Map · Light") {
    RailDispatcherGatewayMapScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("713 · Rail Dispatcher Gateway Map · Dark") {
    RailDispatcherGatewayMapScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
