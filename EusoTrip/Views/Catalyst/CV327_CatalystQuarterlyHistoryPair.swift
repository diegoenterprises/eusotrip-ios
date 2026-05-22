//
//  CV327_CatalystQuarterlyHistoryPair.swift
//  EusoTrip — Catalyst · Quarterly History pair (CV327 + CV337).
//
//  Pixel-match to:
//    327 Catalyst Driver Quarterly History  (DR-001-EUSO · 2026 · YTD)
//    337 Catalyst Vehicle Quarterly History (TRK-001-PB579 · 2026 · YTD)
//
//  YTD rollup views — distinct from the Q1-specific 327B/337B
//  B-variants. Both share `CatalystYTDBody`. Body reads
//  `drivers.getPerformanceMetrics` (driver) or `fleet.getFleetStats`
//  (vehicle). Bottom nav frozen.
//

import SwiftUI

private struct CYDMetrics: Decodable, Hashable {
    let metrics: M?
    struct M: Decodable, Hashable {
        let totalMiles: Double?
        let totalLoads: Int?
        let onTimeDeliveryRate: Int?
    }
}
private struct CYDFleet: Decodable, Hashable {
    let totalVehicles: Int?
    let utilization: Int?
    let avgMpg: Double?
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
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
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
    @State private var fleetStats: CYDFleet?

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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(kind == .driver ? "CATALYST · DRIVER · QUARTERLY HISTORY"
                                     : "CATALYST · VEHICLE · QUARTERLY HISTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Quarterly history").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(kind == .driver ? "DR-001-EUSO · 2026 · ME" : "TRK-001-PB579 · 2026 · PB")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .driver ? "OWNER-OP SEAM · QUARTERLY BOOKS CLEAN"
                                     : "OWNER-OP SEAM · ASSET QUARTERLY BOOKS CLEAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(kind == .driver
                     ? "Catalyst rolls up driver · same companyId both sides · clean Schedule C quarters"
                     : "Catalyst rolls up asset · same companyId both sides · clean §168 depreciation quarters")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("YTD 2026 · Q1 closed · Q2 in progress · A+ composite holding").font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(kind == .driver ? "ME" : "PB").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind == .driver ? "Michael Eusorone · DR-001-EUSO" : "Peterbilt 579 · 2022 · TRK-001-PB579")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(kind == .driver ? "Eusotrans LLC · hired 2025-04-15 · ACH ····6411" : "Eusotrans LLC · owner-op · titled 2024-08-04")
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
                    ("YTD MILES",  milesFmt(m?.totalMiles ?? 18660),    "Q1 closed · Q2 in progress",  .blue),
                    ("YTD LOADS",  "\(m?.totalLoads ?? 18)",            "9 Q1 + 9 Q2 to date",         .blue),
                    ("YTD OTP",    "\(m?.onTimeDeliveryRate ?? 94)%",   "year-to-date avg",            .green),
                    ("GRADE",      "A+",                                "YTD composite",               .green),
                ]
            case .vehicle:
                let s = fleetStats
                return [
                    ("YTD MILES",  milesFmt(18660),                      "Q1 closed · Q2 in progress",  .blue),
                    ("YTD LOADS",  "18",                                  "asset utilization",          .blue),
                    ("UTIL",       "\(s?.utilization ?? 84)%",            "YTD avg · §168",            .green),
                    ("GRADE",      "A",                                    "asset YTD pillar",          .green),
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

    private var quartersCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("QUARTERS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                quarterRow("Q1 2026", "CLOSED", "$14,820 gross · 9 loads · 94% OTP", .green)
                quarterRow("Q2 2026", "IN PROGRESS", "in-flight · 9 loads to date · 95% OTP", .blue)
                quarterRow("Q3 2026", "QUEUED", "—", .gray)
                quarterRow("Q4 2026", "QUEUED", "—", .gray)
            }
        }
    }

    private func quarterRow(_ q: String, _ state: String, _ detail: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(q).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(state).font(.caption2.weight(.heavy)).foregroundStyle(color)
                }
                Text(detail).font(.caption2).foregroundStyle(palette.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .driver:  return "Q1 closed clean at 94% OTP. Q2 holding 95% — keep cadence to lock Schedule C through tax cabinet."
            case .vehicle: return "Q1 asset rollup closed at 84% utilization. §168 depreciation books reconcile through TaxBook auto-export."
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
            struct In: Encodable { let driverId: String; let period: String }
            do { driverMetrics = try await EusoTripAPI.shared.query("drivers.getPerformanceMetrics", input: In(driverId: "0", period: "year")) } catch { /* */ }
        case .vehicle:
            do { fleetStats = try await EusoTripAPI.shared.queryNoInput("fleet.getFleetStats") } catch { /* */ }
        }
    }
}

private func milesFmt(_ m: Double) -> String {
    if m >= 1000 { return String(format: "%.1fK", m / 1000) }
    return String(format: "%.0f", m)
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
