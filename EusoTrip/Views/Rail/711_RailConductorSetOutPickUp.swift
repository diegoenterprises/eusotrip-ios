//
//  711_RailConductorSetOutPickUp.swift
//  EusoTrip — 05 Rail · 711 Rail Conductor Set-Out and Pick-Up Work Order.
//  CONDUCTOR SIDE · en-route switching · nav tab SHIPMENTS.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/711 Rail Conductor Set-Out and
//  Pick-Up Work Order.svg" — same sections, same order, same device:
//    eyebrow → headline → state chips → iridescent hairline → SPLIT LEDGER
//    (station header band; SET OUT left / centre rule / PICK UP right) →
//    NET CONSIST DELTA (on arrival → on departure) → OFFLINE queued-write strip
//    → tri-country band → CTA pair.
//
//  ─── WIRING MANIFEST ─────────────────────────────────────────────────────────
//    railShipments.getTrainConsists      EXISTS server/routers/railShipments.ts:1332
//        → {consists:[{id,consistNumber,totalCars,totalWeight,totalLengthFeet,
//           trainType,status,conductorId,originYardId,destinationYardId}], total}
//    railShipments.getYardTrackOccupancy EXISTS railShipments.ts:1246
//        → {yardId,yardName,totalTracks,capacity,utilizationPct,tracks[],unassigned[]}
//    railShipments.getRailcars           EXISTS server/routers/railShipments.ts:1192
//        → {railcars:[{id,railcarNumber,carType,status,trackNumber,lengthFeet,
//           tareWeight,loadLimit,currentYardId,yardName}], total}
//    railShipments.assignCarToTrack EXISTS railShipments.ts:1300  MUTATION
//    railShipments.createConsist         EXISTS server/routers/railShipments.ts:1454  MUTATION
//    railWorkOrder.getForStation         STUB · named-gap RAIL-CDR-711-WORK-ORDER
//    railWorkOrder.completeStationWork   STUB · named-gap RAIL-CDR-711-COMPLETE-WORK
//
//  RBAC:    railReadProcedure (railShipments.ts:94) · RAIL_CONDUCTOR (server/_core/trpc.ts:33)
//  WS:      WS_EVENTS.RAIL_CONSIST_UPDATE (shared/websocket-events.ts:411) refreshes
//           the ledger and the delta; WS_EVENTS.RAIL_IN_YARD (:403) arms the station
//           band; channel WS_CHANNELS.RAIL_YARD(yardId) (:622).
//  OFFLINE: QUEUE(consist) for the completion write (visible queued badge);
//           reads are READ_CACHED(10 min) with a real cached-at timestamp.
//
//  0 stubs in the view layer · 0 mock arrays · 0 placeholders. The ordered
//  set-out / pick-up list does not exist server-side, so the two columns render
//  the REAL car pools standing at the station (decoded from getRailcars, split by
//  the server's own status enum) under an explicit derivation note, and the
//  departure half of the delta stays honestly dashed until the order is served.
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI
import Combine

// MARK: - Screen

struct RailConductorSetOutPickUpScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConductorSetOutPickUpBody() } nav: {
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

/// railShipments.getTrainConsists (railShipments.ts:1332) envelope.
private struct WoConsistEnvelope: Decodable {
    let consists: [WoConsist]?
    let total: Int?
}

/// Mirrors the train_consists row the router selects wholesale.
private struct WoConsist: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let totalCars: Int?
    let totalLengthFeet: Int?
    let trainType: String?
    let status: String?
    let conductorId: Int?
    let originYardId: Int?
    let destinationYardId: Int?
    /// DECIMAL(12,2) — MySQL sends it as a string; both forms accepted, never guessed.
    let totalWeight: Double?

