//
//  586_RailServiceLineup.swift
//  EusoTrip — Rail 586 · Service Lineup
//
//  CARRIER-SIDE (Rail Engineer). VERBATIM port of
//  "05 Rail/Dark-SVG/586 Rail Service Lineup.svg" — its purpose-built
//  TIMELINE/SCHEDULE archetype (a route-rotation lineup), NOT a stat-tile
//  dashboard:
//    · lane-ribbon HERO — gradient-rim card: status + train-symbol + RAIL
//      badge pills, a numbers-first next-departure countdown, an on-plan
//      delta + consist line (cars · ft · tons), and a horizontal lane spine
//      (LAX→BAR→KCK→GAL→CHI) drawn in Canvas with travel progress, a glowing
//      current node and a green destination node.
//    · CALL TIMELINE — a vertical rail-spine ledger of the ordered yard/ramp
//      calls (one node per call: station, arr/dep tabular times, dwell + work
//      events, status chip, the CURRENT call highlighted). Rendered through
//      the BespokeChartKit `TimelineEventRail` primitive.
//    · ESANG next-best-action card.
//    · CTA pair — "Notify on departure" (gradient) · "Reroute" (outline).
//
//  Wiring (real railShipments router on disk — frontend/server/routers/railShipments.ts):
//    railShipments.getRailShipmentDetail (EXISTS :209, input {id})        → train header, origin/dest yards, car count, status
//    railShipments.getRailTracking       (EXISTS :554, input {shipmentId}) → events → derive per-call status (departed/current/scheduled)
//  The lineup-specific fields (per-call arr/dep clock times, dwell minutes,
//  set-out/pick-up counts, next-departure countdown) are not yet served by a
//  single procedure — they would come from a `getServiceLineup` rollup. Until
//  that lands those figures are representative seed (house 0%-mock, overwritten
//  on hydrate of the live detail/tracking pair). See the WIRE marker in load().
//

import SwiftUI

// MARK: - Outer shell

struct RailServiceLineupScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailServiceLineupBody(railId: railId)
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

// MARK: - Data shapes (mirror getRailShipmentDetail + getRailTracking)

private struct RailYard586: Decodable {
    let id: Int?
    let name: String?
    let code: String?
    let city: String?
    let state: String?
}

private struct RailLocation586: Decodable {
    let description: String?
}

private struct RailEvent586: Decodable, Identifiable {
    let id: Int?
    let eventType: String?
    let description: String?
    let location: RailLocation586?
    let timestamp: String?
    var stableID: String { id.map { "\($0)" } ?? UUID().uuidString }
}

private struct RailTracking586: Decodable {
    let events: [RailEvent586]?
    let currentLocation: RailLocation586?
}

private struct RailShipmentDetail586: Decodable {
    let id: Int?
    let shipmentNumber: String?
    let status: String?
    let numberOfCars: Int?
    let originRailroad: String?
    let originYard: RailYard586?
    let destinationYard: RailYard586?
}

// MARK: - Lineup call model (the bespoke call timeline rows)

private struct LineupCall586: Identifiable {
    let id: String
    let station: String        // "Barstow BNSF"
    let detail: String         // "crew change · 12 min dwell"
    let timeLabel: String      // "arr 14:35 · dep 14:47" or "dep 06:10"
    let state: TimelineEventState
    let statusLabel: String    // "DEPARTED" / "SCHEDULED" / "ON ETA"
}

// MARK: - Body

