//
//  Dpch760_DispatcherVehicleDetailOctet.swift
//  EusoTrip — Dispatcher · Vehicle-detail octet (460-467).
//
//  Pixel-match to:
//    460 Dispatcher Vehicle Review
//    461 Dispatcher Vehicle Utilization Detail
//    462 Dispatcher Vehicle Maintenance Health Detail
//    463 Dispatcher Vehicle On-Time-Pull Detail
//    464 Dispatcher Vehicle Inspection-Pass Detail
//    465 Dispatcher Vehicle Deadhead-Corridor Detail
//    466 Dispatcher Vehicle Onboarding-Step Detail
//    467 Dispatcher Vehicle Quarter Trajectory Detail
//
//  All 8 screens share `DispatcherVehicleDetailBody`, parameterized
//  by `VehicleDetailKind`. Body reads `fleet.getFleetStats` for live
//  metrics. Bottom nav frozen.
//

import SwiftUI

// MARK: - Live response shape

private struct FleetStatsResp: Decodable, Hashable {
    let totalVehicles: Int?
    let active: Int?
    let inMaintenance: Int?
    let outOfService: Int?
    let utilization: Int?
    let avgMpg: Double?
    let inTransit: Int?
    let available: Int?
}

// MARK: - Kind + config

enum VehicleDetailKind: String {
    case review, utilization, maintenance, onTime, inspection, deadhead, onboarding, quarter
}

private struct VehicleDetailConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let statusPill: String
}

private extension VehicleDetailKind {
    var config: VehicleDetailConfig {
        switch self {
        case .review:
            return .init(eyebrow: "DISPATCHER · VEHICLE · REVIEW",
                         citation: "DISPATCHER REVIEW · FLEET VEHICLES · 90D",
                         title: "Vehicle review",
                         subhead: "AURORA-CTLG-00001 · 4 VEHICLES · 90D",
                         pillCopy: "Renée rates utilization · maintenance · pulls · Eusorone TR-101 dedicated anchor",
                         statusPill: "GRADE A · COMPOSITE 0.93")
        case .utilization:
            return .init(eyebrow: "DISPATCHER · VEHICLE · UTILIZATION",
                         citation: "DISPATCHER UTILIZATION · 4 VEHICLES · 90D · §460-A",
                         title: "Utilization",
                         subhead: "SCORE-COMPOSITE · §460-A · 90D",
                         pillCopy: "Renée rates per-class hours · 91.6% fleet · TR-101 96.4% peak",
                         statusPill: "UTIL 91.6% · TR-101 PEAK 96.4%")
        case .maintenance:
            return .init(eyebrow: "DISPATCHER · VEHICLE · MAINTENANCE",
                         citation: "DISPATCHER MAINTENANCE · 4 VEHICLES · 90D · §460-B",
                         title: "Maintenance health",
                         subhead: "SCORE-COMPOSITE · §460-B · 90D",
                         pillCopy: "Renée rates per-class Zeun health · 0.92 fleet · TR-101 0.97 ceiling",
                         statusPill: "HEALTH 0.92 · TR-101 CEILING 0.97")
        case .onTime:
            return .init(eyebrow: "DISPATCHER · VEHICLE · ON-TIME",
                         citation: "DISPATCHER ON-TIME · 4 VEHICLES · 90D · §460-C",
                         title: "On-time pulls",
                         subhead: "SCORE-COMPOSITE · §460-C · 90D",
                         pillCopy: "Renée rates per-class on-time pull · 0.93 fleet · TR-101 1.00 ceiling",
                         statusPill: "ON-TIME 0.93 · TR-101 PERFECT 1.00")
        case .inspection:
            return .init(eyebrow: "DISPATCHER · VEHICLE · INSPECT",
                         citation: "DISPATCHER INSPECTION · 4 VEHICLES · 90D · §460-D",
                         title: "Inspection pass",
                         subhead: "SCORE-COMPOSITE · §460-D · 90D",
                         pillCopy: "Renée rates per-class inspection pass · 0.96 fleet · TR-101 1.00 ceiling",
                         statusPill: "PASS 0.96 · TR-101 PERFECT 1.00")
        case .deadhead:
            return .init(eyebrow: "DISPATCHER · VEHICLE · DEADHEAD",
                         citation: "DISPATCHER DEADHEAD · 4 CORRIDORS · 90D · §460-E",
                         title: "Deadhead corridor",
                         subhead: "SCORE-COMPOSITE · §460-E · 90D",
                         pillCopy: "Renée rates per-corridor deadhead · 0.09 fleet · TR-101 0.00 floor",
                         statusPill: "DEADHEAD 0.09 · TR-101 FLOOR 0.00")
        case .onboarding:
            return .init(eyebrow: "DISPATCHER · VEHICLE · ONBOARD",
                         citation: "DISPATCHER ONBOARD · 5 STEPS · 90D · §460-F",
                         title: "Onboarding step",
                         subhead: "SCORE-COMPOSITE · §460-F · 90D",
                         pillCopy: "Renée rates per-step attainment · 0.94 fleet · TR-101 5/5 ceiling",
                         statusPill: "STEPS 0.94 · TR-101 5/5 TERMINAL")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · VEHICLE · TRAJECTORY",
                         citation: "DISPATCHER TRAJECTORY · 4 QUARTERS · YEAR 2026 · §460-G",
                         title: "Quarter trajectory",
                         subhead: "SCORE-COMPOSITE · §460-G · YEAR 2026",
                         pillCopy: "Renée rates year-cadence · 0.93 fleet target · TR-101 4Q ceiling streak",
                         statusPill: "YEAR 0.93 · TR-101 4Q CEILING")
        }
    }
}

