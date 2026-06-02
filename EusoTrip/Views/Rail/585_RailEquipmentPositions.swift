//
//  585_RailEquipmentPositions.swift
//  EusoTrip — Rail Engineer · Equipment Positions (per-unit railcar position board).
//
//  VERBATIM-bespoke port of "05 Rail/Dark-SVG/585 Rail Equipment Positions.svg"
//  (flagship DETAIL grammar per FOUNDER CADENCE DIRECTIVE 2026-05-24): eyebrow +
//  mono ID caption, 28/-0.4 title, gradient-rimmed hero ActiveCard (cardRim + inset),
//  3-cell KPI strip (IN MOTION · AT YARD · BAD-ORDER), itemized POSITIONS ListRow
//  stack (40x40 rx10 railcar-grid icon chip + 14/700 car number + mono 11 location ·
//  container sub + status pill + right tabular value), CONTAINER · AEI context strip,
//  CTA pair (View on map · Refresh).  NAV: HOME · SHIPMENTS · [orb] · COMPLIANCE · ME.
//
//  Lane: LA/Long Beach ICTF → Chicago Logistics Park; well-car DTTX 748213 carrying
//  TCNU 7693120 on RAIL-260523-7C3A0B12D4. Shipper-of-record Eusorone Technologies.
//
//  Data (tRPC railShipments / tracking — generic string-path query client):
//    railShipments.getRailcars             EXISTS railShipments.ts:444 →
//        { railcars:[…], total } → POSITIONS rows + IN-MOTION / AT-YARD / BAD-ORDER KPIs + pool
//    railShipments.liveTrackRailcar        EXISTS railShipments.ts:733 → { railcarNumber } →
//        Railinc RailSight live speed/position for the lead in-motion car (hero AVG SPD)
//    railShipments.trackIntermodalContainer EXISTS railShipments.ts:893 → { containerNumber } →
//        Vizion intermodal container track → CONTAINER strip
//  No seed data: an empty getRailcars pool renders an honest "No railcar positions"
//  empty state. Every figure on screen comes from the live procs above or not at all.
//
//  CONTRACT-DRIFT HARDENING (origin/oath/contract-drift-fixes): the getRailcars
//  envelope tolerates BOTH the keyed `{ railcars:[…], total }` object AND a server
//  that returns a BARE ARRAY of railcars; every detail DTO uses a tolerant custom
//  `init(from:)` so a missing/renamed key never throws a decode crash.
//
//  ANIMATION POLISH (oath/anim-equipment-polish #3): the hero route arc sweeps
//  origin→current on appear (and on any data refresh) via a single decel spring
//  toward the REAL `routeProgress`, settling exactly on the true fraction.
//  Reduce-motion snaps to the final state.
//

import SwiftUI

// MARK: - Outer shell

struct RailEquipmentPositionsScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailEquipmentPositionsBody(railId: railId)
        } nav: {
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

// MARK: - Data shapes (mirror the real tRPC return envelopes)

/// railShipments.getRailcars → `{ railcars:[…], total }` OR a bare `[…]` array.
/// Contract-drift tolerant: decodes either the keyed object or the bare array so a
/// drifting server contract can never throw a decode crash on hydrate.
private struct GetRailcarsEnvelope585: Decodable {
    let railcars: [Railcar585]
    let total: Int?

    private enum CodingKeys: String, CodingKey {
        case railcars, total, items, data
    }

    init(from decoder: Decoder) throws {
        // Preferred: keyed object `{ railcars:[…], total }` (also tolerate items/data aliases).
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            let rows = (try? c.decode([Railcar585].self, forKey: .railcars))
                ?? (try? c.decode([Railcar585].self, forKey: .items))
                ?? (try? c.decode([Railcar585].self, forKey: .data))
            if let rows {
                railcars = rows
                total = (try? c.decode(Int.self, forKey: .total)) ?? rows.count
                return
            }
        }
        // Fallback: server returned a BARE ARRAY of railcars.
        if let arr = try? decoder.singleValueContainer().decode([Railcar585].self) {
            railcars = arr
            total = arr.count
            return
        }
        railcars = []
        total = 0
    }
}

