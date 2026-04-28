//
//  212_ShipperControlTower.swift
//  EusoTrip 2027 UI — brick 212 (shipper · control tower)
//
//  Multi-modal supply-chain visibility — every active load across
//  truck / rail / vessel in one glanceable screen. Mirrors the web
//  `/control-tower` route (`ControlTower.tsx`) and is the iOS-side
//  flagship visibility surface for the Shipper role.
//
//  Cohort B day-1 — fully dynamic. No fixtures.
//
//    • Header KPIs → `controlTower.overview` (truck + vessel + rail
//      mode counts) + `controlTower.exceptions.totalExceptions`.
//      MCP-verified at `frontend/server/routers/controlTower.ts:16`.
//    • Per-mode card grid → mode counts from overview envelope.
//    • Exceptions list → `controlTower.exceptions(limit:50)`. Late
//      deliveries (truck `deliveryDate <= NOW`) + late vessel
//      arrivals (`eta <= NOW`) merged with mode discriminator.
//    • Recent activity → `controlTower.recentActivity(limit:30)`.
//
//  Design doctrine (per Driver Figma 010-103, applied here):
//    §1   LinearGradient.diagonal on the gradient hero KPI tile,
//         tier badges, mode icons. NO flat brand fills.
//    §2   `CTAButton` recipe (0.12s easeOut press scale + iridescent
//         hue-shift) on every primary action.
//    §4   Tokenized Space/Radius/EType throughout.
//    §5   Palette semantic only. Severity → Brand.success / .warning
//         / .danger.
//    §7   Ternary ShapeStyle wrapped in `AnyShapeStyle`.
//    §10  Dark + Light previews compile in isolation under the
//         empty-envelope path so the screen never crashes a preview
//         canvas.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ControlTowerStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded(
            overview: ControlTowerAPI.Overview,
            exceptions: ControlTowerAPI.ExceptionsResponse,
            activity: [ControlTowerAPI.ActivityRow]
        )
    }

    @Published private(set) var state: LoadState = .loading

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let o   = api.controlTower.overview()
            async let exc = api.controlTower.exceptions(limit: 50)
            async let act = api.controlTower.recentActivity(limit: 30)
            let (overview, exceptions, activity) = try await (o, exc, act)

            // Empty: no active anything AND no exceptions AND no
            // activity. Surfaces the EusoEmptyState rather than a
            // KPI grid full of zeros so a brand-new shipper sees a
            // clear "post your first load" affordance.
            let allZero =
                overview.total.active == 0 &&
                overview.total.inTransit == 0 &&
                exceptions.totalExceptions == 0 &&
                activity.isEmpty
            if allZero {
                state = .empty
            } else {
                state = .loaded(overview: overview, exceptions: exceptions, activity: activity)
            }
        } catch {
            state = .error("Couldn't reach control tower service.")
        }
    }
}

// MARK: - Screen root

