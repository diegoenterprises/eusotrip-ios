//
//  585_RailEquipmentPositions.swift
//  EusoTrip — Rail Engineer · Equipment Positions (real-time railcar positions).
//
//  Visual identity: route-arc canvas hero (Bézier route curve origin→current→dest
//  with live railcar pucks at their interpolated positions along the arc).
//  Matches the Live Tracking (560) design language — route as a visual object,
//  positions as glyphs ON the route, not just a text list.
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

// MARK: - Data shapes

private struct PositionsSummary585: Decodable {
    let inMotionCount: Int?
    let atYardCount: Int?
    let badOrderCount: Int?
    let totalRailcars: Int?
    let avgSpeedMph: Int?
    let routeLabel: String?
    let originLabel: String?
    let destinationLabel: String?
    let progressFraction: Double?
}

private struct RailcarPosition585: Decodable, Identifiable {
    var id: String { carNumber ?? "\(UUID())" }
    let carNumber: String?
    let location: String?
    let containerNumber: String?
    let status: String?
    let speedMph: Int?
    let dwellHours: Int?
    let progressFraction: Double?
}

private struct ContainerTracking585: Decodable {
    let containerNumber: String?
    let lastAEILocation: String?
    let lastReadMinutesAgo: Int?
    let additionalUnits: Int?
    let iso6346Verified: Bool?
}

private struct RailIdIn585: Encodable { let railId: String }

// MARK: - Body

