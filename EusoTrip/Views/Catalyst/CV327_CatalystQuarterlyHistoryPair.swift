//
//  CV327_CatalystQuarterlyHistoryPair.swift
//  EusoTrip — Catalyst · Quarterly History pair (CV327 + CV337).
//
//  Pixel-match to:
//    327 Catalyst Driver Quarterly History  (driver · YTD)
//    337 Catalyst Vehicle Quarterly History (vehicle · YTD)
//
//  YTD rollup views — distinct from the Q1-specific 327B/337B
//  B-variants. Both share `CatalystYTDBody`.
//
//  Data sources (zero fabrication):
//    • driver kind →
//        - catalysts.getMyDrivers → CatalystAPI.FleetDriver
//          (real driver id + name; identity strip).
//        - drivers.getPerformanceMetrics → DriversAPI.PerformanceScorecard
//          (real metrics.totalMiles / totalLoads / onTimeDeliveryRate over
//           the `year` window). NO grade, NO gross-revenue, NO per-quarter
//           rollup in this proc → those render honest "—" / EusoEmptyState.
//    • vehicle kind →
//        - fleet.listAssets → first FleetAsset.id (resolve a REAL vehicle).
//        - vehicles.getScorecardAxis → real vehicleName / companyName /
//          assetCode / titledAt / grade / composite (per-vehicle identity +
//          a real derived grade).
//        - fleet.getFleetStats → fleet-wide utilization + avgMpg (the only
//          fleet KPIs this proc emits). There is NO per-asset YTD miles /
//          loads / gross / per-quarter rollup in the schema → honest "—".
//
//  Identity is read STRICTLY from the live procs above — never a hardcoded
//  persona. The per-quarter gross/load/OTP rollup has no live source (no
//  quarter-rollup table); the QUARTERS card renders EusoEmptyState rather
//  than fabricated Q1/Q2/Q3/Q4 rows. Bottom nav frozen.
//

import SwiftUI

// drivers.getPerformanceMetrics — verbatim server shape (drivers.ts:586).
// Optional throughout so a null / zeroed envelope degrades into an honest
// "—" rather than crashing decode.
private struct CYDMetrics: Decodable, Hashable {
    let metrics: M?
    struct M: Decodable, Hashable {
        let totalMiles: Double?
        let totalLoads: Int?
        let onTimeDeliveryRate: Double?  // 0–100 (server rounds to int)
    }
}

// fleet.getFleetStats — subset iOS reads (fleet.ts:233 returns the wider set).
private struct CYDFleet: Decodable, Hashable {
    let totalVehicles: Int?
    let utilization: Int?
    let avgMpg: Double?
}

// vehicles.getScorecardAxis — real per-vehicle identity + derived grade
// (vehicles.ts:592). Optional throughout — a null server response (no db /
// no company / no matching vehicle) degrades into honest "—".
private struct CYDAxis: Decodable, Hashable {
    let vehicleId: String?
    let vehicleName: String?     // real make/model/year
    let companyName: String?     // real companies.name (nullable)
    let assetCode: String?       // "TRK-001"
    let titledAt: String?        // vehicle.createdAt date (nullable)
    let status: String?          // "PUBLISHED · LIVE" / "ARCHIVED"
    let grade: String?           // derived A–F
    let composite: Double?       // 0.00–1.00
}

enum CatalystYTDKind: String {
    case driver, vehicle
}

private struct CatalystYTDShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Fleet", systemImage: "truck.box.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Fleet",  systemImage: "truck.box.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CatalystYTDBody: View {
    let kind: CatalystYTDKind

    @Environment(\.palette) private var palette
    @State private var driverMetrics: CYDMetrics?
    @State private var driverId: String?
    @State private var driverName: String?
    @State private var fleetStats: CYDFleet?
    @State private var axis: CYDAxis?

