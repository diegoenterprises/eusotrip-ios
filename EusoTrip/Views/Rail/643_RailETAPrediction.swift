//
//  643_RailETAPrediction.swift
//  EusoTrip — Rail Engineer · ETA Prediction (MAP/PREDICTION forecast surface).
//
//  Verbatim port of "643 Rail ETA Prediction.svg" (Dark).
//  ARCHETYPE = MAP/PREDICTION journey (NOT the generic hero+3KPI+ledger):
//    · MapCanvas route panel hero — origin pin, interchange node, live car
//      position, destination pin, gradient route arc, ETA callout chip.
//    · CONFIDENCE band card with a P10 · P50 · P90 interval bar.
//    · PER-SEGMENT FORECAST ledger — each leg = chip + leg name + predicted
//      clock + confidence/risk pill.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] ·
//  [orb] · COMPLIANCE · ME).
//
//  Data (verified against intermodal.ts + drizzle/schema.ts):
//    intermodal.getIntermodalTracking        (EXISTS · intermodal.ts:269)
//        input {intermodalShipmentId:Int} → {segments[], containers[],
//        currentMode, activeSegmentId}. Drives the route arc + live car pin
//        + per-segment ledger (leg name, predicted clock, status).
//    intermodal.getIntermodalShipmentDetail  (EXISTS · intermodal.ts:161)
//        input {id:Int} → {...shipment, segments[], transfers[], containers[]}.
//        Enriches the ledger with the full ordered segment set + origin/dest.
//
//  PORT-GAP — the P10/P50/P90 forecast + confidence% + per-leg risk tag has
//  NO model endpoint. The desc proposes intermodal.predictEta(input:{shipmentId})
//  → {p10,p50,p90,confidencePct,perSegment[{leg,etaIso,confidencePct,riskTag}]}
//  but it does not exist on the router (no p10/p50/p90/confidence column or
//  procedure anywhere in intermodal.ts). Per the OATH we DO NOT fabricate the
//  percentile window or the confidence/risk pills — the confidence band and
//  the per-leg risk pills render a real empty state until predictEta ships.
//  Segment ETAs that DO exist (arrivedAt actual / departedAt) are plotted.
//

import SwiftUI

struct RailETAPredictionScreen: View {
    let theme: Theme.Palette
    /// Intermodal shipment the forecast is computed for. Defaults to 0 so the
    /// top-level struct stays single-required-param (`theme`) per the build
    /// contract; the real router id is injected by the Shipments → ETA route.
    var shipmentId: Int = 0
    /// Display reference shown in the eyebrow / ID row. Defaults to the canon
    /// shipment from the wireframe (RAIL-260522-3C7B0).
    var shipmentRef: String = "RAIL-260522-3C7B0"

    var body: some View {
        Shell(theme: theme) {
            RailETAPredictionBody(shipmentId: shipmentId, shipmentRef: shipmentRef)
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

// MARK: - Data shapes (verified · intermodal.ts + drizzle/schema.ts)

private struct IMSegment643: Decodable, Identifiable {
    let id: Int
    let legNumber: Int?
    let mode: String?
    let originDescription: String?
    let destinationDescription: String?
    let status: String?
    let departedAt: String?
    let arrivedAt: String?
    let estimatedHours: String?
    let actualHours: String?
}

private struct IMTracking643: Decodable {
    let segments: [IMSegment643]
    let currentMode: String?
    let activeSegmentId: Int?
}

private struct IMDetail643: Decodable {
    let intermodalNumber: String?
    let status: String?
    let originDescription: String?
    let destinationDescription: String?
    let segments: [IMSegment643]?
}

// MARK: - Body

private struct RailETAPredictionBody: View {
    let shipmentId: Int
    let shipmentRef: String

    @Environment(\.palette) private var palette

    @State private var tracking: IMTracking643? = nil
    @State private var detail: IMDetail643? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Ordered, de-duplicated segment set: prefer the detail's full ordered
    // list, fall back to the tracking projection.
    private var segments: [IMSegment643] {
        let raw = (detail?.segments ?? tracking?.segments ?? [])
        return raw.sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) }
    }

    private var activeSegmentId: Int? { tracking?.activeSegmentId }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline().padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    routeHero
                    confidenceBand
                    perSegmentLedger
                    modelContext
                    ctaRow
                    Color.clear.frame(height: 8)
                }
                .padding(.top, Space.s4)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (✦ RAIL ENGINEER · ETA FORECAST … LIVE)

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · ETA FORECAST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("LIVE")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (back chevron · ETA prediction · CONF · id)

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("ETA prediction")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("CONF \(confidenceText)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(shipmentRef)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(.top, Space.s4)
    }