struct ShipperControlTower: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ControlTowerStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: storeStateKey
        )
    }

    /// Stable string used as the animation key so SwiftUI re-runs
    /// the cross-fade only when the load state actually flips.
    private var storeStateKey: String {
        switch store.state {
        case .loading:        return "loading"
        case .empty:           return "empty"
        case .error:           return "error"
        case .loaded(let o, let e, let a):
            return "loaded-\(o.total.active)-\(o.total.inTransit)-\(e.totalExceptions)-\(a.count)"
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · CONTROL TOWER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Supply chain visibility")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Truck · rail · ocean — every load, every mode, real-time.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            loadingShell
        case .empty:
            EusoEmptyState(
                systemImage: "eye",
                title: "Nothing in flight yet",
                subtitle: "Once you post your first load, the control tower lights up with live mode counts, exceptions, and activity.",
                comingSoon: false
            )
        case .error(let msg):
            inlineError(msg) { Task { await store.refresh() } }
        case .loaded(let o, let e, let a):
            kpiGrid(overview: o, exceptionCount: e.totalExceptions)
            modeCardGrid(overview: o)
            exceptionsCard(e)
            activityCard(a)
        }
    }

    // MARK: KPI grid (4 hero tiles — Total Active / In Transit / Exceptions / Modes Active)

    private func kpiGrid(overview o: ControlTowerAPI.Overview, exceptionCount: Int) -> some View {
        let modesActive = [o.truck, o.vessel, o.rail].filter { ($0.active + $0.inTransit) > 0 }.count
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2),
                GridItem(.flexible(), spacing: Space.s2),
            ],
            spacing: Space.s2
        ) {
            kpiTile(
                icon: "dot.radiowaves.left.and.right",
                label: "TOTAL ACTIVE",
                value: "\(o.total.active)",
                tint: .gradient,
                pulse: o.total.active > 0
            )
            kpiTile(
                icon: "arrow.triangle.swap",
                label: "IN TRANSIT",
                value: "\(o.total.inTransit)",
                tint: .gradient,
                pulse: o.total.inTransit > 0
            )
            kpiTile(
                icon: "exclamationmark.triangle.fill",
                label: "EXCEPTIONS",
                value: "\(exceptionCount)",
                tint: exceptionCount > 0 ? .danger : .neutral,
                pulse: exceptionCount > 0
            )
            kpiTile(
                icon: "square.grid.3x3.fill",
                label: "MODES ACTIVE",
                value: "\(modesActive)",
                tint: .neutral,
                pulse: false
            )
        }
    }

    private enum TileTint { case gradient, danger, neutral }

    private func kpiTile(icon: String, label: String, value: String, tint: TileTint, pulse: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(iconStyle(for: tint))
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if pulse {
                    Circle()
                        .fill(pulseDotColor(for: tint))
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 1 : 0)
                        .modifier(PulseModifier(active: pulse, reduceMotion: reduceMotion))
                }
            }
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(valueStyle(for: tint))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileBackground(for: tint))
        .overlay(tileBorder(for: tint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private func iconStyle(for tint: TileTint) -> some ShapeStyle {
        switch tint {
        case .gradient: AnyShapeStyle(LinearGradient.diagonal)
        case .danger:   AnyShapeStyle(Brand.danger)
        case .neutral:  AnyShapeStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func valueStyle(for tint: TileTint) -> some ShapeStyle {
        switch tint {
        case .gradient: AnyShapeStyle(LinearGradient.diagonal)
        case .danger:   AnyShapeStyle(Brand.danger)
        case .neutral:  AnyShapeStyle(palette.textPrimary)
        }
    }

    private func pulseDotColor(for tint: TileTint) -> Color {
        switch tint {
        case .gradient: return Brand.gradientEnd
        case .danger:   return Brand.danger
        case .neutral:  return palette.textTertiary
        }
    }

    @ViewBuilder
    private func tileBackground(for tint: TileTint) -> some View {
        switch tint {
        case .gradient:
            LinearGradient(
                colors: [Brand.blue.opacity(0.18), Brand.magenta.opacity(0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .danger:
            LinearGradient(
                colors: [Brand.danger.opacity(0.20), Brand.danger.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .neutral:
            palette.bgCard
        }
    }

    @ViewBuilder
    private func tileBorder(for tint: TileTint) -> some View {
        switch tint {
        case .gradient:
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
        case .danger:
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1)
        case .neutral:
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        }
    }

    // MARK: Mode cards (truck / ocean / rail)

    private func modeCardGrid(overview o: ControlTowerAPI.Overview) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionEyebrow("BY MODE")
            VStack(spacing: Space.s2) {
                modeCard(icon: "truck.box.fill",      label: "Truck",  counts: o.truck)
                modeCard(icon: "ferry.fill",          label: "Ocean",  counts: o.vessel)
                modeCard(icon: "tram.fill",           label: "Rail",   counts: o.rail)
            }
        }
    }

    private func modeCard(icon: String, label: String, counts: ControlTowerAPI.ModeCounts) -> some View {
        let total = counts.active + counts.inTransit + (counts.delivered ?? 0)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(total) total")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCardSoft))
                }
                HStack(spacing: 12) {
                    countCell(value: counts.active,    label: "ACTIVE",    color: Brand.info)
                    countCell(value: counts.inTransit, label: "IN TRANSIT", color: Brand.success)
                    if let d = counts.delivered {
                        countCell(value: d, label: "DELIVERED", color: palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func countCell(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Exceptions card (red-flagged late loads + vessels)

    private func exceptionsCard(_ e: ControlTowerAPI.ExceptionsResponse) -> some View {
        let merged = e.truckExceptions + e.vesselExceptions
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(merged.isEmpty ? palette.textTertiary : Brand.danger)
                Text("EXCEPTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !merged.isEmpty {
                    Text("\(merged.count)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.danger.opacity(0.15)))
                }
            }
            if merged.isEmpty {
                Text("No exceptions across modes.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s4)
            } else {
                VStack(spacing: 6) {
                    ForEach(merged.prefix(8)) { ex in exceptionRow(ex) }
                }
                if merged.count > 8 {
                    Text("\(merged.count - 8) more · pull to refresh for the latest")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(merged.isEmpty
                              ? palette.borderFaint
                              : Brand.danger.opacity(0.4),
                              lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func exceptionRow(_ ex: ControlTowerAPI.ExceptionRow) -> some View {
        let modeIcon: String = (ex.mode == "truck") ? "truck.box.fill" : "ferry.fill"
        let title: String = {
            switch ex.mode {
            case "truck":
                let p = ex.pickupLocation
                let d = ex.deliveryLocation
                let lhs = [p?.city, p?.state].compactMap { $0 }.joined(separator: ", ")
                let rhs = [d?.city, d?.state].compactMap { $0 }.joined(separator: ", ")
                if lhs.isEmpty || rhs.isEmpty { return ex.loadNumber ?? "Truck #\(ex.rowId)" }
                return "\(lhs) → \(rhs)"
            case "vessel":
                return ex.bookingNumber ?? "Booking #\(ex.rowId)"
            default:
                return "Exception #\(ex.rowId)"
            }
        }()
        let typeLabel = ex.exceptionType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return HStack(spacing: Space.s2) {
            Image(systemName: modeIcon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 24)
            Text(title)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(typeLabel)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Brand.danger))
        }
        .padding(Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Brand.danger.opacity(0.08))
        )
    }

    // MARK: Activity card (recent updates across modes)

    private func activityCard(_ rows: [ControlTowerAPI.ActivityRow]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RECENT ACTIVITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(rows.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            if rows.isEmpty {
                Text("No recent updates.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(15).enumerated()), id: \.element.id) { idx, r in
                        activityRow(r)
                        if idx < min(rows.count, 15) - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func activityRow(_ r: ControlTowerAPI.ActivityRow) -> some View {
        let icon = r.mode == "truck" ? "truck.box.fill" : "ferry.fill"
        let status = (r.status ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return HStack(spacing: Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 20)
            Text(r.label ?? "—")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.s2)
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 0.75))
            }
        }
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Loading + error shells

    private var loadingShell: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 80)
            }
        }
    }

    private func inlineError(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Control tower offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func sectionEyebrow(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.9)
            .foregroundStyle(palette.textTertiary)
    }
}

// MARK: - Pulse modifier (active KPI tile dot)

private struct PulseModifier: ViewModifier {
    let active: Bool
    let reduceMotion: Bool

    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.6
                }
            }
    }
}

// MARK: - Previews

#Preview("212 · Shipper Control Tower · Night") {
    ShipperControlTower()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("212 · Shipper Control Tower · Afternoon") {
    ShipperControlTower()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