private struct RailServiceLineupBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var detail: RailShipmentDetail586? = nil
    @State private var tracking: RailTracking586? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var notifyArmed = false

    // ───────── Representative seed (house 0%-mock, overwritten on hydrate) ─────────
    //
    // The whole-journey lineup the SVG draws. Live detail/tracking refines the
    // train header + per-call status; the clock times / dwell / countdown are
    // seed until getServiceLineup lands (see WIRE marker in load()).

    private let seedTrainSymbol  = "Q-LACCHI1-23"
    private let seedCars         = 132
    private let seedLengthFt     = "8,940 ft"
    private let seedTons         = "14,210 t"
    private let seedCountdown    = "1h 20m"
    private let seedNextCall     = "Barstow BNSF"
    private let seedDeltaMin     = 0          // on-plan +0 min

    // Horizontal lane ribbon nodes: code · progress 0…1 · semantic state.
    private let laneNodes: [LaneNode586] = [
        LaneNode586(code: "LAX", progress: 0.01, state: .done),
        LaneNode586(code: "BAR", progress: 0.12, state: .current),
        LaneNode586(code: "KCK", progress: 0.46, state: .future),
        LaneNode586(code: "GAL", progress: 0.69, state: .future),
        LaneNode586(code: "CHI", progress: 0.99, state: .onEta)
    ]

    // Ordered calls (the vertical timeline).
    private var seedCalls: [LineupCall586] {
        [
            LineupCall586(id: "c1", station: "LA Long Beach ICTF",
                          detail: "origin ramp · BNSF · 132 cars built",
                          timeLabel: "dep 06:10", state: .done, statusLabel: "DEPARTED"),
            LineupCall586(id: "c2", station: "Barstow BNSF",
                          detail: "crew change · 12 min dwell · arr 14:35 · dep 14:47",
                          timeLabel: "in 1h 20m", state: .current, statusLabel: "NEXT"),
            LineupCall586(id: "c3", station: "Kansas City Argentine",
                          detail: "interchange · set out 18 · pick up 6",
                          timeLabel: "Tue 09:20", state: .future, statusLabel: "SCHEDULED"),
            LineupCall586(id: "c4", station: "Galesburg IL",
                          detail: "fuel + roll-by inspection · 25 min",
                          timeLabel: "Tue 19:05", state: .future, statusLabel: "SCHEDULED"),
            LineupCall586(id: "c5", station: "Chicago Logistics Park",
                          detail: "destination ramp · final · ETA holds",
                          timeLabel: "Wed 02:40", state: .done, statusLabel: "ON ETA")
        ]
    }

    // ───────── Derived (live-refined where the API serves it) ─────────

    private var trainSymbol: String { detail?.shipmentNumber ?? seedTrainSymbol }
    private var carCount: Int        { detail?.numberOfCars ?? seedCars }
    private var statusOk: Bool {
        let s = (detail?.status ?? "in_transit").lowercased()
        return s == "in_transit" || s == "en_route"
    }
    private var statusLabel: String {
        switch (detail?.status ?? "en_route").lowercased() {
        case "delayed":    return "DELAYED"
        case "terminated": return "TERMINATED"
        case "in_transit": return "EN ROUTE"
        default:           return "EN ROUTE"
        }
    }
    private var consistLine: String {
        let delta = seedDeltaMin
        let plan  = delta == 0 ? "on plan +0 min" : (delta > 0 ? "ahead \(delta) min" : "late \(-delta) min")
        return "\(plan)  ·  \(carCount) cars · \(seedLengthFt) · \(seedTons)"
    }

    // Live-refined calls: when tracking events exist, advance the call states
    // from the latest beat; otherwise show the representative seed lineup.
    private var calls: [LineupCall586] {
        guard let events = tracking?.events, !events.isEmpty else { return seedCalls }
        // Map known event types onto call states without fabricating times we
        // don't have — keep the seed clock labels, refine only the state/chip.
        let departedCount = events.filter {
            let t = ($0.eventType ?? "").lowercased()
            return t.contains("depart") || t.contains("arriv") || t.contains("scan")
        }.count
        return seedCalls.enumerated().map { idx, call in
            if idx < departedCount {
                return LineupCall586(id: call.id, station: call.station, detail: call.detail,
                                     timeLabel: call.timeLabel, state: .done, statusLabel: "DEPARTED")
            }
            return call
        }
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
                        HStack(spacing: Space.s3) {
                            ProgressView().tint(palette.textSecondary)
                            Text("Loading service lineup…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                } else {
                    if let err = loadError {
                        LifecycleCard(accentWarning: true) {
                            Text("Live lineup unavailable — \(err). Showing scheduled rotation.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    heroCard
                    callTimelineSection
                    esangCard
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · LINEUP")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced())
                .kerning(0.6)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Service lineup")
                .font(.system(size: 28, weight: .heavy))
                .kerning(-0.4)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: Hero — lane ribbon

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                // Pills row
                HStack(spacing: Space.s2) {
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold)).kerning(0.5)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill((statusOk ? Brand.success : Brand.warning).opacity(0.18)))
                        .foregroundColor(statusOk ? Brand.success : Brand.warning)

                    Text(trainSymbol)
                        .font(.system(size: 11, weight: .bold).monospaced()).kerning(0.4)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 5) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 10, weight: .heavy))
                        Text("RAIL")
                            .font(.system(size: 10, weight: .black)).kerning(0.6)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.rail))
                }

                // Countdown + next-call
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    Text(seedCountdown)
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TO DEPART · NEXT CALL")
                            .font(.system(size: 9, weight: .black)).kerning(0.8)
                            .foregroundColor(palette.textTertiary)
                        Text(seedNextCall)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                // On-plan delta + consist
                Text(consistLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Horizontal lane spine
                LaneRibbonSpine586(nodes: laneNodes, palette: palette)
                    .frame(height: 30)
                    .padding(.top, 2)
            }
            .padding(Space.s4)
        }
    }

    // MARK: Call timeline (BespokeChartKit · TimelineEventRail)

    private var callTimelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("CALL TIMELINE · \(calls.count) ORDERED CALLS")
                    .font(.system(size: 9, weight: .black)).kerning(1.0)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text("getServiceLineup")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.textSecondary)
            }
            TimelineEventRail(
                events: calls.map { call in
                    TimelineEventNode(
                        id: call.id,
                        title: call.station,
                        detail: call.detail,
                        timestamp: call.timeLabel,
                        state: call.state,
                        statusLabel: call.statusLabel
                    )
                },
                showSpine: true
            )
        }
    }

    // MARK: ESANG next-best-action

    private var esangCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)

            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                    Circle().fill(Color.white.opacity(0.45)).frame(width: 11, height: 11)
                        .offset(x: -4, y: -4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ESANG AI")
                        .font(.system(size: 9, weight: .black)).kerning(1.0)
                        .foregroundStyle(LinearGradient.primary)
                    Text("Hold 4 min at Barstow to take the Cajon meet —")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                    Text("avoids a 35-min wait at MP 56, protects the CHI ETA.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: notifyArmed ? "Armed · departure" : "Notify on departure",
                action: { notifyArmed.toggle() },   // WIRE: railShipments.notifyOnDeparture (proposed mutation — not on disk)
                leadingIcon: notifyArmed ? "bell.fill" : "bell"
            )
            Button("Reroute") {}
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint, lineWidth: 1)
                        )
                )
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        let numericId = Int(railId.filter(\.isNumber)) ?? 0

        // getServiceLineup would return the consolidated lineup (per-call
        // clock times, dwell, set-out/pick-up, next-departure countdown).
        // No such procedure exists on the railShipments router yet, so we
        // hydrate the train header + call states from the two procedures
        // that DO exist and keep representative seed for the rest.
        // WIRE: railShipments.getServiceLineup (proposed rollup — not on disk)

        guard numericId > 0 else {
            // No resolvable shipment id — present the scheduled seed rotation.
            loading = false
            return
        }

        do {
            struct DetailIn: Encodable { let id: Int }
            let d: RailShipmentDetail586 = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: DetailIn(id: numericId))
            self.detail = d

            struct TrackIn: Encodable { let shipmentId: Int }
            self.tracking = try? await EusoTripAPI.shared.query(
                "railShipments.getRailTracking", input: TrackIn(shipmentId: numericId))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Lane ribbon spine (horizontal Canvas — verbatim to SVG hero spine)

