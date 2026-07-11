//
//  692_VesselTransshipmentConnection.swift
//  EusoTrip — Vessel Operator · Transshipment Connection (CARRIER-SIDE · MAP/CONNECTION class).
//
//  Verbatim port of "692 Vessel Transshipment Connection.svg" (Dark + Light).
//  A TWO-NODE CONNECTION chart — the arriving feeder leg crossing the hub-port
//  fence at LEFT, the onward mother-vessel leg holding at the CY/berth at RIGHT,
//  joined by a transfer arc — over a connection-status meter and a leg-to-leg
//  sequence ledger, fused with one ESANG card. Deliberately NOT the flat dwell
//  stat card the batch stamped.
//
//  Web parity: IntermodalJourney.tsx (`/intermodal/:id/tracking`).
//
//  DATA (endpoints confirmed on disk this fire — real code wins the SVG's stale line refs):
//    intermodal.getIntermodalTracking      → { segments, containers, currentMode, activeSegmentId }
//                                             (protectedProcedure · server/routers/intermodal.ts:732)
//    intermodal.getIntermodalCostBreakdown → { intermodalNumber, segments, transfers,
//                                             totalSegmentCost, totalTransferCost, grandTotal, currency }
//                                             (protectedProcedure · server/routers/intermodal.ts:787)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • The live connection BUFFER / onward CUTOFF / DWELL clock is not a typed
//      intermodal field. This port renders the connection-STATUS meter (legs
//      completed / active-leg mode+status / onward mode) from real segment rows,
//      and the buffer band reads "connection window not published" rather than a
//      fabricated 5.5h. Propose intermodal.getIntermodalTracking adding a nested
//      { connectionBufferHours, onwardCutoff, dwellHours, riskVector } object.
//    • Live AIS feeder position is not in this env — the hero chart is a faithful
//      SCHEMATIC of the connection whose node states are driven by the real leg
//      statuses (arriving / transfer / booked), never a fabricated lat/lng.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel (transshipment leg is vessel-to-vessel) · SG hub / US import · USD.
//  PERSONA Vessel Operator · shipper-of-record DU/Eusorone.
//

import SwiftUI

struct VesselTransshipmentConnectionScreen: View {
    let theme: Theme.Palette
    /// Intermodal shipment this connection is drilled into (query scope only —
    /// an unowned/unknown id reads as the honest empty state server-side).
    var intermodalShipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselTransshipmentConnectionBody(intermodalShipmentId: intermodalShipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getIntermodalTracking + getIntermodalCostBreakdown)

private struct IntermodalSegment: Decodable, Identifiable {
    let id: Int
    let legNumber: Int?
    let mode: String?
    let status: String?
    let rate: String?
    let originName: String?
    let destinationName: String?
    let carrierName: String?
    let vesselName: String?
}

private struct IntermodalTrackingResponse: Decodable {
    let segments: [IntermodalSegment]
    let currentMode: String?
    let activeSegmentId: Int?
}

private struct IntermodalCostSegment: Decodable { let legNumber: Int?; let mode: String?; let rate: Double? }
private struct IntermodalCostTransfer: Decodable { let transferType: String?; let cost: Double?; let facilityName: String? }
private struct IntermodalCostResponse: Decodable {
    let intermodalNumber: String?
    let transfers: [IntermodalCostTransfer]
    let totalSegmentCost: Double?
    let totalTransferCost: Double?
    let grandTotal: Double?
    let currency: String?
}

// MARK: - Body

private struct VesselTransshipmentConnectionBody: View {
    @Environment(\.palette) private var palette

    let intermodalShipmentId: Int

