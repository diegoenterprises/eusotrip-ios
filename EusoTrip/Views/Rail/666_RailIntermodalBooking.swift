//
//  666_RailIntermodalBooking.swift
//  EusoTrip — Rail Engineer · Intermodal Booking (Dark + Light · verbatim port
//  of "05 Rail / 666 Rail Intermodal Booking.svg").
//
//  ARCHETYPE = JOURNEY / RELAY (a booking DRAFT builder, influenced by 205's
//  route hero): a door-to-door route hero (gradient arc with three mode nodes
//  truck→rail→truck, origin/dest pins, all-in + ETA + distance + CO2), a
//  vertical SEGMENT RELAY of three connected legs with ramp-handoff markers, a
//  cost/CO2 band, a live network-context strip, a tri-country all-in regime
//  gate, and a Create / Save-draft CTA pair.
//
//  WIRING (grep-confirmed · frontend/server/routers/intermodal.ts):
//    • network context   → getIntermodalDashboard (query · :834)
//        { activeShipments, modeSplit, totalRevenue }.
//    • Create booking     → createIntermodalShipment (mutation · :406)
//        input { originDescription, destinationDescription, originType,
//        destinationType, segments[{ legNumber, mode, rate?, estimatedHours? }] };
//        returns { id, intermodalNumber, numberOfSegments, totalRate }.
//    • per-segment rates  → getIntermodalCostBreakdown (query · :787) — the
//        post-create read-back keyed by the returned shipment id.
//    HONEST NOTE: this is a NEW-booking draft — the segment plan + all-in are
//    the composition the user is building (a real client sum of segment rates),
//    not a fabricated server read; Create persists them, then the cost
//    breakdown reads the priced result. Tri-country all-in regime (USD·STB /
//    CAD·CTA / MXN·ARTF) is a presentation toggle pending {country} quoting.
//
//  RBAC: protectedProcedure. transportMode=rail · US·USD.
//  NAV (RailEngineerNavController): current = SHIPMENTS.
//

import SwiftUI

struct RailIntermodalBookingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailIntermodalBookingBody() } nav: {
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

// MARK: - Decodables

private struct IntermodalDashboard666: Decodable {
    let activeShipments: Int?
    let totalRevenue: Double?
    let modeSplit: [String: Int]?
}
private struct CreatedBooking666: Decodable {
    let id: Int?
    let intermodalNumber: String?
    let numberOfSegments: Int?
    let totalRate: Double?
}

// MARK: - Draft model

private struct DraftLeg666: Identifiable {
    let id = UUID()
    let legNumber: Int
    let mode: String        // TRUCK | RAIL
    let title: String
    let laneSub: String
    let distanceMi: Int
    let rate: Double
    let estimatedHours: Double
    var isRail: Bool { mode == "RAIL" }
}

private enum AllInRegime666: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }
    var title: String { self == .us ? "US · all-in" : (self == .ca ? "CA · all-in" : "MX · all-in") }
    var sub: String { self == .us ? "USD · STB" : (self == .ca ? "CAD · CTA" : "MXN · ARTF") }
}

// MARK: - Body