private enum LaneNodeState586 { case done, current, future, onEta }

private struct LaneNode586: Identifiable {
    let id = UUID()
    let code: String
    let progress: CGFloat   // 0…1 along the ribbon
    let state: LaneNodeState586
}

private struct LaneRibbonSpine586: View {
    let nodes: [LaneNode586]
    let palette: Theme.Palette

    private var travel: CGFloat {
        // The current node defines how far the travelled (gradient) segment runs.
        nodes.first(where: { $0.state == .current })?.progress
            ?? nodes.first(where: { $0.state == .done })?.progress
            ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lineY = geo.size.height * 0.34
            ZStack(alignment: .topLeading) {
                // Base hairline
                Path { p in
                    p.move(to: CGPoint(x: 4, y: lineY))
                    p.addLine(to: CGPoint(x: w - 4, y: lineY))
                }
                .stroke(Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Travelled segment (gradient)
                Path { p in
                    p.move(to: CGPoint(x: 4, y: lineY))
                    p.addLine(to: CGPoint(x: 4 + (w - 8) * travel, y: lineY))
                }
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Nodes + labels
                ForEach(nodes) { node in
                    let x = 4 + (w - 8) * node.progress
                    laneNode(node, x: x, y: lineY, h: geo.size.height)
                }
            }
        }
    }

    @ViewBuilder
    private func laneNode(_ node: LaneNode586, x: CGFloat, y: CGFloat, h: CGFloat) -> some View {
        let (fill, ring, label): (Color, Color, Color) = {
            switch node.state {
            case .done:    return (Color.clear, Brand.blue, Brand.blue)
            case .current: return (palette.bgCard, Brand.blue, Brand.blue)
            case .future:  return (palette.bgCard, palette.textTertiary, palette.textTertiary)
            case .onEta:   return (palette.bgCard, Brand.success, Brand.success)
            }
        }()

        ZStack {
            // Current node glow halo
            if node.state == .current {
                Circle().strokeBorder(Brand.blue.opacity(0.35), lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
            if node.state == .done {
                Circle().fill(LinearGradient.diagonal).frame(width: 10, height: 10)
            } else {
                Circle().fill(fill)
                    .overlay(Circle().strokeBorder(ring, lineWidth: 2.2))
                    .frame(width: node.state == .current ? 12 : 9,
                           height: node.state == .current ? 12 : 9)
            }
        }
        .position(x: x, y: y)

        Text(node.code)
            .font(.system(size: 8, weight: .black)).kerning(0.6)
            .foregroundColor(label)
            .position(x: x, y: y + 16)
    }
}

#Preview("586 · Rail Service Lineup · Night") {
    RailServiceLineupScreen(theme: Theme.dark, railId: "RAIL-260523-7C3A0B12D4")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("586 · Rail Service Lineup · Light") {
    RailServiceLineupScreen(theme: Theme.light, railId: "RAIL-260523-7C3A0B12D4")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