    private let dash = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                identityRow
                kpiGrid
                quartersCard
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // Subhead: real driver id / real asset code · year window. No source → "—".
    private var subhead: String {
        switch kind {
        case .driver:
            return "\(nonEmptyCYD(driverId) ?? dash) · 2026 · YTD"
        case .vehicle:
            return "\(nonEmptyCYD(axis?.assetCode) ?? dash) · 2026 · YTD"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(kind == .driver ? "CATALYST · DRIVER · QUARTERLY HISTORY"
                                     : "CATALYST · VEHICLE · QUARTERLY HISTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Quarterly history").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subhead)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .driver ? "OWNER-OP SEAM · QUARTERLY BOOKS"
                                     : "OWNER-OP SEAM · ASSET QUARTERLY BOOKS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(kind == .driver
                     ? "Catalyst rolls up driver · same company both sides · Schedule C quarters"
                     : "Catalyst rolls up asset · same company both sides · §168 depreciation quarters")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("YTD 2026 · live metrics carry from the performance feed · per-quarter rollup not yet sourced").font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // Real identity from the live procs — never a hardcoded persona.
    private var identityRow: some View {
        let line1: String
        let line2: String
        let badge: String
        switch kind {
        case .driver:
            let name = nonEmptyCYD(driverName)
            let id = nonEmptyCYD(driverId)
            line1 = [name, id].compactMap { $0 }.joined(separator: " · ").nilIfEmptyCYD ?? dash
            line2 = dash  // no carrier name / hire date / ACH in the roster row
            badge = name?.split(separator: " ").first.map { String($0.prefix(2)).uppercased() } ?? dash
        case .vehicle:
            let name = nonEmptyCYD(axis?.vehicleName)
            let code = nonEmptyCYD(axis?.assetCode)
            line1 = [name, code].compactMap { $0 }.joined(separator: " · ").nilIfEmptyCYD ?? dash
            let company = nonEmptyCYD(axis?.companyName)
            let titled = nonEmptyCYD(axis?.titledAt).map { "titled \($0)" }
            line2 = [company, titled].compactMap { $0 }.joined(separator: " · ").nilIfEmptyCYD ?? dash
            badge = name?.split(separator: " ").first.map { String($0.prefix(2)).uppercased() } ?? dash
        }
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(badge).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(line1)
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(line2)
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .driver:
                let m = driverMetrics?.metrics
                return [
                    ("YTD MILES",  milesFmt(m?.totalMiles),               "year-to-date · live",         .blue),
                    ("YTD LOADS",  loadsFmt(m?.totalLoads),               "year-to-date · live",         .blue),
                    ("YTD OTP",    pctFmt(m?.onTimeDeliveryRate),         "year-to-date avg · live",     .green),
                    // PerformanceScorecard carries no composite grade → "—".
                    ("GRADE",      dash,                                  "no live composite grade",     palette.textTertiary),
                ]
            case .vehicle:
                let s = fleetStats
                let a = axis
                return [
                    // No per-asset YTD miles / loads in the schema → honest "—".
                    ("YTD MILES",  dash,                                  "no live per-asset rollup",    palette.textTertiary),
                    ("YTD LOADS",  dash,                                  "no live per-asset rollup",    palette.textTertiary),
                    ("UTIL",       pctIntFmt(s?.utilization),             "fleet · live · §168",         .green),
                    ("GRADE",      nonEmptyCYD(a?.grade) ?? dash,         "asset composite · §9.4",      .green),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    // Per-quarter rollup (gross / load count / OTP per quarter) has NO live
    // source — there is no quarter-rollup table in the schema. Render the
    // branded empty state rather than fabricated Q1/Q2/Q3/Q4 rows.
    private var quartersCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("QUARTERS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                EusoEmptyState(
                    systemImage: "calendar.badge.clock",
                    title: "No quarter rollup yet",
                    subtitle: kind == .driver
                        ? "Per-quarter gross, load count, and OTP roll up here once the quarterly-close table ships. Live YTD metrics are above."
                        : "Per-quarter §168 depreciation rollups appear here once the quarterly-close table ships. Live fleet metrics are above.",
                    comingSoon: true
                )
            }
        }
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .driver:
                return "YTD miles, loads, and OTP carry live from the performance feed. The per-quarter Schedule C rollup isn't sourced yet — it stays neutral until the quarterly-close table ships."
            case .vehicle:
                return "Fleet utilization and the asset composite grade carry live. The per-quarter §168 depreciation rollup isn't sourced yet — it stays neutral until the quarterly-close table ships."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        switch kind {
        case .driver:
            // Resolve the REAL driver (id + name) from the catalyst's roster,
            // then bind live YTD KPIs from drivers.getPerformanceMetrics.
            // No hardcoded driverId / persona.
            do {
                let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)
                guard let primary = roster.first else { return }
                driverId = primary.id
                driverName = primary.name
                struct In: Encodable { let driverId: String; let period: String }
                driverMetrics = try await EusoTripAPI.shared.query(
                    "drivers.getPerformanceMetrics",
                    input: In(driverId: primary.id, period: "year"))
            } catch { /* leave honest dashes */ }
        case .vehicle:
            // Fleet-wide live metrics (utilization / avgMpg).
            fleetStats = try? await EusoTripAPI.shared.queryNoInput("fleet.getFleetStats")
            // Resolve a REAL vehicleId from the signed-in company's fleet, then
            // pull the live scorecard axis (real identity + derived grade).
            do {
                let assets = try await EusoTripAPI.shared.fleet.listAssets()
                if let first = assets.items.first {
                    struct AxisIn: Encodable { let vehicleId: String }
                    axis = try await EusoTripAPI.shared.query(
                        "vehicles.getScorecardAxis", input: AxisIn(vehicleId: first.id))
                }
            } catch { /* honest "—" everywhere axis is absent */ }
        }
    }
}

// MARK: - Honest formatters (no invented fallbacks)

private func nonEmptyCYD(_ s: String?) -> String? {
    guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return s
}

private extension String {
    var nilIfEmptyCYD: String? {
        let t = trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

private func milesFmt(_ m: Double?) -> String {
    guard let m, m > 0 else { return "—" }
    if m >= 1000 { return String(format: "%.1fK", m / 1000) }
    return String(format: "%.0f", m)
}

private func loadsFmt(_ n: Int?) -> String {
    guard let n else { return "—" }
    return "\(n)"
}

private func pctFmt(_ v: Double?) -> String {
    guard let v else { return "—" }
    return "\(Int(v.rounded()))%"
}

private func pctIntFmt(_ v: Int?) -> String {
    guard let v else { return "—" }
    return "\(v)%"
}

// MARK: - Screens

struct CatalystDriverQuarterlyHistoryScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystYTDShell(theme: theme) { CatalystYTDBody(kind: .driver) } }
}
struct CatalystVehicleQuarterlyHistoryScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystYTDShell(theme: theme) { CatalystYTDBody(kind: .vehicle) } }
}

// MARK: - Previews

#Preview("CV327 YTD · Dark")    { CatalystDriverQuarterlyHistoryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV337 YTD · Light")   { CatalystVehicleQuarterlyHistoryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