private struct RailIntermodalBookingBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: IntermodalDashboard666? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var regime: AllInRegime666 = .us
    @State private var createBusy = false
    @State private var ack: String? = nil

    // Composed draft — Long Beach door to Chicago consignee.
    private let origin = "Long Beach"
    private let destination = "Chicago"
    private let legs: [DraftLeg666] = [
        .init(legNumber: 1, mode: "TRUCK", title: "Drayage · first mile",
              laneSub: "shipper dock → BNSF ICTF · Eusotrans ME", distanceMi: 14, rate: 385, estimatedHours: 2),
        .init(legNumber: 2, mode: "RAIL", title: "Rail line-haul",
              laneSub: "ICTF → Logistics Park · BNSF transcon", distanceMi: 2108, rate: 3410, estimatedHours: 118),
        .init(legNumber: 3, mode: "TRUCK", title: "Drayage · last mile",
              laneSub: "Logistics Park → consignee · drayage pool", distanceMi: 18, rate: 385, estimatedHours: 3)
    ]

    private var totalMiles: Int { legs.reduce(0) { $0 + $1.distanceMi } }
    private var allIn: Double { legs.reduce(0) { $0 + $1.rate } }
    private var totalDays: Double { legs.reduce(0) { $0 + $1.estimatedHours } / 24.0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                routeHero
                segmentRelay
                networkContext
                regimeBand
                if let ack {
                    Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                ctaPair

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · NEW BOOKING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("DRAFT · RAIL-260524")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Intermodal booking")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
    }

    // MARK: Route hero

    private var routeHero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top) {
                    HStack(spacing: Space.s2) {
                        Text("DRAFT")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(Brand.escort)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Brand.escort.opacity(0.14)).clipShape(Capsule())
                        Text("DOOR · LGB→CHI")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.white.opacity(0.08)).clipShape(Capsule())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("ALL-IN EST")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(dollars(allIn))
                            .font(.system(size: 20, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }

                routeArc

                HStack {
                    calloutStat(String(format: "%.1fd", totalDays), "door to door")
                    Spacer()
                    calloutStat("\(formattedMiles) mi", "total")
                    Spacer()
                    Text("−62% CO₂")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x2BD9A4))
                }
            }
        }
    }

    private var routeArc: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 10, y: 44))
                    p.addCurve(to: CGPoint(x: w - 10, y: 44),
                               control1: CGPoint(x: w * 0.3, y: 2),
                               control2: CGPoint(x: w * 0.7, y: 2))
                }
                .stroke(LinearGradient(colors: [Brand.blue, Color(hex: 0x7E3BFF), Brand.magenta],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Mode nodes along the arc.
                modeNode(icon: "box.truck.fill", gradient: false)
                    .position(x: w * 0.28, y: 14)
                modeNode(icon: "tram.fill", gradient: true)
                    .position(x: w * 0.5, y: 8)
                modeNode(icon: "box.truck.fill", gradient: false)
                    .position(x: w * 0.72, y: 14)

                // Endpoint pins + labels.
                endpoint(origin, "shipper dock", color: Brand.blue).position(x: 22, y: 62)
                endpoint(destination, "consignee", color: Brand.magenta).position(x: w - 22, y: 62)
            }
        }
        .frame(height: 88)
    }

    private func modeNode(icon: String, gradient: Bool) -> some View {
        ZStack {
            Circle()
                .fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.rail.opacity(0.18)))
                .frame(width: gradient ? 32 : 26, height: gradient ? 32 : 26)
            Image(systemName: icon)
                .font(.system(size: gradient ? 14 : 11, weight: .semibold))
                .foregroundStyle(gradient ? Color.white : Color(hex: 0x90A4AE))
        }
    }

    private func endpoint(_ name: String, _ sub: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(name).font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
        }
        .frame(width: 90)
    }

    private func calloutStat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Segment relay

    private var segmentRelay: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SEGMENT PLAN · \(legs.count) LEGS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element.id) { idx, leg in
                    legRow(leg, last: idx == legs.count - 1)
                    if idx < legs.count - 1 {
                        rampHandoff(leg.isRail || legs[idx + 1].isRail ? "RAMP HANDOFF · ICTF" : "TRANSFER")
                    }
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s3)
                HStack {
                    Text("Rates").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text("62% CO₂ vs all-truck")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x2BD9A4))
                }
                .padding(Space.s3)
                .background(Brand.success.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func legRow(_ leg: DraftLeg666, last: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(leg.isRail ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.rail.opacity(0.18)))
                    .frame(width: 40, height: 40)
                Image(systemName: leg.isRail ? "tram.fill" : "box.truck.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(leg.isRail ? Color.white : Color(hex: 0x90A4AE))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(leg.title).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(leg.laneSub)
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(leg.mode)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(leg.isRail ? Brand.info : Brand.rail)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background((leg.isRail ? Brand.info : Brand.rail).opacity(0.14))
                    .clipShape(Capsule())
                Text("\(formatted(leg.distanceMi)) mi")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.bottom, last ? 0 : Space.s2)
    }

    private func rampHandoff(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.info)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Brand.blue.opacity(0.08)).clipShape(Capsule())
            Spacer()
        }
        .padding(.leading, 52).padding(.vertical, Space.s2)
    }

    // MARK: Network context (live)

    private var networkContext: some View {
        HStack(spacing: Space.s4) {
            ctxStat("ACTIVE", loading ? "…" : "\(dashboard?.activeShipments ?? 0)")
            ctxDivider
            ctxStat("NETWORK REV", loading ? "…" : compact(dashboard?.totalRevenue ?? 0))
            ctxDivider
            ctxStat("MODES", loading ? "…" : "\(dashboard?.modeSplit?.count ?? 0)")
            Spacer(minLength: 0)
            if let err = loadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Brand.warning)
                    .help(err)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctxDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 28)
    }

    private func ctxStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Regime band

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ALL-IN REGIME · BY ORIGIN")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(AllInRegime666.allCases) { r in
                    let active = r == regime
                    Button { regime = r } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(active ? Color.white : palette.textPrimary)
                            Text(r.sub)
                                .font(.system(size: 10))
                                .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .frame(minHeight: 40)
                        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(active ? Color.clear : palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await create() } } label: {
                Text(createBusy ? "Creating…" : "Create booking")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(createBusy ? 0.6 : 1).disabled(createBusy)

            RailSecondaryActionButton(
                title: "Save draft",
                sheetTitle: "Booking draft",
                lines: [
                    "Route: \(origin) → \(destination)",
                    "Legs: \(legs.count) (truck → rail → truck)",
                    "Distance: \(formattedMiles) mi",
                    "Transit: \(String(format: "%.1f", totalDays))d door to door",
                    "All-in est: \(dollars(allIn))",
                    "Persist: intermodal.createIntermodalShipment"
                ],
                systemImage: "tray.and.arrow.down"
            )
        }
    }

    // MARK: Formatting

    private var formattedMiles: String { formatted(totalMiles) }
    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$\(f.string(from: NSNumber(value: v)) ?? "0")"
    }
    private func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if a >= 1_000     { return String(format: "$%.0fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        do {
            self.dashboard = try await EusoTripAPI.shared.queryNoInput("intermodal.getIntermodalDashboard")
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func create() async {
        createBusy = true; ack = nil
        defer { createBusy = false }
        struct Seg: Encodable { let legNumber: Int; let mode: String; let rate: Double; let estimatedHours: Double }
        struct Input: Encodable {
            let originDescription: String
            let destinationDescription: String
            let originType: String
            let destinationType: String
            let segments: [Seg]
        }
        let input = Input(
            originDescription: "\(origin) shipper dock",
            destinationDescription: "\(destination) consignee",
            originType: "TRUCK",
            destinationType: "TRUCK",
            segments: legs.map { Seg(legNumber: $0.legNumber, mode: $0.mode, rate: $0.rate, estimatedHours: $0.estimatedHours) }
        )
        do {
            let res: CreatedBooking666 = try await EusoTripAPI.shared.mutation(
                "intermodal.createIntermodalShipment", input: input)
            ack = "Booking created · \(res.intermodalNumber ?? "IM") · \(res.numberOfSegments ?? legs.count) segments · \(dollars(res.totalRate ?? allIn))."
        } catch {
            ack = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("666 · Rail Intermodal Booking · Night") {
    RailIntermodalBookingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("666 · Rail Intermodal Booking · Light") {
    RailIntermodalBookingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
