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
//    railShipments.getServiceLineup       (input {railId})                  → the consolidated rollup: train header (symbol/cars/status), the next-departure countdown + next-call yard, and the ordered per-call list (yard/status/clock).
//
//  De-fabrication (2026-06-07): every lineup figure now resolves from the
//  live getServiceLineup rollup (refined by getRailShipmentDetail/Tracking) or
//  renders an honest em-dash "-". The screen carries NO seeded values — the
//  old "Q-LACCHI1-23" / "8,940 ft" / "14,210 t" / "1h 20m" / "Barstow BNSF"
//  hero, the fixed LAX→BAR→KCK→GAL→CHI spine, the LA→Chicago figma call
//  timeline, and the "Hold 4 min at Barstow" ESANG advisory were all Figma
//  literals and are gone. No lineup on file → em-dash header + honest empty
//  timeline state, never a fabricated rotation.
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

// MARK: - Contract-drift-tolerant lineup DTOs
//
// These mirror the proposed getServiceLineup rollup contract. They are kept
// here as the crash-preventing decode path: the server can return either the
// iOS-shaped object or a bare railYards row, and the custom init(from:)
// reconciles both without throwing. Retained so that when getServiceLineup
// lands, hydration is contract-drift safe out of the box.

private struct TrainConsist586: Decodable {
    let trainSymbol: String?
    let carCount: Int?
    let scheduledCalls: Int?
    let clearedCalls: Int?
    let estimatedTransitHours: Int?
    let status: String?
    let nextCallLabel: String?
    let nextCallYardName: String?
}

private struct ServiceCall586: Decodable {
    let yardName: String?
    let detail: String?
    let status: String?
    let timeLabel: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Decode iOS struct fields directly if they exist (for future direct API shape)
        if let yn = try? c.decodeIfPresent(String.self, forKey: .yardName) {
            self.yardName = yn
            self.detail = try? c.decodeIfPresent(String.self, forKey: .detail)
            self.status = try? c.decodeIfPresent(String.self, forKey: .status)
            self.timeLabel = try? c.decodeIfPresent(String.self, forKey: .timeLabel)
        } else {
            // Server returns raw railYards row; map to iOS shape
            let name = try? c.decodeIfPresent(String.self, forKey: .name)
            let city = try? c.decodeIfPresent(String.self, forKey: .city)
            let state = try? c.decodeIfPresent(String.self, forKey: .state)
            let splcCode = try? c.decodeIfPresent(String.self, forKey: .splcCode)
            let serverStatus = try? c.decodeIfPresent(String.self, forKey: .status)
            let operatingHours = try? c.decodeIfPresent([String: String].self, forKey: .operatingHours)

            self.yardName = name

            // detail = city, state (or splcCode if available)
            var parts: [String] = []
            if let c = city { parts.append(c) }
            if let st = state { parts.append(st) }
            self.detail = parts.isEmpty ? splcCode : parts.joined(separator: ", ")

            self.status = serverStatus

            // timeLabel from operatingHours if available
            if let hours = operatingHours,
               let open = hours["open"],
               let close = hours["close"] {
                self.timeLabel = "\(open) - \(close)"
            } else {
                self.timeLabel = nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case yardName
        case detail
        case status
        case timeLabel
        // railYards table fields for server shape
        case name
        case city
        case state
        case splcCode
        case operatingHours
    }
}

private struct FacilityStatus586: Decodable {
    let facilityName: String?
    let rampStatus: String?
    let gateAvgMinutes: Int?
    let etaNote: String?
    let advisoryNote: String?

    enum CodingKeys: String, CodingKey {
        case facilityName, gates, operatingStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        facilityName = try? container.decode(String.self, forKey: .facilityName)

        // Extract rampStatus from operatingStatus enum ("NORMAL" → "open", etc.)
        let operatingStatus = try? container.decode(String.self, forKey: .operatingStatus)
        rampStatus = operatingStatus.map { status in
            status.lowercased() == "normal" ? "open" : "closed"
        }

        // Compute gateAvgMinutes from gates array average waitTime
        let gates = try? container.decode([GateInfo].self, forKey: .gates)
        if let gates = gates, !gates.isEmpty {
            let avgWaitTime = gates.map { $0.waitTime }.reduce(0, +) / gates.count
            gateAvgMinutes = avgWaitTime
        } else {
            gateAvgMinutes = nil
        }