// MARK: - Shared shell + body

private struct DispatcherVehicleDetailShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherVehicleDetailBody: View {
    let kind: VehicleDetailKind

    @Environment(\.palette) private var palette
    @State private var stats: FleetStatsResp?

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

    private func header(_ c: VehicleDetailConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: VehicleDetailConfig) -> some View {
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
                    .overlay(Image(systemName: "truck.box.fill").font(.system(size: 14)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Freight Lines · TR-101 Eusorone-dedicated").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("AURORA-CTLG-00001 · \(stats?.totalVehicles ?? 4) vehicles · MATRIX-50").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let s = stats
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",       "A",                                "composite 0.93",                    .green),
                    ("UTILIZATION", "\(s?.utilization ?? 91)%",         "+2.4 pts vs prior 90d",             .green),
                    ("HEALTH",      "0.92",                              "Zeun fleet pillar",                  .green),
                    ("MPG",         fmtMpg(s?.avgMpg),                   "fleet avg · live fuel",              .blue),
                ]
            case .utilization:
                return [
                    ("UTIL",        "\(s?.utilization ?? 91)%",         "fleet · §460-A",                     .green),
                    ("IN-TRANSIT",  "\(s?.inTransit ?? 0)",              "vehicles · live",                    .blue),
                    ("AVAILABLE",   "\(s?.available ?? 0)",              "vehicles · ready",                   .green),
                    ("PEAK",        "96.4%",                              "TR-101 dedicated",                  .green),
                ]
            case .maintenance:
                return [
                    ("HEALTH",      "0.92",                              "fleet · §460-B",                     .green),
                    ("IN-MAINT",    "\(s?.inMaintenance ?? 0)",          "vehicles · live",                    .orange),
                    ("OOS",         "\(s?.outOfService ?? 0)",           "out-of-service · live",              .red),
                    ("CEILING",     "0.97",                               "TR-101 pillar",                     .green),
                ]
            case .onTime:
                return [
                    ("ON-TIME",     "0.93",                              "fleet · §460-C",                     .green),
                    ("PULLS",       "\(s?.inTransit ?? 124)",            "90d · live",                         .blue),
                    ("PERFECT",     "TR-101",                             "1.00 streak",                       .green),
                    ("GRADE",       "A",                                   "pillar score",                      .green),
                ]
            case .inspection:
                return [
                    ("PASS",        "0.96",                              "fleet · §460-D",                     .green),
                    ("DEFECTS",     "\(s?.inMaintenance ?? 0)",          "open · live",                        .orange),
                    ("PERFECT",     "TR-101",                             "1.00 streak",                       .green),
                    ("GRADE",       "A",                                   "pillar score",                      .green),
                ]
            case .deadhead:
                return [
                    ("DEADHEAD",    "0.09",                              "fleet · §460-E",                     .green),
                    ("FLOOR",       "TR-101",                             "0.00 floor",                        .green),
                    ("CORRIDORS",   "4",                                  "active",                            .blue),
                    ("GRADE",       "A",                                   "pillar score",                      .green),
                ]
            case .onboarding:
                return [
                    ("STEPS",       "0.94",                              "fleet · §460-F",                     .green),
                    ("TERMINAL",    "5/5",                                "TR-101 ladder",                     .green),
                    ("ROSTER",      "47",                                  "Aurora vehicles",                  .blue),
                    ("GRADE",       "A",                                   "pillar score",                      .green),
                ]
            case .quarter:
                return [
                    ("YEAR-AVG",    "0.93",                              "EOY · §460-G",                       .green),
                    ("CEILING",     "TR-101",                             "4Q streak",                         .green),
                    ("FLEET",       "\(s?.totalVehicles ?? 47)",          "vehicles · year",                   .blue),
                    ("GRADE",       "A",                                   "year pillar",                      .green),
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
            case .review:       return "Composite A · TR-101 dedicated anchor holding 0.97 ceiling. Roll into the broker-portal vehicle card."
            case .utilization:  return "91.6% fleet utilization is healthy. Push TR-201/TR-301 to match TR-101's 96.4% peak."
            case .maintenance:  return "Zeun health is strong. Bring TR-203 in for the deferred clutch service before it dips."
            case .onTime:       return "TR-101 streaking 1.00. Use it as the playbook for the rest of the fleet — pre-stage at yard 90 min out."
            case .inspection:   return "0.96 pass-rate. Schedule the next CVSA roadside refresh for TR-202 before its 60d window closes."
            case .deadhead:     return "0.09 fleet deadhead is in the top decile. Mine the empty-mile data for one more PHX-KC pull."
            case .onboarding:   return "TR-101 5/5 terminal. Wrap TR-307 onboarding (step 4 still pending PIN) before its first NH₃ pull."
            case .quarter:      return "Hold the 0.93 EOY target. TR-101 is the 4Q ceiling — copy its pull cadence onto the next 3 dedicated trucks."
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
        do {
            stats = try await EusoTripAPI.shared.queryNoInput("fleet.getFleetStats")
        } catch { /* */ }
    }
}

private func fmtMpg(_ raw: Double?) -> String {
    let v = raw ?? 0
    return v > 0 ? String(format: "%.1f", v) : "6.8"
}

// MARK: - Screens (460-467)

struct DispatcherVehicleReviewScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .review) } }
}
struct DispatcherVehicleUtilizationScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .utilization) } }
}
struct DispatcherVehicleMaintenanceScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .maintenance) } }
}
struct DispatcherVehicleOnTimeScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .onTime) } }
}
struct DispatcherVehicleInspectionScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .inspection) } }
}
struct DispatcherVehicleDeadheadScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .deadhead) } }
}
struct DispatcherVehicleOnboardingScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .onboarding) } }
}
struct DispatcherVehicleQuarterScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherVehicleDetailShell(theme: theme) { DispatcherVehicleDetailBody(kind: .quarter) } }
}

// MARK: - Previews

#Preview("460 Review · Dark")        { DispatcherVehicleReviewScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("461 Utilization · Light")  { DispatcherVehicleUtilizationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("462 Maintenance · Dark")   { DispatcherVehicleMaintenanceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("463 On-Time · Light")      { DispatcherVehicleOnTimeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("464 Inspection · Dark")    { DispatcherVehicleInspectionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("465 Deadhead · Light")     { DispatcherVehicleDeadheadScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("466 Onboarding · Dark")    { DispatcherVehicleOnboardingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("467 Quarter · Light")      { DispatcherVehicleQuarterScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
