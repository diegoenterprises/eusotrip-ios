//
//  CV330_CatalystVehicleScorecardSeptet.swift
//  EusoTrip — Catalyst · Vehicle scorecard septet (CV330-CV336).
//
//  Pixel-match to:
//    330 Vehicle Performance Scorecard
//    331 Catalyst Vehicle Profile
//    332 Catalyst Vehicle Documents
//    333 Catalyst Vehicle Analytics
//    334 Catalyst Vehicle Settlements
//    335 Catalyst Vehicle Onboarding
//    336 Catalyst Vehicle Compliance
//
//  IDs prefixed `CV` (Catalyst Vehicle) to avoid collisions with
//  Shipper-side 330-336. All 7 share `CatalystVehicleBody`,
//  parameterized by `CatalystVehicleKind`. Body reads
//  `fleet.getFleetStats` for fleet-wide metrics + (optional)
//  `fleet.getVehicles` row for the focal truck. Bottom nav frozen
//  (Catalyst: Home / Fleet / Wallet / Me).
//

import SwiftUI

private struct CVFleetStats: Decodable, Hashable {
    let totalVehicles: Int?
    let active: Int?
    let inMaintenance: Int?
    let outOfService: Int?
    let utilization: Int?
    let avgMpg: Double?
    let inTransit: Int?
    let available: Int?
}

enum CatalystVehicleKind: String {
    case scorecard, profile, documents, analytics, settlements, onboarding, compliance
}

private struct CatalystVehicleConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let statusPill: String
}

private extension CatalystVehicleKind {
    var config: CatalystVehicleConfig {
        switch self {
        case .scorecard:
            return .init(eyebrow: "CATALYST · VEHICLE · SCORECARD",
                         citation: "OWNER-OP SEAM · CLEAN ASSET",
                         title: "Vehicle scorecard",
                         subhead: "Eusotrans LLC · Peterbilt 579 · VIN 1FUJGLDR8GLGT1842 · last 90 days",
                         pillCopy: "Catalyst tracks vehicle · same companyId both sides · clean depreciation books",
                         statusPill: "GRADE A · COMPOSITE 0.93")
        case .profile:
            return .init(eyebrow: "CATALYST · VEHICLE · PROFILE",
                         citation: "OWNER-OP SEAM · CLEAN ASSET",
                         title: "Vehicle profile",
                         subhead: "TRK-001-PB579 · 90D · PB",
                         pillCopy: "Catalyst owns asset · same companyId both sides · clean depreciation books",
                         statusPill: "PETERBILT 579 · 2022 · MC-306 · REEFER · CVSA L1")
        case .documents:
            return .init(eyebrow: "CATALYST · VEHICLE · DOCUMENTS",
                         citation: "OWNER-OP SEAM · §396 EVIDENCE",
                         title: "Vehicle documents",
                         subhead: "TRK-001-PB579 · 14 docs · all current",
                         pillCopy: "Catalyst pins title + registration + cab card + inspection · clean §396 cabinet",
                         statusPill: "TITLE · REG · CAB · ANNUAL ALL CURRENT")
        case .analytics:
            return .init(eyebrow: "CATALYST · VEHICLE · ANALYTICS",
                         citation: "OWNER-OP SEAM · 90D ROLLING",
                         title: "Vehicle analytics",
                         subhead: "TRK-001-PB579 · 9 loads · MPG / RPM / dwell",
                         pillCopy: "Catalyst dashboards asset · same companyId · clean rate-per-mile, MPG and dwell decomposition",
                         statusPill: "RPM $5.12 · MPG 6.8 · DWELL 0:48 AVG")
        case .settlements:
            return .init(eyebrow: "CATALYST · VEHICLE · LEDGER",
                         citation: "OWNER-OP SEAM · §396 CLEAN ASSET",
                         title: "Vehicle settlements",
                         subhead: "TRK-001-PB579 · 90D · 9 SETTLEMENTS",
                         pillCopy: "Catalyst earns on asset · same companyId both sides · clean depreciation books",
                         statusPill: "REV 90D $14,820 · 9 LOADS · GROSS")
        case .onboarding:
            return .init(eyebrow: "CATALYST · VEHICLE · ONBOARD",
                         citation: "OWNER-OP SEAM · 5-STEP LADDER",
                         title: "Vehicle onboarding",
                         subhead: "TRK-001-PB579 · 5/5 steps · terminal",
                         pillCopy: "Catalyst seats asset · same companyId · all 5 onboarding pillars closed by Eusotrans LLC",
                         statusPill: "TERMINAL · PIN · TITLE · INSURE · INSPECT · ROUTE")
        case .compliance:
            return .init(eyebrow: "CATALYST · VEHICLE · COMPLIANCE",
                         citation: "OWNER-OP SEAM · §396 §393 §397 CLEAN",
                         title: "Vehicle compliance",
                         subhead: "TRK-001-PB579 · §396 · 0 OOS YTD",
                         pillCopy: "Catalyst monitors asset · same companyId both sides · clean §396 §393 §397 record",
                         statusPill: "SAFER A · 0 OOS YTD · §396 §393 §397")
        }
    }
}