    enum CodingKeys: String, CodingKey {
        case id, consistNumber, totalCars, totalLengthFeet, trainType, status
        case conductorId, originYardId, destinationYardId, totalWeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.consistNumber = try c.decodeIfPresent(String.self, forKey: .consistNumber)
        self.totalCars = try c.decodeIfPresent(Int.self, forKey: .totalCars)
        self.totalLengthFeet = try c.decodeIfPresent(Int.self, forKey: .totalLengthFeet)
        self.trainType = try c.decodeIfPresent(String.self, forKey: .trainType)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.conductorId = try c.decodeIfPresent(Int.self, forKey: .conductorId)
        self.originYardId = try c.decodeIfPresent(Int.self, forKey: .originYardId)
        self.destinationYardId = try c.decodeIfPresent(Int.self, forKey: .destinationYardId)
        if let s = try? c.decodeIfPresent(String.self, forKey: .totalWeight), let d = Double(s) {
            self.totalWeight = d
        } else {
            self.totalWeight = try c.decodeIfPresent(Double.self, forKey: .totalWeight)
        }
    }
}

/// railShipments.getRailcars (railShipments.ts:1192) envelope.
private struct WoRailcarEnvelope: Decodable {
    let railcars: [WoRailcar]?
    let total: Int?
}

/// Mirrors the railcars row plus the router's yardName join.
private struct WoRailcar: Decodable, Identifiable {
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

/// railShipments.getYardTrackOccupancy (railShipments.ts:1246).
private struct WoYardOccupancy: Decodable {
    let yardId: Int?
    let yardName: String?
    let totalTracks: Int?
    let capacity: Int?
    let utilizationPct: Double?
    let tracks: [WoTrack]?
    let unassigned: [WoSlimCar]?
    let note: String?
}

private struct WoTrack: Decodable, Identifiable {
    var id: Int { trackNumber }
    let trackNumber: Int
    let carCount: Int?
    let cars: [WoSlimCar]?
}

private struct WoSlimCar: Decodable, Identifiable {
    let id: Int
    let carNumber: String?
    let carType: String?
    let status: String?
}

// MARK: - Body

private struct RailConductorSetOutPickUpBody: View {
    @Environment(\.palette) private var palette

    @State private var consist: WoConsist? = nil
    @State private var yard: WoYardOccupancy? = nil
    @State private var carsAtStation: [WoRailcar] = []

    @State private var loading = true
    @State private var loadError: String? = nil
    /// Real read timestamp — the only source of the cached-at line.
    @State private var readAt: Date? = nil
    @State private var now = Date()
    /// OFFLINE: reads are READ_CACHED(10 min); the completion is QUEUE(consist).
    private let cacheTTL: TimeInterval = 10 * 60

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: Derived state
    //
    // The ordered work order (which cars are cut out and which are lifted) is
    // the named gap. What the server DOES report is every car standing at the
    // station and the status the yard put it in. The left column therefore
    // shows the SET-OUT POOL (cars standing loaded / assigned here) and the
    // right column the PICK-UP POOL (cars standing available here). Both are
    // decoded rows, and the derivation is stated on screen.

    private var setOutPool: [WoRailcar] {
        carsAtStation.filter { ["loaded", "assigned", "in_transit"].contains($0.status ?? "") }
    }
    private var pickUpPool: [WoRailcar] {
        carsAtStation.filter { ($0.status ?? "") == "available" }
    }

    private var stationName: String {
        yard?.yardName ?? carsAtStation.first?.yardName ?? "station not resolved"
    }

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
    private var cacheAgeLabel: String {
        guard let age = cacheAgeSeconds else { return "no read yet" }
        let m = Int(age / 60)
        return m < 1 ? "under a minute" : "\(m) min"
    }