        etaNote = nil
        advisoryNote = nil
    }

    private struct GateInfo: Decodable {
        let waitTime: Int
    }
}

private struct RailIdIn586: Encodable { let railId: String }

// The consolidated lineup `railShipments.getServiceLineup` returns: the
// train header (TrainConsist586 fields) plus the ordered per-call list.
// Honest-empty (`calls: []`, header nulls) when the server has no lineup.
private struct ServiceLineup586: Decodable {
    let trainSymbol: String?
    let carCount: Int?
    let scheduledCalls: Int?
    let clearedCalls: Int?
    let estimatedTransitHours: Int?
    let status: String?
    let nextCallLabel: String?
    let nextCallYardName: String?
    let calls: [ServiceCall586]?
}

// MARK: - Body

private struct RailServiceLineupBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var detail: RailShipmentDetail586? = nil
    @State private var tracking: RailTracking586? = nil
    @State private var lineup: ServiceLineup586? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var notifyArmed = false

    // ───────── Honest floor (no seeded figures) ─────────
    //
    // De-fabrication (2026-06-07): the whole-journey lineup the SVG draws was
    // representative seed (train symbol, car length/tons, countdown, next-call,
    // the LAX→BAR→KCK→GAL→CHI spine, and the LA→Chicago figma call timeline).
    // None of it was a real measurement. Every value now resolves from the live
    // railShipments.getServiceLineup rollup (+ getRailShipmentDetail/Tracking
    // refinement) or renders an honest em-dash. There are NO seeded constants.
    // When the server has no lineup (calls == [], header nulls), the screen
    // degrades to em-dashes + an honest empty timeline state, never a fake train.

    private let dash = "-"

    // ───────── Derived (live-refined where the API serves it) ─────────

    private var trainSymbol: String { lineup?.trainSymbol ?? detail?.shipmentNumber ?? dash }
    /// Live car count, nil when neither the lineup nor the detail serves one.
    private var carCount: Int? { lineup?.carCount ?? detail?.numberOfCars }
    private var statusOk: Bool {
        // No live status → make no green/ok claim.
        let s = (detail?.status ?? "").lowercased()
        return s == "in_transit" || s == "en_route"
    }
    private var statusLabel: String {
        switch (detail?.status ?? "").lowercased() {
        case "delayed":    return "DELAYED"
        case "terminated": return "TERMINATED"
        case "in_transit": return "EN ROUTE"
        case "en_route":   return "EN ROUTE"
        default:           return dash
        }
    }

    /// Hero countdown to the next departure — the live `nextCallLabel`, else "-".
    private var countdownText: String { lineup?.nextCallLabel ?? dash }
    /// Hero NEXT CALL yard — the live `nextCallYardName`, else "-".
    private var nextCallText: String { lineup?.nextCallYardName ?? dash }

    /// ESANG advisory headline. No live next-best-action / meet-pass source is
    /// on the wire, so when the lineup names a next call we surface that honest
    /// fact; otherwise an em-dash. Never a fabricated "hold N min" instruction.
    private var advisoryPrimary: String {
        if let next = lineup?.nextCallYardName, !next.isEmpty { return "Next service call: \(next)." }
        return dash
    }
    private var advisorySecondary: String {
        "No active advisory \(dash) live optimization pending."
    }

    /// Consist line: live car count only. The proc serves no on-plan delta,
    /// length-feet, or tonnage column, so those carry honest em-dashes rather
    /// than the old "8,940 ft" / "14,210 t" / "+0 min" figma figures.
    private var consistLine: String {
        let cars = carCount.map { "\($0) cars" } ?? "\(dash) cars"
        return "on plan \(dash)  ·  \(cars) · \(dash) ft · \(dash) t"
    }

    // Horizontal lane ribbon nodes derived from the live calls. The SVG drew a
    // fixed LAX→BAR→KCK→GAL→CHI spine; here each node is a real call (code from
    // the yard name) evenly spaced, with the state mapped off the call state.
    // Empty when there are no live calls → the spine renders blank, not a fake.
    private var laneNodes: [LaneNode586] {
        let live = calls
        guard !live.isEmpty else { return [] }
        let n = live.count
        return live.enumerated().map { idx, call in
            let progress: CGFloat = n <= 1 ? 0.5 : CGFloat(idx) / CGFloat(n - 1)
            let state: LaneNodeState586 = {
                switch call.state {
                case .done:    return idx == n - 1 ? .onEta : .done
                case .current: return .current
                default:       return .future
                }
            }()
            return LaneNode586(code: yardCode(call.station), progress: progress, state: state)
        }
    }