private struct CatalystVehicleShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Fleet", systemImage: "truck.box.fill",   isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CatalystVehicleBody: View {
    let kind: CatalystVehicleKind

    @Environment(\.palette) private var palette
    @State private var stats: CVFleetStats?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ c: CatalystVehicleConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: CatalystVehicleConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(c.statusPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("PB").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peterbilt 579 · 2022 · TRK-001-PB579").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Eusotrans LLC · owner-op · MC-306 · VIN 1FUJGLDR8GLGT1842").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let s = stats
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scorecard:
                return [
                    ("GRADE",       "A",                                 "composite 0.93",            .green),
                    ("UTILIZATION", "\(s?.utilization ?? 84)%",         "+3.2 pts vs prior 90d",      .green),
                    ("MPG",         fmtCVMpg(s?.avgMpg),                  "fleet · live fuel",          .blue),
                    ("LOADS-90D",   "9",                                  "Eusotrans LLC roster",       .blue),
                ]
            case .profile:
                return [
                    ("YEAR",        "2022",                              "Peterbilt 579",              .blue),
                    ("CLASS",       "REEFER",                              "53' · MC-306",              .blue),
                    ("CVSA",        "L1",                                  "passed · current annual",   .green),
                    ("STATUS",      activeStatus(s),                       "live ops",                  .green),
                ]
            case .documents:
                return [
                    ("DOCS",        "14",                                  "pinned · current",          .blue),
                    ("TITLE",       "OK",                                   "titled 2024-08-04",        .green),
                    ("INSURE",      "OK",                                   "MC-306 active",            .green),
                    ("ANNUAL",      "OK",                                   "CVSA L1 · 2026-01-12",     .green),
                ]
            case .analytics:
                return [
                    ("RPM",         "$5.12",                                "rate per mile",             .green),
                    ("MPG",         fmtCVMpg(s?.avgMpg),                    "90d · live fuel",           .blue),
                    ("DWELL",       "0:48",                                 "avg dock dwell",            .orange),
                    ("DEADHEAD",    "0.07",                                 "fleet pillar floor",        .green),
                ]
            case .settlements:
                return [
                    ("REV-90D",     "$14,820",                              "9 loads · gross",          .green),
                    ("AVG/LOAD",    "$1,647",                                "per load · 90d",           .blue),
                    ("PAYOUTS",     "9",                                     "NET-30 closed",           .green),
                    ("PENDING",     "0",                                     "AR clean",                .green),
                ]
            case .onboarding:
                return [
                    ("STEPS",       "5/5",                                  "terminal · ladder",        .green),
                    ("PIN",         "OK",                                   "ELD · gateway armed",      .green),
                    ("TITLE",       "OK",                                   "owner-op clean",           .green),
                    ("ROUTE",       "OK",                                   "first 9 loads live",       .green),
                ]
            case .compliance:
                return [
                    ("SAFER",       "A",                                    "FMCSA · 4 min ago",         .green),
                    ("OOS-YTD",     "0",                                    "no out-of-service",         .green),
                    ("§396",        "CLEAN",                                 "annual current",           .green),
                    ("§393 §397",   "CLEAN",                                  "no open defects",         .green),
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

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .scorecard:    return "A composite — refresh weekly. Use this asset as the carrier-pitch reference for next NH₃ pull."
            case .profile:      return "Peterbilt 579, 2022, owner-op — clean. Confirm MC-306 doesn't lapse before next §391 refresh."
            case .documents:    return "All 14 documents are current. Set a 60-day reminder before the CVSA L1 anniversary."
            case .analytics:    return "RPM $5.12, MPG 6.8 — solid. Mine the 0:48 dwell for one more loaded mile vs. dock idle."
            case .settlements:  return "$14,820 in 9 loads, 0 pending AR. Push a 10th load this 90-day window to close the rolling target."
            case .onboarding:   return "All 5 onboarding steps closed. Asset is fully seated — push to backhaul tender priority A."
            case .compliance:   return "SAFER A, 0 OOS YTD. Stay on the §396 + §397 cadence to hold the clean record."
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
        do { stats = try await EusoTripAPI.shared.queryNoInput("fleet.getFleetStats") } catch { /* */ }
    }
}

private func fmtCVMpg(_ raw: Double?) -> String {
    let v = raw ?? 6.8
    return String(format: "%.1f", v > 0 ? v : 6.8)
}
private func activeStatus(_ s: CVFleetStats?) -> String {
    (s?.inTransit ?? 0) > 0 ? "IN-TRANSIT" : "AVAILABLE"
}

// MARK: - Screens (CV330-CV336)

struct CatalystVehicleScorecardScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .scorecard) } }
}
struct CatalystVehicleProfileScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .profile) } }
}
struct CatalystVehicleDocumentsScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .documents) } }
}
struct CatalystVehicleAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .analytics) } }
}
struct CatalystVehicleSettlementsScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .settlements) } }
}
struct CatalystVehicleOnboardingScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .onboarding) } }
}
struct CatalystVehicleComplianceScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .compliance) } }
}

// MARK: - Previews

#Preview("CV330 Score · Dark")    { CatalystVehicleScorecardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV331 Profile · Light") { CatalystVehicleProfileScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV332 Docs · Dark")     { CatalystVehicleDocumentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV333 Analytics · Light") { CatalystVehicleAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV334 Ledger · Dark")   { CatalystVehicleSettlementsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV335 Onboard · Light") { CatalystVehicleOnboardingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV336 Compliance · Dark") { CatalystVehicleComplianceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