    @State private var tracking: IntermodalTrackingResponse? = nil
    @State private var cost: IntermodalCostResponse? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    connectionChartHero
                    connectionMeter
                    sequenceLedger
                    esangCard
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var segments: [IntermodalSegment] {
        (tracking?.segments ?? []).sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) }
    }

    // MARK: Top bar (DETAIL)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · TRANSSHIPMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(cost?.intermodalNumber.map { $0.uppercased() } ?? "AIS · CONNECTION")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Hub connection")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: Hero — two-node connection chart

    private var connectionChartHero: some View {
        ConnectionChart(
            feederLabel: feederNode.title,
            feederSub: feederNode.sub,
            feederState: feederNode.state,
            onwardLabel: onwardNode.title,
            onwardSub: onwardNode.sub,
            onwardState: onwardNode.state,
            transferLabel: transferLabel
        )
        .frame(height: 158)
        .frame(maxWidth: .infinity)
        .padding(1.5)
        .background(LinearGradient.diagonal.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private struct NodeVM { let title: String; let sub: String; let state: ConnectionChart.NodeState }

    private var feederNode: NodeVM {
        guard let first = segments.first else {
            return NodeVM(title: "Feeder leg", sub: "awaiting AIS feed", state: .pending)
        }
        let ttl = first.vesselName ?? first.carrierName ?? "Feeder \(first.legNumber ?? 1)"
        let sub = laneString(first)
        let st: ConnectionChart.NodeState = statusIsActive(first.status) ? .active
            : statusIsDone(first.status) ? .done : .pending
        return NodeVM(title: ttl, sub: sub, state: st)
    }

    private var onwardNode: NodeVM {
        guard segments.count > 1, let last = segments.last else {
            return NodeVM(title: "Onward leg", sub: "not yet booked", state: .pending)
        }
        let ttl = last.vesselName ?? last.carrierName ?? "Onward \(last.legNumber ?? 2)"
        let sub = laneString(last)
        let st: ConnectionChart.NodeState = statusIsActive(last.status) ? .active
            : statusIsDone(last.status) ? .done : .pending
        return NodeVM(title: ttl, sub: sub, state: st)
    }

    private var transferLabel: String {
        if let f = cost?.transfers.first?.facilityName, !f.isEmpty { return "TRANSFER · \(f.uppercased())" }
        return "TRANSFER"
    }

    private func laneString(_ s: IntermodalSegment) -> String {
        let o = s.originName ?? "—"; let d = s.destinationName ?? "—"
        return "\(o) → \(d)"
    }
    private func statusIsActive(_ s: String?) -> Bool {
        ["in_transit", "booked", "arriving", "loading"].contains((s ?? "").lowercased())
    }
    private func statusIsDone(_ s: String?) -> Bool {
        ["completed", "delivered", "discharged", "arrived"].contains((s ?? "").lowercased())
    }

    // MARK: Connection-status meter (ring + columns — honest fields)

    private var connectionMeter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONNECTION STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getIntermodalTracking")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s4) {
                ProgressRing(fraction: legFraction, centerTop: "\(legsDone)/\(max(segments.count, 1))", centerBottom: "LEGS")
                    .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: Space.s3) {
                    meterCol("ACTIVE LEG", activeLegLabel)
                    HStack(spacing: Space.s5) {
                        meterCol("ONWARD MODE", (tracking?.currentMode ?? "—").uppercased())
                        meterCol("TRANSFERS", "\(cost?.transfers.count ?? 0)")
                    }
                }
                Spacer(minLength: 0)
            }
            Text("Live connection window not published on this shipment — showing leg status. Buffer/cutoff clock pending intermodal schedule fields.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl)
    }

    private var legsDone: Int { segments.filter { statusIsDone($0.status) }.count }
    private var legFraction: Double {
        guard !segments.isEmpty else { return 0 }
        return Double(legsDone) / Double(segments.count)
    }
    private var activeLegLabel: String {
        if let active = segments.first(where: { statusIsActive($0.status) }) {
            return "\((active.mode ?? "leg").capitalized) · \(prettyStatus(active.status))"
        }
        return "—"
    }

    private func meterCol(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: Leg-to-leg sequence ledger

    private var sequenceLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONNECTION SEQUENCE · \(segments.count) LEGS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard { Text("Loading connection…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if segments.isEmpty {
                EusoEmptyState(icon: Image(systemName: "arrow.triangle.swap"),
                               title: "No connection legs",
                               subtitle: "Legs for this transshipment will appear here once the shipment is booked.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                        legRow(seg)
                        if idx < segments.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                    if let grand = cost?.grandTotal {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, Space.s2)
                        HStack {
                            Text("Connection cost")
                                .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                            Spacer()
                            Text(money(grand, cost?.currency))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.textPrimary)
                        }
                        .padding(.top, Space.s2)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.xl)
            }
        }
    }

    private func legRow(_ seg: IntermodalSegment) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(legTint(seg).opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: modeIcon(seg.mode))
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(legTint(seg))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Leg \(seg.legNumber ?? 0) · \(seg.vesselName ?? seg.carrierName ?? (seg.mode ?? "segment").capitalized)")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(laneString(seg))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            StatusPill(text: prettyStatus(seg.status), kind: pillKind(seg.status))
        }
    }

    // MARK: ESANG card

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · CONNECTION PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(esangHeadline)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(esangSub)
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl)
    }

    private var esangHeadline: String {
        if segments.isEmpty { return "No live connection to advise on yet" }
        if let active = segments.first(where: { statusIsActive($0.status) }) {
            return "Keep \(active.mode ?? "the") leg moving to protect the transfer"
        }
        return "All legs staged — clear for the onward move"
    }
    private var esangSub: String {
        let m = tracking?.currentMode ?? "—"
        return "onward mode \(m) · \(cost?.transfers.count ?? 0) transfer point(s)"
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let intermodalShipmentId: Int }
        let input = In(intermodalShipmentId: intermodalShipmentId)
        do {
            self.tracking = try await EusoTripAPI.shared.query("intermodal.getIntermodalTracking", input: input)
            self.cost = try? await EusoTripAPI.shared.query("intermodal.getIntermodalCostBreakdown", input: input)
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    // MARK: helpers

    private func prettyStatus(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "PENDING" }
        return s.replacingOccurrences(of: "_", with: " ").uppercased()
    }
    private func pillKind(_ s: String?) -> StatusPill.Kind {
        switch (s ?? "").lowercased() {
        case "completed", "delivered", "discharged", "arrived": return .success
        case "in_transit", "booked", "arriving", "loading": return .info
        case "delayed", "exception", "held": return .warning
        default: return .neutral
        }
    }
    private func legTint(_ s: IntermodalSegment) -> Color {
        switch (s.status ?? "").lowercased() {
        case "completed", "delivered", "discharged", "arrived": return Brand.success
        case "in_transit", "booked", "arriving", "loading": return Brand.info
        default: return Brand.neutral
        }
    }
    private func modeIcon(_ mode: String?) -> String {
        switch (mode ?? "").lowercased() {
        case "vessel", "ocean", "sea": return "ferry.fill"
        case "rail": return "tram.fill"
        case "truck", "drayage", "road": return "box.truck.fill"
        default: return "arrow.triangle.swap"
        }
    }
    private func money(_ v: Double, _ ccy: String?) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = ccy ?? "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(ccy ?? "USD") \(Int(v))"
    }
}