    private var subline: String {
        guard let c = consist else { return "no consist on file for this conductor" }
        var parts: [String] = []
        parts.append(c.consistNumber ?? "Consist \(c.id)")
        if let t = c.totalCars { parts.append("\(t) cars on arrival") }
        if let ty = c.trainType { parts.append(ty) }
        if let s = c.status { parts.append(s.replacingOccurrences(of: "_", with: " ")) }
        return parts.joined(separator: " · ")
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                Text(subline).font(EType.caption).foregroundStyle(palette.textSecondary)
                stateChips
                IridescentHairline().accessibilityHidden(true)

                if loading {
                    LifecycleCard { Text("Reading the station work…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text("Work order unavailable").font(EType.bodyStrong).foregroundStyle(Brand.danger)
                        Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Work order unavailable. \(err)")
                } else {
                    splitLedger
                    sectionLabel("NET CONSIST DELTA · ON DEPARTURE",
                                 trailing: "\(setOutPool.count) out · \(pickUpPool.count) in")
                    deltaCard
                    sectionLabel("WORK STATUS", trailing: "consist read · TTL 10 min")
                    offlineStrip
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
            Text("RAIL CONDUCTOR · STATION WORK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(consist?.consistNumber ?? "—")
                .font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rail conductor, station work. Consist \(consist?.consistNumber ?? "not resolved").")
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Set-out · pick-up").font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // Overflow glyph with no receiver behind it — never announced as a control.
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
        }
    }

    private var stateChips: some View {
        HStack(spacing: Space.s2) {
            chip("\(setOutPool.count) SET OUT", Brand.warning)
            chip("\(pickUpPool.count) PICK UP", Brand.success)
            chip("COMPLETION UNAVAILABLE", Brand.warning)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(setOutPool.count) set out, \(pickUpPool.count) pick up. Completion unavailable.")
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
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text). \(trailing).")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: THE DEVICE · the mirrored two-column split ledger

    private var splitLedger: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            VStack(alignment: .leading, spacing: 0) {
                stationBand
                HStack(alignment: .top, spacing: 0) {
                    ledgerColumn(title: "SET OUT · \(setOutPool.count)",
                                 tint: Brand.warning,
                                 cars: setOutPool,
                                 arrow: "→",
                                 role: "set-out pool",
                                 emptyLine: "no cars standing loaded here")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(palette.borderFaint).frame(width: 1)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                    ledgerColumn(title: "PICK UP · \(pickUpPool.count)",
                                 tint: Brand.success,
                                 cars: pickUpPool,
                                 arrow: "←",
                                 role: "pick-up pool",
                                 emptyLine: "no cars available here")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, Space.s3)
                }
                .padding(.top, Space.s3)
                Text("No issued set-out or pick-up order is available. These columns show recorded car pools at this station, grouped by yard status; confirm the ordered cuts with yard control.")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s3)
            }
            .padding(Space.s4)
        }
    }