private struct RailEquipmentPositionsBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var summary: PositionsSummary585? = nil
    @State private var positions: [RailcarPosition585] = []
    @State private var container: ContainerTracking585? = nil

    // MARK: Derived

    private var inMotionCount: Int { summary?.inMotionCount ?? 0 }
    private var atYardCount: Int   { summary?.atYardCount   ?? 0 }
    private var badOrderCount: Int { summary?.badOrderCount ?? 0 }
    private var totalRailcars: Int { summary?.totalRailcars ?? 0 }
    private var avgSpeedLabel: String {
        guard let s = summary?.avgSpeedMph, s > 0 else { return "—" }
        return "\(s) mph"
    }
    private var routeLabel: String   { summary?.routeLabel      ?? "BNSF Transcon" }
    private var originLabel: String  { summary?.originLabel     ?? "Chicago, IL" }
    private var destLabel: String    { summary?.destinationLabel ?? "Los Angeles, CA" }
    private var routeProgress: Double { summary?.progressFraction ?? 0.42 }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                routeCanvas
                kpiStrip
                positionsSection
                containerStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
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
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Route arc canvas (hero)

    private var routeCanvas: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pad: CGFloat = 32
            let midY = h * 0.52

            // Arc control point (Bézier gives the railway curve shape)
            let cp = CGPoint(x: w / 2, y: midY - 38)
            let startPt = CGPoint(x: pad, y: midY)
            let endPt   = CGPoint(x: w - pad, y: midY)

            // Background track (dashed gray — full route)
            var trackPath = Path()
            trackPath.move(to: startPt)
            trackPath.addQuadCurve(to: endPt, control: cp)
            ctx.stroke(trackPath, with: .color(Color(red: 0.55, green: 0.60, blue: 0.68).opacity(0.35)),
                       style: StrokeStyle(lineWidth: 3, dash: [6, 5]))

            // Completed portion (solid primary gradient, up to routeProgress)
            let completedEnd = arcPoint(t: routeProgress, start: startPt, end: endPt, control: cp)
            var completedPath = Path()
            completedPath.move(to: startPt)
            // Approximate with multiple small segments
            let steps = 40
            for i in 1...steps {
                let t = routeProgress * Double(i) / Double(steps)
                let pt = arcPoint(t: t, start: startPt, end: endPt, control: cp)
                completedPath.addLine(to: pt)
            }
            ctx.stroke(completedPath, with: .linearGradient(
                Gradient(colors: [Color(red: 0.22, green: 0.55, blue: 1.0), Color(red: 0.72, green: 0.28, blue: 1.0)]),
                startPoint: CGPoint(x: pad, y: midY), endPoint: completedEnd),
                       style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Origin pin (filled gradient circle)
            let originRect = CGRect(x: startPt.x - 8, y: startPt.y - 8, width: 16, height: 16)
            ctx.fill(Path(ellipseIn: originRect), with: .linearGradient(
                Gradient(colors: [Color(red: 0.22, green: 0.55, blue: 1.0), Color(red: 0.72, green: 0.28, blue: 1.0)]),
                startPoint: CGPoint(x: originRect.minX, y: originRect.midY),
                endPoint: CGPoint(x: originRect.maxX, y: originRect.midY)))

            // Destination pin (hollow ring)
            let destRect = CGRect(x: endPt.x - 6, y: endPt.y - 6, width: 12, height: 12)
            ctx.stroke(Path(ellipseIn: destRect),
                       with: .color(Color(red: 0.55, green: 0.60, blue: 0.68).opacity(0.6)),
                       lineWidth: 2)

            // Live position pucks (in-motion railcars)
            let motionCars = positions.filter { ($0.status ?? "").lowercased() == "in_motion" }
            for car in motionCars.prefix(5) {
                let t = car.progressFraction ?? routeProgress
                let pt = arcPoint(t: t, start: startPt, end: endPt, control: cp)
                // Halo
                let haloRect = CGRect(x: pt.x - 12, y: pt.y - 12, width: 24, height: 24)
                ctx.fill(Path(ellipseIn: haloRect), with: .color(Color(red: 0.72, green: 0.28, blue: 1.0).opacity(0.18)))
                // Puck
                let puckRect = CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)
                ctx.fill(Path(ellipseIn: puckRect), with: .color(Color.white))
                // Inner dot
                let dotRect = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dotRect), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.22, green: 0.55, blue: 1.0), Color(red: 0.72, green: 0.28, blue: 1.0)]),
                    startPoint: CGPoint(x: dotRect.minX, y: dotRect.midY),
                    endPoint: CGPoint(x: dotRect.maxX, y: dotRect.midY)))
            }

            // Origin label
            ctx.draw(Text(originLabel).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68)),
                at: CGPoint(x: startPt.x, y: midY + 20), anchor: .leading)
            // Destination label
            ctx.draw(Text(destLabel).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68)),
                at: CGPoint(x: endPt.x, y: midY + 20), anchor: .trailing)
            // Route label centered
            ctx.draw(Text(routeLabel).font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68)),
                at: CGPoint(x: w / 2, y: 16), anchor: .center)
        }
        .frame(height: 110)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        )
    }

    // Quadratic Bézier interpolation
    private func arcPoint(t: Double, start: CGPoint, end: CGPoint, control: CGPoint) -> CGPoint {
        let t = max(0, min(1, t))
        let x = (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * control.x + t * t * end.x
        let y = (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "IN MOTION",  value: "\(inMotionCount)",  gradientNumeral: inMotionCount > 0)
            MetricTile(label: "AT YARD",    value: "\(atYardCount)")
            MetricTile(label: "BAD-ORDER",  value: "\(badOrderCount)",  accent: badOrderCount > 0 ? Brand.danger : palette.textPrimary)
        }
    }

    // MARK: Positions list

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("POSITIONS")
                    .font(.system(size: 9, weight: .black)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(avgSpeedLabel)
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(positions.enumerated()), id: \.offset) { idx, pos in
                    if idx > 0 { Divider().overlay(Color.black.opacity(0.06)).padding(.horizontal, Space.s4) }
                    positionRow(pos)
                }
            }
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
        }
    }

    @ViewBuilder
    private func positionRow(_ pos: RailcarPosition585) -> some View {
        let (pillLabel, pillColor) = positionPillInfo(pos.status)
        let locationLine = [pos.location, pos.containerNumber].compactMap { $0 }.joined(separator: " · ")
        let rightValue   = positionRightValue(pos)
        let inMotion = (pos.status ?? "").lowercased() == "in_motion"

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(pillColor.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: inMotion ? "train.side.front.car" : "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(pillColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pos.carNumber ?? "—")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                if !locationLine.isEmpty {
                    Text(locationLine)
                        .font(.system(size: 11).monospaced()).kerning(0.4).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(pillColor.opacity(0.14))).foregroundStyle(pillColor)
                Text(rightValue)
                    .font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
    }

    // MARK: Container strip

    private var containerStrip: some View {
        let cNum  = container?.containerNumber ?? "—"
        let loc   = container?.lastAEILocation ?? "—"
        let mins  = container?.lastReadMinutesAgo ?? 0
        let extra = container?.additionalUnits ?? 0
        let isoOk = container?.iso6346Verified ?? false

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONTAINER · AEI")
                    .font(.system(size: 9, weight: .black)).kerning(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ISO 6346 \(isoOk ? "✓" : "pending")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isoOk ? Brand.success : Brand.warning)
            }
            Text("\(cNum) · last read \(loc) · \(mins) min ago")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            if extra > 0 {
                Text("+\(extra) more units off-screen")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Refresh positions", action: { Task { await loadAll() } }, leadingIcon: "arrow.triangle.2.circlepath")
            Button("View waybill") {}
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(palette.bgCard)
                    .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1)))
        }
    }

    // MARK: Helpers

    private func positionPillInfo(_ status: String?) -> (String, Color) {
        switch (status ?? "").lowercased() {
        case "in_motion":  return ("IN MOTION", Brand.success)
        case "at_ramp":    return ("AT RAMP",   Brand.blue)
        case "at_yard":    return ("AT YARD",   Brand.warning)
        case "bad_order":  return ("BAD ORDER", Brand.danger)
        default:           return ("—",         Brand.info)
        }
    }

    private func positionRightValue(_ pos: RailcarPosition585) -> String {
        let status = (pos.status ?? "").lowercased()
        if status == "in_motion", let s = pos.speedMph { return "\(s) mph" }
        if let h = pos.dwellHours { return "\(h)h dwell" }
        return "—"
    }

    // MARK: Data loading

    private func loadAll() async {
        async let summaryTask: PositionsSummary585 = EusoTripAPI.shared.query(
            "tracking.getRealtimePositions", input: RailIdIn585(railId: railId))
        async let positionsTask: [RailcarPosition585] = EusoTripAPI.shared.query(
            "railShipments.getRailcars", input: RailIdIn585(railId: railId))
        async let containerTask: ContainerTracking585 = EusoTripAPI.shared.query(
            "railShipments.trackIntermodalContainer", input: RailIdIn585(railId: railId))
        summary   = try? await summaryTask
        positions = (try? await positionsTask) ?? []
        container = try? await containerTask
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