    /// 3-letter code from a yard name, e.g. "Barstow BNSF" → "BAR". Em-dash
    /// placeholder when the station is the dash sentinel / empty.
    private func yardCode(_ station: String) -> String {
        let trimmed = station.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != dash else { return dash }
        let letters = trimmed.uppercased().filter { $0.isLetter }
        return letters.isEmpty ? dash : String(letters.prefix(3))
    }

    // Live calls. Prefer the consolidated getServiceLineup rollup when the
    // server served real calls; otherwise refine state off tracking events when
    // present; otherwise empty — the UI shows an honest empty timeline state,
    // NOT a seeded LA→Chicago rotation.
    private var calls: [LineupCall586] {
        if let live = lineup?.calls, !live.isEmpty {
            return live.enumerated().map { idx, c in
                let st = (c.status ?? "").uppercased()
                let state: TimelineEventState =
                    st.contains("DEPART") || st.contains("ARRIV") || st.contains("CLEAR") ? .done
                    : (st.contains("NEXT") || st.contains("INTERCHANGE")) ? .current
                    : .future
                return LineupCall586(
                    id: "live-\(idx)",
                    station: c.yardName ?? dash,
                    detail: c.detail ?? "",
                    timeLabel: c.timeLabel ?? "",
                    state: state,
                    statusLabel: st.isEmpty ? "SCHEDULED" : st)
            }
        }
        // No consolidated lineup. We have no per-call clock times / dwell to
        // honestly fabricate from bare tracking events, so we render nothing
        // rather than invent a rotation. (Tracking still refines the header.)
        return []
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
                            Text("Live lineup unavailable - \(err).")
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
                    Text(countdownText)
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TO DEPART · NEXT CALL")
                            .font(.system(size: 9, weight: .black)).kerning(0.8)
                            .foregroundColor(palette.textTertiary)
                        Text(nextCallText)
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

                // Horizontal lane spine — only when the live lineup served
                // calls; no calls → no fabricated LAX→CHI ribbon.
                if !laneNodes.isEmpty {
                    LaneRibbonSpine586(nodes: laneNodes, palette: palette)
                        .frame(height: 30)
                        .padding(.top, 2)
                }
            }
            .padding(Space.s4)
        }
    }

    // MARK: Call timeline (BespokeChartKit · TimelineEventRail)

    private var callTimelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("CALL TIMELINE · \(calls.isEmpty ? dash : "\(calls.count)") ORDERED CALLS")
                    .font(.system(size: 9, weight: .black)).kerning(1.0)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text("getServiceLineup")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.textSecondary)
            }
            if calls.isEmpty {
                // Honest empty state — the server served no per-call rotation.
                // We do NOT draw the figma LA→Chicago train here.
                LifecycleCard {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(palette.textTertiary)
                        Text("No service lineup on file for this train.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
            } else {
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
                    // De-fabrication (2026-06-07): the "Hold 4 min at Barstow"
                    // / "avoids a 35-min wait at MP 56" advisory was figma copy
                    // with no live AI source. No meet-pass / next-best-action
                    // proc is on the wire, so we state the honest neutral status
                    // rather than a fabricated recommendation.
                    Text(advisoryPrimary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                    Text(advisorySecondary)
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

        // getServiceLineup returns the consolidated lineup (per-call clock
        // times, dwell, set-out/pick-up, next-departure countdown). It accepts
        // the shipmentNumber string directly, so it's the primary hydrate; the
        // detail/tracking procs still refine the header + per-call states.

        // Primary: the consolidated lineup (resolves by shipmentNumber).
        self.lineup = try? await EusoTripAPI.shared.query(
            "railShipments.getServiceLineup", input: RailIdIn586(railId: railId))

        guard numericId > 0 else {
            // No resolvable numeric id — the lineup above (if any) carries the
            // screen; with no lineup the UI shows honest em-dashes + empty state.
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