    /// No predictEta model → no confidence number to show. Renders "—" until
    /// the forecast endpoint ships (PORT-GAP) rather than the SVG's mock 82%.
    private var confidenceText: String { "—" }

    // MARK: - HERO · map canvas route panel

    private var routeHero: some View {
        RouteCanvas643(
            originLabel: originLabel,
            interchangeLabel: interchangeLabel,
            destinationLabel: destinationLabel,
            etaChip: etaChipText,
            livePositionFraction: liveFraction
        )
        .frame(height: 146)
    }

    private var originLabel: String {
        segments.first?.originDescription ?? detail?.originDescription ?? "Origin"
    }

    private var destinationLabel: String {
        segments.last?.destinationDescription ?? detail?.destinationDescription ?? "Destination"
    }

    /// The interchange = the boundary between the first and second leg (the
    /// real transfer node). nil when there is only one leg.
    private var interchangeLabel: String? {
        guard segments.count >= 2 else { return nil }
        return segments.first?.destinationDescription
    }

    /// ETA callout: the predicted/actual arrival of the FINAL leg if present.
    private var etaChipText: String {
        if let last = segments.last,
           let eta = last.arrivedAt ?? last.departedAt,
           let pretty = Self.prettyClock(eta) {
            return "ETA \(pretty)"
        }
        return "ETA pending"
    }

    /// Live-car position as a fraction (0…1) along the arc, derived from how
    /// many legs are done vs. total. No fabricated GPS — this is purely the
    /// completed-leg ratio against the real segment set.
    private var liveFraction: Double {
        let total = segments.count
        guard total > 0 else { return 0 }
        let done = segments.filter { ($0.status ?? "").lowercased() == "completed" }.count
        // Place the car mid-way through the active leg when one is in transit.
        let hasActive = segments.contains { ($0.status ?? "").lowercased() == "in_transit" }
        let base = Double(done) / Double(total)
        let step = 1.0 / Double(total)
        return min(1.0, hasActive ? base + step * 0.5 : base)
    }

    // MARK: - CONFIDENCE interval (PORT-GAP — no predictEta model)

    private var confidenceBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ARRIVAL WINDOW · P10 · P50 · P90")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("forecast")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            // PORT-GAP: the P10/P50/P90 percentile window + confidence% has no
            // model endpoint (proposed intermodal.predictEta does not exist on
            // the router). We render a real empty state instead of fabricating
            // a probability interval.
            EusoEmptyState(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "Forecast window unavailable",
                subtitle: "The P10·P50·P90 arrival window and confidence score require the ETA model (predictEta), which is not yet wired on this carrier.",
                comingSoon: true
            )
            .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - PER-SEGMENT FORECAST ledger