private struct Railcar585: Decodable, Identifiable {
    var id: String { carNumber ?? "\(UUID())" }
    let carNumber: String?          // railcars.carNumber / reportingMark+number
    let carType: String?            // well_car / flatcar / boxcar …
    let status: String?             // in_transit / at_yard / bad_order …
    let currentLocation: String?    // free-text AEI / yard location
    let containerNumber: String?
    let speedMph: Double?
    let dwellHours: Double?
    let progressFraction: Double?   // (main hero) interpolation along route arc, if server supplies it

    private enum CodingKeys: String, CodingKey {
        case carNumber, reportingMark, number, railcarNumber
        case carType, status
        case currentLocation, location, currentLocationName
        case containerNumber, container
        case speedMph, speed
        case dwellHours, dwell
        case progressFraction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // carNumber, or railcarNumber alias, or reportingMark + number composed
        if let cn = try? c.decode(String.self, forKey: .carNumber) {
            carNumber = cn
        } else if let rn = try? c.decode(String.self, forKey: .railcarNumber) {
            carNumber = rn
        } else {
            let mark = (try? c.decode(String.self, forKey: .reportingMark)) ?? ""
            let num  = (try? c.decode(String.self, forKey: .number)) ?? ""
            let joined = [mark, num].filter { !$0.isEmpty }.joined(separator: " ")
            carNumber = joined.isEmpty ? nil : joined
        }
        carType         = try? c.decode(String.self, forKey: .carType)
        status          = try? c.decode(String.self, forKey: .status)
        currentLocation = (try? c.decode(String.self, forKey: .currentLocation))
            ?? (try? c.decode(String.self, forKey: .location))
            ?? (try? c.decode(String.self, forKey: .currentLocationName))
        containerNumber = (try? c.decode(String.self, forKey: .containerNumber))
            ?? (try? c.decode(String.self, forKey: .container))
        // speed may arrive as Double or Int → tolerate both before falling back to the `speed` alias.
        speedMph  = (try? c.decode(Double.self, forKey: .speedMph))
            ?? (try? c.decode(Int.self, forKey: .speedMph)).map(Double.init)
            ?? (try? c.decode(Double.self, forKey: .speed))
            ?? (try? c.decode(Int.self, forKey: .speed)).map(Double.init)
        dwellHours = (try? c.decode(Double.self, forKey: .dwellHours))
            ?? (try? c.decode(Int.self, forKey: .dwellHours)).map(Double.init)
            ?? (try? c.decode(Double.self, forKey: .dwell))
            ?? (try? c.decode(Int.self, forKey: .dwell)).map(Double.init)
        progressFraction = try? c.decode(Double.self, forKey: .progressFraction)
    }
}

/// railShipments.liveTrackRailcar → Railinc RailSight position (best-effort, tolerant shape).
private struct LiveRailcar585: Decodable {
    let speed: Double?
    let location: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case speed, speedMph
        case location, currentLocation
        case status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = (try? c.decode(Double.self, forKey: .speed))
            ?? (try? c.decode(Int.self, forKey: .speed)).map(Double.init)
            ?? (try? c.decode(Double.self, forKey: .speedMph))
            ?? (try? c.decode(Int.self, forKey: .speedMph)).map(Double.init)
        location = (try? c.decode(String.self, forKey: .location))
            ?? (try? c.decode(String.self, forKey: .currentLocation))
        status = try? c.decode(String.self, forKey: .status)
    }
}

/// railShipments.trackIntermodalContainer → Vizion track (best-effort, tolerant shape).
private struct IntermodalContainer585: Decodable {
    let containerNumber: String?
    let location: String?
    let lastReadMinutesAgo: Int?
    let iso6346Verified: Bool?
    let additionalUnits: Int?

    private enum CodingKeys: String, CodingKey {
        case containerNumber, container
        case location, lastLocation, lastAEILocation
        case lastReadMinutesAgo, minutesAgo
        case iso6346Verified, verified
        case additionalUnits
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        containerNumber = (try? c.decode(String.self, forKey: .containerNumber))
            ?? (try? c.decode(String.self, forKey: .container))
        location = (try? c.decode(String.self, forKey: .lastAEILocation))
            ?? (try? c.decode(String.self, forKey: .lastLocation))
            ?? (try? c.decode(String.self, forKey: .location))
        lastReadMinutesAgo = (try? c.decode(Int.self, forKey: .lastReadMinutesAgo))
            ?? (try? c.decode(Int.self, forKey: .minutesAgo))
        iso6346Verified = (try? c.decode(Bool.self, forKey: .iso6346Verified))
            ?? (try? c.decode(Bool.self, forKey: .verified))
        additionalUnits = try? c.decode(Int.self, forKey: .additionalUnits)
    }
}

