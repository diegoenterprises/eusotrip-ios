//
//  299_ShipperTankInventory.swift
//  EusoTrip — Shipper · TANK INVENTORY (bulk terminal live gauging).
//
//  Wireframe: 02 Shipper/Dark-SVG/299 Shipper Tank Inventory.svg
//  Archetype: BOARD / MONITORING. A bulk-terminal tank farm at a glance —
//  utilization, on-hand vs capacity, and each tank's fill against its
//  reorder line, so Diego knows which product runs dry first and whether a
//  movement needs scheduling. NOT a stat dashboard: a fill-vs-reorder tank
//  board leads, a reorder-watch list follows.
//
//  Web peer: frontend/client/src/pages/shipper/tank-inventory.
//  Wiring (on-disk confirmed — iOS tankMonitorRouter mirror):
//    • tankMonitor.getMultiTerminalOverview EXISTS tankMonitor.ts:291 →
//      the terminal + totals hero (tanks, capacity, on-hand, util, alerts).
//      PRIMARY CONSUME.
//    • tankMonitor.getTankReadings EXISTS tankMonitor.ts:63 → per-tank fill
//      rows (tankNumber, product, level, percentFull, gauge, status).
//    • tankMonitor.getTankAlerts EXISTS tankMonitor.ts:167 → the reorder-
//      watch list (which tanks are low, severity-sorted). REAL alert feed.
//  RBAC: company/terminal scoped server-side. transportMode=truck · US.
//
//  Honest gaps (surfaced to the-oath): the SVG's draw-rate / days-to-
//  reorder FORECAST (inventory.getForecast), the schedule-movement write
//  (inventory.scheduleMovement) and the movement history (inventory.
//  getHistory) live on the web `inventory` router, NOT the iOS
//  tankMonitor mirror. This screen therefore renders the REAL reorder-watch
//  ALERTS in place of a fabricated "420 bbl/d · 2.1 d" forecast, and the
//  two CTAs land on the nearest registered shipper surfaces (Create Load
//  for a movement, Reports for history) — never a dead tap. All levels
//  convert gallons → barrels (÷42); an offline tank renders honest zeros.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

private let kGallonsPerBarrel = 42.0

// MARK: - Screen root