// MARK: - ConnectionChart (bespoke two-node schematic)

private struct ConnectionChart: View {
    enum NodeState { case done, active, pending }
    let feederLabel: String
    let feederSub: String
    let feederState: NodeState
    let onwardLabel: String
    let onwardSub: String
    let onwardState: NodeState
    let transferLabel: String

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                    .fill(palette.bgCard)

                // grid hint lines
                Path { p in
                    for gx in stride(from: w * 0.18, to: w, by: w * 0.2) {
                        p.move(to: CGPoint(x: gx, y: 12)); p.addLine(to: CGPoint(x: gx, y: h - 12))
                    }
                }.stroke(palette.borderFaint, lineWidth: 1)

                // hub geofence ring (left)
                Circle()
                    .stroke(Brand.info.opacity(0.6), style: StrokeStyle(lineWidth: 1.4, dash: [5, 5]))
                    .frame(width: h * 0.62, height: h * 0.62)
                    .position(x: w * 0.28, y: h * 0.46)
                Text("HUB · FENCE")
                    .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.info)
                    .position(x: w * 0.28, y: h * 0.16)

                // transfer arc (gradient)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.28, y: h * 0.46))
                    p.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.58),
                                   control: CGPoint(x: w * 0.55, y: h * 0.12))
                }
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [2, 5]))
                Text(transferLabel)
                    .font(.system(size: 7, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.magenta)
                    .position(x: w * 0.55, y: h * 0.2)

                // feeder node (left)
                node(state: feederState, glyph: "ferry.fill")
                    .position(x: w * 0.28, y: h * 0.46)
                // onward node (right)
                node(state: onwardState, glyph: "ferry.fill")
                    .position(x: w * 0.80, y: h * 0.58)

                // labels
                VStack(alignment: .leading, spacing: 1) {
                    Text(feederLabel.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text(feederSub).font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                .frame(width: w * 0.4, alignment: .leading)
                .position(x: w * 0.24, y: h * 0.82)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(onwardLabel.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text(onwardSub).font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                .frame(width: w * 0.4, alignment: .trailing)
                .position(x: w * 0.76, y: h * 0.86)

                // AIS-schematic badge
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 5, height: 5)
                    Text("SCHEMATIC").font(.system(size: 7, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.success)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Brand.success.opacity(0.14)))
                .position(x: w * 0.16, y: 18)
            }
        }
    }

    @ViewBuilder
    private func node(state: NodeState, glyph: String) -> some View {
        let color: Color = state == .done ? Brand.success : state == .active ? Brand.info : Brand.neutral
        ZStack {
            Circle().fill(color.opacity(0.18)).frame(width: 30, height: 30)
            Circle().strokeBorder(color, lineWidth: 1.4).frame(width: 30, height: 30)
            Image(systemName: glyph).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
        }
    }
}

// MARK: - ProgressRing (shared small ring)

private struct ProgressRing: View {
    let fraction: Double
    let centerTop: String
    let centerBottom: String
    @Environment(\.palette) private var palette
    var body: some View {
        ZStack {
            Circle().stroke(palette.borderFaint, lineWidth: 7)
            Circle().trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(centerTop).font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(centerBottom).font(.system(size: 7, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

#Preview("692 · Vessel Transshipment Connection · Night") {
    VesselTransshipmentConnectionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("692 · Vessel Transshipment Connection · Light") {
    VesselTransshipmentConnectionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