// tRPC inputs (real proc shapes)
private struct GetRailcarsIn585: Encodable { let limit: Int; let offset: Int }
private struct RailcarNumberIn585: Encodable { let railcarNumber: String }
private struct ContainerNumberIn585: Encodable { let containerNumber: String }

// MARK: - Body

private struct RailEquipmentPositionsBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let railId: String

    @State private var railcars: [Railcar585] = []
    @State private var live: LiveRailcar585? = nil
    @State private var container: IntermodalContainer585? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hydrated = false

    /// Fraction the hero route arc animates toward. Starts at 0 so the arc sweeps
    /// origin→current on appear (and on any data refresh), always settling on the
    /// REAL `routeProgress`. Reduce-motion snaps to it. (oath/anim-equipment-polish #3)
    @State private var shownProgress: Double = 0

    /// POSITIONS rows — the real `railShipments.getRailcars` envelope, never a
    /// fabricated-on-empty seed. An empty pool renders an honest empty state.
    private var rows: [Railcar585] { railcars }

    // MARK: Derived counts (live, from the real getRailcars envelope)

    private func bucket(_ status: String?) -> String {
        switch (status ?? "").lowercased() {
        case "in_transit", "in_motion", "moving", "en_route": return "in_motion"
        case "bad_order", "bad-order", "badorder", "shopped":  return "bad_order"
        case "at_yard", "at_ramp", "spotted", "yard",
             "idle", "stored", "constructive_placement":       return "at_yard"
        default:                                               return "at_yard"
        }
    }

    private var inMotionCount: Int { rows.filter { bucket($0.status) == "in_motion" }.count }
    private var atYardCount: Int   { rows.filter { bucket($0.status) == "at_yard" }.count }
    private var badOrderCount: Int { rows.filter { bucket($0.status) == "bad_order" }.count }
    private var poolSize: Int      { railcars.count }

    private var avgSpeed: Int {
        // Prefer the Railinc live feed for the lead car; else average rolling in-motion rows.
        if let s = live?.speed, s > 0 { return Int(s.rounded()) }
        let moving = rows.compactMap { bucket($0.status) == "in_motion" ? $0.speedMph : nil }.filter { $0 > 0 }
        guard !moving.isEmpty else { return 0 }
        return Int((moving.reduce(0, +) / Double(moving.count)).rounded())
    }

    private var routeLabel: String { "BNSF transcon" }

    /// Real route fraction (origin→current) from the lead in-motion railcar's
    /// `progressFraction`. Falls back to 0 — never a decorative constant — so a
    /// loading/empty route shows no completed arc until the true fraction lands.
    private var routeProgress: Double {
        let lead = rows.first(where: { bucket($0.status) == "in_motion" })
            ?? rows.first(where: { $0.progressFraction != nil })
        return max(0, min(1, lead?.progressFraction ?? 0.0))
    }

    // MARK: Container strip values

    /// Lead container number — live Vizion track, else the first real railcar that
    /// carries one. `nil` when neither exists (the strip then hides itself).
    private var containerNumber: String? {
        container?.containerNumber
            ?? rows.first(where: { $0.containerNumber != nil })?.containerNumber
    }
    private var containerLocation: String? { container?.location }
    private var containerMinsAgo: Int? { container?.lastReadMinutesAgo }
    private var containerIsoOk: Bool? { container?.iso6346Verified }
    private var extraUnits: Int {
        if let a = container?.additionalUnits, a > 0 { return a }
        return max(0, poolSize - rows.count)
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()

                if loading {
                    LifecycleCard {
                        Text("Loading positions…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .padding(.vertical, 8)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger).padding(.vertical, 6)
                    }
                    ctaPair
                } else if rows.isEmpty {
                    EusoEmptyState(systemImage: "tram.fill",
                                   title: "No railcar positions",
                                   subtitle: "AEI positions for this lane's railcars will appear here the moment the carrier reports them.")
                    ctaPair
                } else {
                    heroCard
                    kpiStrip
                    positionsSection
                    if containerNumber != nil { containerStrip }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        // Arc-sweep on appear + on any data refresh; settles on the REAL fraction.
        .onAppear { settleSweep(to: routeProgress) }
        .onChange(of: routeProgress) { _, new in settleSweep(to: new) }
    }

    /// Animate the hero route arc sweep toward the real route fraction.
    /// Reduce-motion snaps to the final state; otherwise a natural decel settle.
    private func settleSweep(to target: Double) {
        let clamped = max(0, min(1, target))
        if reduceMotion {
            shownProgress = clamped
        } else {
            // Natural decel settle (no easeInOut on meaningful motion).
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                shownProgress = clamped
            }
        }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · POSITIONS")
                .font(.system(size: 9, weight: .black)).kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced()).kerning(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Equipment positions")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary).lineLimit(1)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Hero ActiveCard (gradient rim + inset) — "4 in motion / of 6 railcars" + AVG SPD

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold)).kerning(0.5)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.blue.opacity(0.12)))
                        .foregroundStyle(Brand.blue)
                    Text(routeLabel)
                        .font(.system(size: 11, weight: .bold)).kerning(0.5)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .foregroundStyle(palette.textPrimary)
                }

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                        Text("\(inMotionCount)")
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("in motion")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("of \(poolSize) railcars")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                    // Route-progress arc — sweeps origin→current via the animated
                    // `shownProgress`, settling on the real `routeProgress`.
                    RouteProgressArc585(fraction: shownProgress)
                        .frame(width: 56, height: 56)
                    Spacer().frame(width: Space.s3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AVG SPD")
                            .font(.system(size: 10, weight: .black)).kerning(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(avgSpeed)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text("mph rolling")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 116)
    }

    // MARK: KPI strip — IN MOTION (gradient) · AT YARD · BAD-ORDER

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "IN MOTION", value: "\(inMotionCount)", gradientNumeral: inMotionCount > 0)
            MetricTile(label: "AT YARD",   value: "\(atYardCount)")
            MetricTile(label: "BAD-ORDER", value: "\(badOrderCount)",
                       accent: badOrderCount > 0 ? Brand.danger : nil)
        }
    }

    // MARK: POSITIONS — itemized AEI list

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("POSITIONS")
                    .font(.system(size: 9, weight: .black)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("AEI · LIVE")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, car in
                    if idx > 0 {
                        Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, Space.s4)
                    }
                    positionRow(car)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            )
        }
    }

    @ViewBuilder
    private func positionRow(_ car: Railcar585) -> some View {
        let (pillLabel, pillColor) = positionPillInfo(car.status)
        let sub = [car.currentLocation, car.containerNumber]
            .compactMap { $0 }.joined(separator: " · ")
        let rightValue = positionRightValue(car)

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.info.opacity(0.12)).frame(width: 40, height: 40)
                // Well-car / container-car grid glyph (matches SVG: 3-cell well car)
                RailcarGridGlyph().stroke(Brand.info, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 14)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(car.carNumber ?? "—")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11).monospaced()).kerning(0.4)
                        .foregroundStyle(palette.textSecondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                    .foregroundStyle(pillColor)
                Text(rightValue)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
    }

    // MARK: CONTAINER · AEI strip

    @ViewBuilder
    private var containerStrip: some View {
        // Only rendered when `containerNumber != nil`. Each sub-detail (AEI read,
        // extra units, ISO verification) shows only when the live track supplies it.
        if let cnum = containerNumber {
            // Compose the AEI read line from whatever the Vizion track returned.
            let aeiLine: String? = {
                guard containerLocation != nil || containerMinsAgo != nil else { return nil }
                var parts = ["last AEI read"]
                if let loc = containerLocation { parts.append(loc) }
                if let mins = containerMinsAgo { parts.append("\(mins) min ago") }
                return parts.joined(separator: " ")
            }()
            let isoLine: String? = {
                var parts: [String] = []
                if extraUnits > 0 { parts.append("+\(extraUnits) more units off-screen") }
                if let ok = containerIsoOk { parts.append("ISO 6346 \(ok ? "verified" : "pending")") }
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            }()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CONTAINER")
                        .font(.system(size: 9, weight: .black)).kerning(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("ISO 6346")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(palette.textSecondary)
                }
                Text(aeiLine.map { "\(cnum) · \($0)" } ?? cnum)
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1)
                if let isoLine {
                    Text(isoLine)
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            )
        }
    }

    // MARK: CTA pair — View on map (gradient) · Refresh

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "View on map", action: {}, leadingIcon: "plus")
            Button("Refresh") { Task { await loadAll() } }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                )
        }
    }

    // MARK: Helpers

    private func positionPillInfo(_ status: String?) -> (String, Color) {
        switch bucket(status) {
        case "in_motion":
            return ("IN MOTION", Brand.success)
        case "bad_order":
            return ("BAD ORDER", Brand.danger)
        default:
            // distinguish at_ramp (blue) from at_yard (amber) by raw status
            switch (status ?? "").lowercased() {
            case "at_ramp", "spotted": return ("AT RAMP", Brand.blue)
            default:                   return ("AT YARD", Brand.warning)
            }
        }
    }

    private func positionRightValue(_ car: Railcar585) -> String {
        if bucket(car.status) == "in_motion" {
            if let s = car.speedMph, s > 0 { return "\(Int(s.rounded())) mph" }
            if avgSpeed > 0 { return "\(avgSpeed) mph" }
        }
        if let h = car.dwellHours, h > 0 { return "\(Int(h.rounded()))h" }
        return "—"
    }

    // MARK: Data loading

    private func loadAll() async {
        loading = !hydrated
        loadError = nil
        do {
            // 1. Railcar pool → POSITIONS rows + KPI buckets (real envelope).
            //    GetRailcarsEnvelope585 tolerates BOTH the keyed `{ railcars:[…] }`
            //    object AND a bare `[…]` array (contract-drift hardening).
            let env: GetRailcarsEnvelope585 = try await EusoTripAPI.shared.query(
                "railShipments.getRailcars",
                input: GetRailcarsIn585(limit: 50, offset: 0))
            railcars = env.railcars

            // 2. Lead in-motion railcar → Railinc RailSight live speed/position (best-effort).
            //    Only fires when the real pool actually has an in-motion car.
            if let lead = railcars.first(where: { bucket($0.status) == "in_motion" }),
               let num = lead.carNumber {
                live = try? await EusoTripAPI.shared.query(
                    "railShipments.liveTrackRailcar",
                    input: RailcarNumberIn585(railcarNumber: num))
            }

            // 3. Lead container → Vizion intermodal container track (best-effort).
            //    Only fires when a real railcar actually carries a container.
            if let cnum = railcars.compactMap({ $0.containerNumber }).first {
                container = try? await EusoTripAPI.shared.query(
                    "railShipments.trackIntermodalContainer",
                    input: ContainerNumberIn585(containerNumber: cnum))
            }

            // WIRE: tracking.getRealtimePositions — needs vehicleIds/loadIds keyed
            // to railcar GPS units (not yet plumbed for rail equipment); the AEI
            // pool above is the canonical position source until that lands.

            hydrated = true
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        // Re-settle the sweep onto the freshly-hydrated real fraction.
        settleSweep(to: routeProgress)
    }
}

// MARK: - Route-progress arc (hero) — animated origin→current sweep

/// A small gradient ring whose lit arc tracks `fraction` (the animated
/// `shownProgress`, settling on the real route fraction). (oath/anim-equipment-polish #3)
private struct RouteProgressArc585: View {
    let fraction: Double

    var body: some View {
        ZStack {
            // Full track (muted)
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 4)
            // Completed portion — trims to the ANIMATED fraction.
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, fraction))))
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((max(0, min(1, fraction)) * 100).rounded()))%")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(LinearGradient.primary)
        }
    }
}

// MARK: - Railcar grid glyph (well car · 3-cell, matches SVG icon chip)

private struct RailcarGridGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = 1.5
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
        let third = rect.width / 3
        p.move(to: CGPoint(x: rect.minX + third, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + third, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + third * 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + third * 2, y: rect.maxY))
        return p
    }
}

#Preview("585 · Equipment Positions · Night") {
    RailEquipmentPositionsScreen(theme: Theme.dark, railId: "RAIL-260523-7C3A0B12D4")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("585 · Equipment Positions · Light") {
    RailEquipmentPositionsScreen(theme: Theme.light, railId: "RAIL-260523-7C3A0B12D4")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