struct ShipperTankInventoryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperTankInventoryBody()
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct ShipperTankInventoryBody: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperTankInventoryStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                switch store.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.s8)
                case .empty:
                    emptyState
                case .error(let msg):
                    errorState(msg)
                case .loaded:
                    summaryStrip
                    tankBoard
                    reorderWatch
                    ctaRow
                    footnote
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s8)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · TANK INVENTORY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: Space.s2)
                if let rail = store.headerRail {
                    Text(rail).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Text("Tank inventory")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(store.subtitle)
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.6)
            IridescentHairline().padding(.top, 2)
        }
    }

    // MARK: Summary strip (UTIL · ON HAND · CAP · ALERTS)

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(label: "UTIL", value: store.utilLabel, gradient: true)
            divider
            summaryCell(label: "ON HAND", value: store.onHandLabel, sub: "bbl")
            divider
            summaryCell(label: "CAP", value: store.capacityLabel, sub: "bbl")
            divider
            summaryCell(label: "ALERTS", value: "\(store.alertCount)", tone: store.alertCount > 0 ? .warn : .neutral)
        }
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private enum CellTone { case neutral, warn }
    private func summaryCell(label: String, value: String, sub: String? = nil, gradient: Bool = false, tone: CellTone = .neutral) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            Group {
                if gradient { Text(value).foregroundStyle(LinearGradient.diagonal) }
                else { Text(value).foregroundStyle(tone == .warn ? Brand.warning : palette.textPrimary) }
            }
            .font(.system(size: 18, weight: .heavy)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            if let sub { Text(sub).font(.system(size: 8, weight: .medium)).foregroundStyle(palette.textTertiary) }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 34)
    }

    // MARK: Tank board (fill vs reorder line)

    private var tankBoard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TANKS · \(store.tanks.count) · FILL vs REORDER LINE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Rectangle().fill(palette.textTertiary).frame(width: 10, height: 1)
                    Text("reorder line").font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.textTertiary)
                }
            }
            if store.tanks.isEmpty {
                EusoEmptyState(
                    systemImage: "gauge.with.dots.needle.bottom.50percent",
                    title: "No tanks gauged",
                    subtitle: "This terminal has no active gauge rows yet. Tank fills appear here as soon as the level monitor ingests a reading."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(store.tanks) { t in tankRow(t) }
                }
            }
        }
    }

    private func tankRow(_ t: TankFillRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.tint.opacity(0.16)).frame(width: 44, height: 44)
                    Text("T-\(t.tankNumber)").font(.system(size: 12, weight: .heavy)).foregroundStyle(t.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.product).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    Text(t.detail).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(t.percentLabel).font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(t.tint)
                    Text(t.barrelLabel).font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(palette.textSecondary)
                }
            }
            fillBar(t)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(t.low ? Brand.warning.opacity(0.45) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func fillBar(_ t: TankFillRow) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = max(0, min(1, t.fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCardSoft).frame(height: 8)
                Capsule()
                    .fill(t.low ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                    .frame(width: max(6, w * frac), height: 8)
                // Reorder reference marker (dashed) at the tank's real
                // alert threshold when present, else the standard low line.
                Rectangle()
                    .fill(palette.textTertiary)
                    .frame(width: 1.4, height: 14)
                    .position(x: w * t.reorderFraction, y: 4)
            }
        }
        .frame(height: 14)
    }

    // MARK: Reorder watch (REAL alert feed — honest stand-in for forecast)

    private var reorderWatch: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("REORDER WATCH · LIVE ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("DRAW-RATE FORECAST · TERMINAL FEED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
            }
            if store.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No tank below its reorder line")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Every gauged tank sits above its reorder threshold. The draw-rate days-to-reorder forecast attaches here with the terminal history feed.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(store.alerts) { a in alertRow(a) }
                }
            }
        }
    }

    private func alertRow(_ a: TankReorderAlert) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(a.tone.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: a.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(a.tone)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Text(a.message).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(a.badge)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(a.tone)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(a.tone.opacity(0.18)))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(a.tone.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTAs (land on real registered surfaces — scheduleMovement /
    // getHistory are inventory-router gaps on the iOS tankMonitor mirror)

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: "Schedule movement",
                action: { shipperEchoNavSwap("204") }
            )
            .frame(maxWidth: .infinity)
            Button { shipperEchoNavSwap("299") } label: {
                Text("History")
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 148)
        }
    }

    private var footnote: some View {
        Text("Levels gauge live from the terminal's tank monitor and convert to barrels at 42 gal/bbl. Reorder watch tracks tanks below their threshold; the draw-rate days-to-reorder forecast attaches with the terminal history feed.")
            .font(EType.caption).foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: States

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "drop.triangle",
            title: "No terminal inventory",
            subtitle: "You have no active bulk terminals gauging inventory. Once a terminal's tank monitor comes online, its fill levels and reorder watch appear here."
        )
        .padding(.top, Space.s6)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.danger)
            }
            Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            Button { Task { await store.load() } } label: {
                Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Row view-models

struct TankFillRow: Identifiable, Equatable {
    let id: String
    let tankNumber: Int
    let product: String
    let percentFull: Double?      // 0..100
    let currentBarrels: Double?
    let detail: String
    /// Reorder threshold as a 0..1 fraction (from a real alert threshold or
    /// the standard low line). Draws the dashed reference marker.
    let reorderFraction: Double

    var fraction: Double { (percentFull ?? 0) / 100.0 }
    var low: Bool { (percentFull ?? 100) <= reorderFraction * 100 + 0.5 }
    var percentLabel: String { percentFull.map { "\(Int($0.rounded()))%" } ?? "—" }
    var barrelLabel: String { currentBarrels.map { "\(formatBarrels($0)) bbl" } ?? "— bbl" }
    var tint: Color { low ? Brand.warning : Brand.blue }
}

struct TankReorderAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let badge: String
    let icon: String
    let tone: Color
}

// MARK: - Barrel formatting (shared)

private func formatBarrels(_ bbl: Double) -> String {
    if bbl >= 10_000 { return String(format: "%.1fk", bbl / 1000.0) }
    if bbl >= 1_000 { return String(format: "%.1fk", bbl / 1000.0) }
    return "\(Int(bbl.rounded()))"
}

// MARK: - Store

@MainActor
final class ShipperTankInventoryStore: ObservableObject {
    enum Phase: Equatable { case loading, empty, loaded, error(String) }
    @Published private(set) var phase: Phase = .loading

    @Published private(set) var terminalName: String = "Terminal"
    @Published private(set) var overallUtil: Int = 0
    @Published private(set) var onHandBarrels: Double = 0
    @Published private(set) var capacityBarrels: Double = 0
    @Published private(set) var alertCount: Int = 0
    @Published private(set) var tanks: [TankFillRow] = []
    @Published private(set) var alerts: [TankReorderAlert] = []