    private var perSegmentLedger: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("PER-SEGMENT FORECAST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("predictEta")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            if loading {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 64)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
                .padding(Space.s4)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else if let err = loadError {
                LedgerErrorCard(message: err)
            } else if segments.isEmpty {
                EusoEmptyState(
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "No segments",
                    subtitle: "Per-leg forecast appears once the intermodal route has booked segments."
                )
                .padding(Space.s4)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                        segmentRow(seg)
                        if idx < segments.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .padding(.vertical, Space.s2)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func segmentRow(_ seg: IMSegment643) -> some View {
        let state = SegmentState.resolve(status: seg.status, isActive: seg.id == activeSegmentId)
        HStack(spacing: Space.s3) {
            // Glyph chip — colored by state.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(state.color.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: state.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(state.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(legName(seg))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(legSubtitle(seg, state: state))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(state.tag)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(state.color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(state.color.opacity(0.16)))
                Text(legClock(seg))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func legName(_ seg: IMSegment643) -> String {
        let o = seg.originDescription
        let d = seg.destinationDescription
        switch (o, d) {
        case let (.some(o), .some(d)): return "\(o) → \(d)"
        case let (.some(o), .none):    return o
        case let (.none, .some(d)):    return "→ \(d)"
        default:
            let leg = seg.legNumber.map { "Leg \($0)" } ?? "Segment"
            let mode = seg.mode.map { " · \($0.capitalized)" } ?? ""
            return leg + mode
        }
    }

    private func legSubtitle(_ seg: IMSegment643, state: SegmentState) -> String {
        // Build from the real columns only — mode + actual departure/arrival.
        var parts: [String] = []
        if let m = seg.mode { parts.append(m.lowercased()) }
        if let dep = seg.departedAt, let p = Self.prettyClock(dep), state == .done {
            parts.append("departed \(p) · actual")
        } else if state == .live {
            parts.append("car mid-leg")
        } else if let est = seg.estimatedHours, let h = Double(est) {
            parts.append(String(format: "est %.0fh", h))
        }
        // PORT-GAP: per-leg confidence% lives on predictEta (absent) — omitted.
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func legClock(_ seg: IMSegment643) -> String {
        if let arr = seg.arrivedAt, let p = Self.prettyClock(arr) { return p }
        if let dep = seg.departedAt, let p = Self.prettyClock(dep) { return p }
        return "pending"
    }

    // MARK: - Model context (real, derived from tracking)

    private var modelContext: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("MODEL · ESang ETA v2")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(modelStatusText)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Inputs: live AAR car events · interchange dwell · Cajon Sub weather")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// No predictEta → no refit timestamp from the model. Reflect the live
    /// tracking mode instead, or "model offline" when the forecast is absent.
    private var modelStatusText: String {
        if let m = tracking?.currentMode { return "live · \(m.lowercased())" }
        return "model offline"
    }

    // MARK: - CTA row (Share ETA · Timeline)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Share ETA", action: { /* portal.createShareToken — UNVERIFIED on router; no-op until wired */ })
            Button(action: { /* navigates to 565 Container Timeline via nav controller */ }) {
                Text("Timeline")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 148)
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct TrackIn: Encodable { let intermodalShipmentId: Int }
        struct DetailIn: Encodable { let id: Int }
        do {
            async let track: IMTracking643 = EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking", input: TrackIn(intermodalShipmentId: shipmentId))
            async let det: IMDetail643 = EusoTripAPI.shared.query(
                "intermodal.getIntermodalShipmentDetail", input: DetailIn(id: shipmentId))
            let (t, d) = try await (track, det)
            self.tracking = t
            self.detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Clock formatting (real ISO → "May 22 14:30")

    private static func prettyClock(_ iso: String) -> String? {
        let parsers: [ISO8601DateFormatter] = {
            let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
            return [a, b]
        }()
        var date: Date? = nil
        for p in parsers { if let d = p.date(from: iso) { date = d; break } }
        if date == nil {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            date = f.date(from: iso)
        }
        guard let d = date else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d HH:mm"
        return out.string(from: d)
    }
}

// MARK: - Segment lifecycle state

private enum SegmentState: Equatable {
    case done, live, upcoming

    static func resolve(status: String?, isActive: Bool) -> SegmentState {
        let s = (status ?? "").lowercased()
        if s == "completed" { return .done }
        if isActive || s == "in_transit" { return .live }
        return .upcoming
    }

    var color: Color {
        switch self {
        case .done:     return Brand.success
        case .live:     return Brand.blue
        case .upcoming: return Brand.warning
        }
    }

    var icon: String {
        switch self {
        case .done:     return "checkmark"
        case .live:     return "clock"
        case .upcoming: return "triangle"
        }
    }

    /// Live state. The SVG's "LOW/MED/HIGH RISK" risk-tag pills come from
    /// predictEta (absent) — until that ships we surface the real lifecycle
    /// state (DONE / LIVE / UPCOMING) instead of a fabricated risk grade.
    var tag: String {
        switch self {
        case .done:     return "DONE"
        case .live:     return "LIVE"
        case .upcoming: return "UPCOMING"
        }
    }
}

// MARK: - Ledger error card

private struct LedgerErrorCard: View {
    let message: String
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
            Spacer()
        }
        .padding(Space.s4)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - RouteCanvas643 (map-canvas route panel — Path/GeometryReader)
//
// Reproduces the SVG hero geometry: gridlines, a gradient route arc (a glow
// underlay + crisp stroke on top), origin/destination pins, an interchange
// node, the live car-position pin riding the arc, and the ETA callout chip.
// The arc is a quadratic-bezier chain matching the wireframe path; the live
// car is placed at `livePositionFraction` along that chain.

private struct RouteCanvas643: View {
    let originLabel: String
    let interchangeLabel: String?
    let destinationLabel: String
    let etaChip: String
    let livePositionFraction: Double

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Control points scaled from the 400×146 SVG canvas.
            let sx: (CGFloat) -> CGFloat = { $0 / 400 * w }
            let sy: (CGFloat) -> CGFloat = { $0 / 146 * h }

            let p0 = CGPoint(x: sx(40),  y: sy(108))   // origin
            let c1 = CGPoint(x: sx(160), y: sy(30))
            let p1 = CGPoint(x: sx(240), y: sy(70))    // interchange node
            let c2 = CGPoint(x: sx(320), y: sy(110))   // reflected control (T)
            let p2 = CGPoint(x: sx(360), y: sy(52))    // destination

            let arc = Path { p in
                p.move(to: p0)
                p.addQuadCurve(to: p1, control: c1)
                p.addQuadCurve(to: p2, control: c2)
            }

            let liveT = max(0, min(1, livePositionFraction))
            let livePoint = Self.pointOnArc(p0: p0, c1: c1, p1: p1, c2: c2, p2: p2, t: liveT)

            ZStack {
                // Card surface
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(palette.borderFaint))

                // Faint gridlines
                Path { p in
                    p.move(to: CGPoint(x: 0, y: sy(48)));  p.addLine(to: CGPoint(x: w, y: sy(48)))
                    p.move(to: CGPoint(x: 0, y: sy(96)));  p.addLine(to: CGPoint(x: w, y: sy(96)))
                    p.move(to: CGPoint(x: sx(100), y: 0)); p.addLine(to: CGPoint(x: sx(100), y: h))
                    p.move(to: CGPoint(x: sx(200), y: 0)); p.addLine(to: CGPoint(x: sx(200), y: h))
                    p.move(to: CGPoint(x: sx(300), y: 0)); p.addLine(to: CGPoint(x: sx(300), y: h))
                }
                .stroke(palette.textPrimary.opacity(0.05), lineWidth: 1)

                // Route arc — glow underlay then crisp gradient stroke
                arc.stroke(Brand.blue.opacity(0.18),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round))
                arc.stroke(LinearGradient.primary,
                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

                // Origin pin
                pin(at: p0, fill: Brand.blue, ring: true)
                label(originLabel, at: CGPoint(x: p0.x, y: p0.y + sy(22)), color: palette.textPrimary, bold: true)

                // Interchange node (only when a real interchange exists)
                if interchangeLabel != nil {
                    Circle().fill(Color.white).frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Brand.escort, lineWidth: 2.5))
                        .position(p1)
                    if let il = interchangeLabel {
                        label(il, at: CGPoint(x: p1.x, y: p1.y + sy(22)),
                              color: Brand.escort.opacity(0.85), bold: false)
                    }
                }

                // Destination pin
                pin(at: p2, fill: Brand.magenta, ring: true)
                label(destinationLabel, at: CGPoint(x: p2.x, y: p2.y - sy(12)),
                      color: palette.textPrimary, bold: true)

                // Live car-position pin on the arc
                Circle().fill(Brand.blue.opacity(0.18)).frame(width: 22, height: 22)
                    .position(livePoint)
                Circle().fill(LinearGradient.diagonal).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .position(livePoint)

                // ETA callout chip (top center)
                Text(etaChip)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color(hex: 0x3A4150)))
                    .position(x: w / 2, y: sy(23))
            }
        }
    }

    @ViewBuilder
    private func pin(at p: CGPoint, fill: Color, ring: Bool) -> some View {
        Circle().fill(fill).frame(width: 12, height: 12)
            .overlay(ring ? Circle().strokeBorder(Color.white, lineWidth: 2) : nil)
            .position(p)
    }

    @ViewBuilder
    private func label(_ text: String, at p: CGPoint, color: Color, bold: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: bold ? .bold : .regular))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .position(p)
    }

    /// Evaluate the two-quad bezier chain at parameter t∈[0,1]. First half of
    /// t maps to the first quad (p0→p1 via c1), second half to the second
    /// quad (p1→p2 via c2).
    static func pointOnArc(p0: CGPoint, c1: CGPoint, p1: CGPoint,
                           c2: CGPoint, p2: CGPoint, t: Double) -> CGPoint {
        if t <= 0.5 {
            let lt = t / 0.5
            return quad(p0, c1, p1, CGFloat(lt))
        } else {
            let lt = (t - 0.5) / 0.5
            return quad(p1, c2, p2, CGFloat(lt))
        }
    }

    private static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let x = mt * mt * a.x + 2 * mt * t * c.x + t * t * b.x
        let y = mt * mt * a.y + 2 * mt * t * c.y + t * t * b.y
        return CGPoint(x: x, y: y)
    }
}

#Preview("643 · Rail ETA Prediction · Night") {
    RailETAPredictionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("643 · Rail ETA Prediction · Light") {
    RailETAPredictionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