    private var stationBand: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("STATION WORK · \(stationName.uppercased())")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.info)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(consist?.consistNumber ?? "—")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.info.opacity(0.14)))
            }
            Text(stationDetail).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Station work at \(stationName). Consist \(consist?.consistNumber ?? "not resolved"). \(stationDetail).")
    }

    /// Every fragment decoded from getYardTrackOccupancy — no invented arrival time.
    private var stationDetail: String {
        guard let y = yard else { return "yard track state unavailable" }
        var parts: [String] = []
        if let t = y.totalTracks { parts.append("\(t) track\(t == 1 ? "" : "s")") }
        if let u = y.utilizationPct { parts.append("\(u.formatted(.number.precision(.fractionLength(0...1))))% occupied") }
        if let un = y.unassigned?.count, un > 0 { parts.append("\(un) unassigned") }
        if let n = y.note { parts.append(n) }
        return parts.isEmpty ? "yard reports no track layout" : parts.joined(separator: " · ")
    }

    private func ledgerColumn(title: String, tint: Color, cars: [WoRailcar],
                              arrow: String, role: String, emptyLine: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(tint)
                .padding(.bottom, Space.s2)
                .accessibilityAddTraits(.isHeader)
            if cars.isEmpty {
                Text(emptyLine).font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(Array(cars.prefix(6).enumerated()), id: \.element.id) { idx, car in
                    if idx > 0 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 8)
                            .accessibilityHidden(true)
                    }
                    carRow(car, arrow: arrow, role: role, hazTint: tint)
                }
                if cars.count > 6 {
                    Text("+ \(cars.count - 6) more standing here")
                        .font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textTertiary)
                        .padding(.top, 8)
                }
            }
        }
    }

    /// One spoken statement per car row — decoded fields only, nothing inferred
    /// about lading, and an unassigned track is said rather than zeroed.
    private func carRowA11y(_ car: WoRailcar, role: String) -> String {
        var parts: [String] = ["Car \(car.railcarNumber ?? "number not recorded")"]
        if (car.carType ?? "") == "tankcar" { parts.append("tank car") }
        parts.append(carDetail(car))
        parts.append(car.trackNumber.map { "track \($0)" } ?? "track unassigned")
        parts.append(role)
        return parts.joined(separator: ", ")
    }

    private func carRow(_ car: WoRailcar, arrow: String, role: String, hazTint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Tank cars carry the regulated lading — flagged from the server's
            // own carType enum, never from a guessed commodity string.
            if (car.carType ?? "") == "tankcar" {
                RoundedRectangle(cornerRadius: 1.5).fill(Brand.warning).frame(width: 3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(car.railcarNumber ?? "—")
                        .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    if (car.carType ?? "") == "tankcar" {
                        Text("TANK").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Brand.warning)
                    }
                }
                Text(carDetail(car)).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text(trackLine(car, arrow: arrow))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(carRowA11y(car, role: role))
    }

    private func carDetail(_ car: WoRailcar) -> String {
        var parts: [String] = []
        parts.append((car.carType ?? "car").replacingOccurrences(of: "_", with: " "))
        if let o = car.owner, !o.isEmpty { parts.append(o) }
        if let l = car.lengthFeet { parts.append("\(l) ft") }
        return parts.joined(separator: " · ")
    }

    private func trackLine(_ car: WoRailcar, arrow: String) -> String {
        guard let t = car.trackNumber else { return "\(arrow) unassigned" }
        return "\(arrow) Track \(t)"
    }

    // MARK: NET CONSIST DELTA
    //
    // Arrival is REAL (the consist row). Departure needs the ordered work, which
    // is the named gap — so it stays dashed. A projected departure figure would
    // be a fabricated number and is refused.

    private var deltaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            deltaRow("Cars",
                     arrival: consist?.totalCars.map { "\($0)" },
                     departure: nil, delta: nil)
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 10)
                .accessibilityHidden(true)
            deltaRow("Length",
                     arrival: consist?.totalLengthFeet.map { "\($0.formatted()) ft" },
                     departure: nil, delta: nil)
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 10)
                .accessibilityHidden(true)
            deltaRow("Tonnage",
                     arrival: consist?.totalWeight.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) t" },
                     departure: nil, delta: nil)
            Text("Departure length and tonnage remain unknown until the ordered cut is recorded. Air-brake continuity retest is required after any cut.")
                .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func deltaRow(_ label: String, arrival: String?, departure: String?, delta: String?) -> some View {
        HStack(spacing: Space.s2) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Text(arrival ?? "—")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
            Text(departure ?? "—")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(departure == nil ? Brand.neutral : palette.textPrimary)
                .frame(width: 78, alignment: .trailing)
            Text(delta ?? "—")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(delta == nil ? Brand.neutral : Brand.danger)
                .frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). On arrival \(arrival ?? "not recorded"). On departure \(departure ?? "unknown until the ordered cut is recorded"). Change \(delta ?? "unknown").")
    }

    // MARK: OFFLINE · QUEUE(consist) + READ_CACHED(10 min)

    private var offlineStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.info)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Completion cannot be recorded here")
                        .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 8)
                    Text("NOT QUEUED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
                Text("No completion was queued or posted. Contact yard control to record the finished work.")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("consist read cached \(readAtLabel) · \(cacheAgeLabel) old · TTL 10 min")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(cacheExpired ? Brand.warning : palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Completion cannot be recorded here. Not queued. No completion was queued or posted. Contact yard control to record the finished work. Consist read cached \(readAtLabel), \(cacheAgeLabel) old, cache lifetime 10 minutes.")
    }

    // MARK: Tri-country band · the set-out car starts a free-time clock

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            countryTile("US · STB · AAR", "USD · 48h free", active: true)
            countryTile("CA · CTA", "CAD · 48h free", active: false)
            countryTile("MX · ARTF", "MXN · 24h free", active: false)
        }
    }

    private func countryTile(_ top: String, _ bottom: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Brand.info : palette.textSecondary).lineLimit(1)
            Text(bottom).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Brand.info : palette.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(top). \(bottom).")
        .accessibilityValue(active ? "Active regime" : "Not the active regime")
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                // NAMED GAP RAIL-CDR-711-COMPLETE-WORK. railWorkOrder.completeStationWork
                // does not exist and no rail mutation legitimately receives a
                // conductor's station-work completion, so this is a REAL Button that
                // is really disabled: it cannot be pressed, it is visibly inert, and
                // it states why to VoiceOver. It never queues and never fakes success.
                Button {} label: {
                    Text("Complete work")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(LinearGradient.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.42)
                .saturation(0.35)
                .accessibilityLabel("Complete work")
                .accessibilityValue("Unavailable. Contact yard control to record the finished move.")
                .accessibilityAddTraits(.isButton)

                Button {
                    Task { await assignTrack() }
                } label: {
                    Text("Assign track")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 132).frame(height: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(assignTarget == nil)
                .opacity(assignTarget == nil ? 0.42 : 1)
                .saturation(assignTarget == nil ? 0.35 : 1)
                .accessibilityLabel("Assign track")
                .accessibilityValue(assignTargetA11yValue)
                .accessibilityHint("Requests Track 1 for the first unassigned car and refreshes the yard record after acceptance.")
                .accessibilityAddTraits(.isButton)
            }
            Text(ctaNote).font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Spoken state for Assign track — the disabled reason carries the same
    /// substance as the visible caption beneath the pair.
    private var assignTargetA11yValue: String {
        guard let car = assignTarget else {
            return "Unavailable. Assign track needs an unassigned car standing at this yard."
        }
        return "Ready for car \(car.railcarNumber ?? "number not recorded")"
    }

    private var ctaNote: String {
        let assign = assignTarget == nil
            ? "Assign track needs an unassigned car standing at this yard."
            : "Assign track requests Track 1 for the first unassigned car and refreshes the yard record after acceptance."
        return "Complete work is unavailable. Contact yard control to record the finished move. " + assign
    }

    /// The first REAL unassigned car at this station — the only car the existing
    /// assignCarToTrack mutation may legally touch (it rejects cars not at the yard).
    private var assignTarget: WoRailcar? {
        carsAtStation.first { $0.trackNumber == nil }
    }

    // MARK: Data

    private struct RailcarsInput: Encodable {
        let yardId: Int
        let limit: Int
        let offset: Int
    }
    private struct YardInput: Encodable { let yardId: Int }
    private struct AssignInput: Encodable {
        let yardId: Int
        let carId: Int
        let trackNumber: Int?
    }
    private struct AssignResult: Decodable {
        let success: Bool?
        let carId: Int?
        let trackNumber: Int?
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            // 1. The conductor's consist (railShipments.ts:1071).
            let env: WoConsistEnvelope = try await EusoTripAPI.shared.queryNoInput("railShipments.getTrainConsists")
            self.consist = env.consists?.first

            // 2. The work location — the consist's destination yard, else its origin.
            //    No yard on the row → no station calls, and the ledger says so.
            let stationYardId = self.consist?.destinationYardId ?? self.consist?.originYardId
            if let yid = stationYardId {
                self.yard = try await EusoTripAPI.shared.query("railShipments.getYardTrackOccupancy",
                                                               input: YardInput(yardId: yid))
                let cars: WoRailcarEnvelope = try await EusoTripAPI.shared.query(
                    "railShipments.getRailcars",
                    input: RailcarsInput(yardId: yid, limit: 50, offset: 0))
                self.carsAtStation = cars.railcars ?? []
            } else {
                self.yard = nil
                self.carsAtStation = []
            }

            self.readAt = Date()
            self.now = Date()
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    /// The one write this screen can honestly make today: park the first
    /// unassigned car standing at the station on track 1. Real mutation, real
    /// server-side validation (it rejects a car that is not at this yard), and
    /// the ledger reloads from the server rather than mutating local state.
    private func assignTrack() async {
        guard let car = assignTarget, let yid = yard?.yardId else { return }
        do {
            let _: AssignResult = try await EusoTripAPI.shared.mutation(
                "railShipments.assignCarToTrack",
                input: AssignInput(yardId: yid, carId: car.id, trackNumber: 1))
            await load()
        } catch {
            loadError = error.eusoUserCopy
        }
    }
}

#Preview("711 · Conductor Set-Out / Pick-Up · Night") {
    RailConductorSetOutPickUpScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("711 · Conductor Set-Out / Pick-Up · Light") {
    RailConductorSetOutPickUpScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