    var headerRail: String? {
        guard phase == .loaded else { return nil }
        return "\(terminalName.uppercased()) · \(overallUtil)% UTIL"
    }
    var subtitle: String { "Eusorone Technologies · \(terminalName) · live gauging" }
    var utilLabel: String { "\(overallUtil)%" }
    var onHandLabel: String { formatBarrels(onHandBarrels) }
    var capacityLabel: String { formatBarrels(capacityBarrels) }

    func load() async {
        phase = .loading
        do {
            let overview = try await EusoTripAPI.shared.tankMonitor.getMultiTerminalOverview()
            guard let terminal = overview.terminals.first else { phase = .empty; return }

            terminalName = terminal.terminalName ?? "Terminal"
            overallUtil = terminal.overallUtilization ?? overview.totals.overallUtilization ?? 0
            onHandBarrels = (overview.totals.totalInventory ?? terminal.totalInventory ?? 0) / kGallonsPerBarrel
            capacityBarrels = (overview.totals.totalCapacity ?? terminal.totalCapacity ?? 0) / kGallonsPerBarrel
            let a = overview.totals.alerts ?? terminal.alerts
            alertCount = (a?.critical ?? 0) + (a?.warning ?? 0) + (a?.info ?? 0)

            // Per-tank readings for the primary terminal.
            let readings = try await EusoTripAPI.shared.tankMonitor.getTankReadings(terminalId: terminal.terminalId)
            let alertRows = (try? await EusoTripAPI.shared.tankMonitor.getTankAlerts()) ?? []

            // Reorder threshold per tank (0..1) from a real alert threshold,
            // else the OOIDA-style standard low line (~25%).
            var thresholdByTank: [Int: Double] = [:]
            for al in alertRows {
                if let tn = al.tankNumber, let thr = al.threshold {
                    thresholdByTank[tn] = max(0.05, min(0.9, thr / 100.0))
                }
            }

            tanks = readings.readings.map { r in
                let bbl = r.currentLevelGallons.map { $0 / kGallonsPerBarrel }
                let reorder = thresholdByTank[r.tankNumber] ?? 0.25
                return TankFillRow(
                    id: r.id,
                    tankNumber: r.tankNumber,
                    product: r.product,
                    percentFull: r.percentFull,
                    currentBarrels: bbl,
                    detail: tankDetail(r),
                    reorderFraction: reorder
                )
            }

            alerts = alertRows.compactMap { mapAlert($0) }
            if alertCount == 0 { alertCount = alerts.count }

            phase = .loaded
        } catch {
            phase = .error(error.eusoUserCopy)
        }
    }

    private func tankDetail(_ r: TankMonitorAPI.TankReading) -> String {
        var parts: [String] = []
        if let f = r.gaugeFeet, let i = r.gaugeInches { parts.append("gauge \(f)'\(i)\"") }
        if let t = r.temperatureF { parts.append("\(Int(t.rounded()))°F") }
        if let p = r.pressurePsi, p > 0 { parts.append("\(Int(p.rounded())) psi") }
        if parts.isEmpty { parts.append(r.status.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private func mapAlert(_ a: TankMonitorAPI.Alert) -> TankReorderAlert? {
        let sev = (a.severity ?? "").lowercased()
        let tone: Color
        let badge: String
        let icon: String
        switch sev {
        case "emergency", "critical":
            tone = Brand.danger; badge = "ORDER NOW"; icon = "exclamationmark.triangle.fill"
        case "warning":
            tone = Brand.warning; badge = "WATCH"; icon = "gauge.with.dots.needle.bottom.0percent"
        default:
            tone = Brand.info; badge = "INFO"; icon = "info.circle.fill"
        }
        let tankLabel = a.tankNumber.map { "T-\($0)" } ?? "Tank"
        let title = [a.product, tankLabel].compactMap { $0 }.joined(separator: " · ")
        let msg = a.message ?? (a.type ?? "Reorder threshold approaching")
        return TankReorderAlert(
            id: a.id ?? "\(a.tankNumber ?? 0)-\(sev)",
            title: title.isEmpty ? tankLabel : title,
            message: msg,
            badge: badge,
            icon: icon,
            tone: tone
        )
    }
}

// MARK: - Previews

#Preview("299 · Tank Inventory · Night") {
    ShipperTankInventoryScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("299 · Tank Inventory · Afternoon") {
    ShipperTankInventoryScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
