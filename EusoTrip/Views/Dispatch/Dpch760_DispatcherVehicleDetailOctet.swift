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
//  fleet metrics + `fleet.getVehicles` for the focal-unit identity.
//  Bottom nav frozen.
//
//  ZERO-FABRICATION binding (2026-06-06):
//    • Every numeric KPI is bound to a REAL field returned by the
//      server proc `fleet.getFleetStats` (frontend/server/routers/fleet.ts:190).
//      Real fields: totalVehicles, total, active, inMaintenance,
//      maintenance, outOfService, utilization, inTransit, loading,
//      available, atShipper, atConsignee, offDuty, issues, avgMpg.
//    • There is NO backend source for a per-vehicle composite GRADE,
//      Zeun HEALTH score, ON-TIME / INSPECTION-PASS / DEADHEAD ratio,
//      ONBOARDING-step attainment, PEAK / CEILING / PERFECT marks, or a
//      per-quarter rollup — `zeun_maintenance` exposes inspection records
//      only (no graded health), and no getVehiclePerformance proc exists.
//      Those fields render an honest "—" (EM_DASH), never a literal.
//    • Identity comes from the FIRST real `fleet.getVehicles` row
//      (FleetVehicleRow: unitNumber/make/model/year), never a hardcoded
//      carrier persona.

import SwiftUI

// MARK: - Live response shape (fleet.getFleetStats — server-verified fields)

private struct FleetStatsResp: Decodable, Hashable {
    let totalVehicles: Int?
    let active: Int?
    let inMaintenance: Int?
    let outOfService: Int?
    let utilization: Int?
    let avgMpg: Double?
    let inTransit: Int?
    let available: Int?
    let issues: Int?
}

/// Honest absent-field placeholder — used wherever the server proc has no
/// matching field (per-vehicle grading, SLA/FTR ratios, per-quarter rollups).
private let EM_DASH = "—"

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
                         citation: "DISPATCHER REVIEW · FLEET VEHICLES · LIVE",
                         title: "Vehicle review",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "Fleet-wide utilization, maintenance status, and fuel economy are live. This vehicle is not graded on its own yet, so no grade is shown.",
                         statusPill: "GRADE \(EM_DASH) · not graded yet")
        case .utilization:
            return .init(eyebrow: "DISPATCHER · VEHICLE · UTILIZATION",
                         citation: "DISPATCHER UTILIZATION · FLEET VEHICLES · LIVE",
                         title: "Utilization",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "Fleet utilization = in-use ÷ total vehicles, live fleet-wide. This vehicle's own peak has no live source yet.",
                         statusPill: "UTIL — see fleet metric")
        case .maintenance:
            return .init(eyebrow: "DISPATCHER · VEHICLE · MAINTENANCE",
                         citation: "DISPATCHER MAINTENANCE · FLEET VEHICLES · LIVE",
                         title: "Maintenance health",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "In-maintenance and out-of-service counts are live fleet-wide. A Zeun health score for this vehicle is not measured yet.",
                         statusPill: "HEALTH \(EM_DASH) · no Zeun grade")
        case .onTime:
            return .init(eyebrow: "DISPATCHER · VEHICLE · ON-TIME",
                         citation: "DISPATCHER ON-TIME · FLEET VEHICLES · LIVE",
                         title: "On-time pulls",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "On-time-pull grading has no live data source yet. In-transit count is live from fleet stats.",
                         statusPill: "ON-TIME \(EM_DASH) · no live source")
        case .inspection:
            return .init(eyebrow: "DISPATCHER · VEHICLE · INSPECT",
                         citation: "DISPATCHER INSPECTION · FLEET VEHICLES · LIVE",
                         title: "Inspection pass",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "Inspection-pass grading is not measured yet — maintenance records are kept, but nothing scores them. Open-maintenance count is live.",
                         statusPill: "PASS \(EM_DASH) · no live source")
        case .deadhead:
            return .init(eyebrow: "DISPATCHER · VEHICLE · DEADHEAD",
                         citation: "DISPATCHER DEADHEAD · FLEET VEHICLES · LIVE",
                         title: "Deadhead corridor",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "Deadhead-corridor grading has no live data source yet.",
                         statusPill: "DEADHEAD \(EM_DASH) · no live source")
        case .onboarding:
            return .init(eyebrow: "DISPATCHER · VEHICLE · ONBOARD",
                         citation: "DISPATCHER ONBOARD · FLEET VEHICLES · LIVE",
                         title: "Onboarding step",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "Per-step onboarding attainment has no live data source yet. Total fleet count is live.",
                         statusPill: "STEPS \(EM_DASH) · no live source")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · VEHICLE · TRAJECTORY",
                         citation: "DISPATCHER TRAJECTORY · FLEET VEHICLES · LIVE",
                         title: "Quarter trajectory",
                         subhead: "FLEET VEHICLES · LIVE",
                         pillCopy: "Per-quarter trajectory rollups have no live data source yet. Total fleet count is live.",
                         statusPill: "YEAR \(EM_DASH) · no live source")
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
    @State private var focalVehicle: FleetVehicleRow?

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
        // Identity is the FIRST real fleet vehicle (fleet.getVehicles →
        // FleetVehicleRow). No carrier persona, no invented unit number.
        let v = focalVehicle
        let unit = v?.unitNumber ?? EM_DASH
        let makeModel: String = {
            let parts = [v?.make, v?.model].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? EM_DASH : parts.joined(separator: " ")
        }()
        let yearStr = v?.year.map { String($0) } ?? EM_DASH
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "truck.box.fill").font(.system(size: 14)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(unit) · \(makeModel)").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Year \(yearStr) · \(fmtInt(stats?.totalVehicles)) vehicles in fleet").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let s = stats
        // Every tile is either a REAL fleet.getFleetStats field or an honest
        // "—". No invented literals, no `?? <number>` defaults. The secondary
        // line states the real source (or "no live source") so an absent
        // value is never read as a graded result.
        let neutral = palette.textTertiary
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",       EM_DASH,                     "not graded yet",            neutral),
                    ("UTILIZATION", utilStr(s),                  "in-use ÷ total · live",        .green),
                    ("HEALTH",      EM_DASH,                     "no Zeun grade",                neutral),
                    ("MPG",         fmtMpg(s?.avgMpg),           "fleet avg · live fuel",        .blue),
                ]
            case .utilization:
                return [
                    ("UTIL",        utilStr(s),                  "in-use ÷ total · live",        .green),
                    ("IN-TRANSIT",  fmtInt(s?.inTransit),        "vehicles · live",              .blue),
                    ("AVAILABLE",   fmtInt(s?.available),        "vehicles · live",              .green),
                    ("PEAK",        EM_DASH,                     "no per-unit source",           neutral),
                ]
            case .maintenance:
                return [
                    ("HEALTH",      EM_DASH,                     "no Zeun grade",                neutral),
                    ("IN-MAINT",    fmtInt(s?.inMaintenance),    "vehicles · live",              .orange),
                    ("OOS",         fmtInt(s?.outOfService),     "out-of-service · live",        .red),
                    ("CEILING",     EM_DASH,                     "no per-unit source",           neutral),
                ]
            case .onTime:
                return [
                    ("ON-TIME",     EM_DASH,                     "no live source",               neutral),
                    ("IN-TRANSIT",  fmtInt(s?.inTransit),        "vehicles · live",              .blue),
                    ("PERFECT",     EM_DASH,                     "no per-unit source",           neutral),
                    ("GRADE",       EM_DASH,                     "not graded yet",            neutral),
                ]
            case .inspection:
                return [
                    ("PASS",        EM_DASH,                     "no live source",               neutral),
                    ("IN-MAINT",    fmtInt(s?.inMaintenance),    "open · live",                  .orange),
                    ("PERFECT",     EM_DASH,                     "no per-unit source",           neutral),
                    ("GRADE",       EM_DASH,                     "not graded yet",            neutral),
                ]
            case .deadhead:
                return [
                    ("DEADHEAD",    EM_DASH,                     "no live source",               neutral),
                    ("FLOOR",       EM_DASH,                     "no per-unit source",           neutral),
                    ("CORRIDORS",   EM_DASH,                     "no live source",               neutral),
                    ("GRADE",       EM_DASH,                     "not graded yet",            neutral),
                ]
            case .onboarding:
                return [
                    ("STEPS",       EM_DASH,                     "no live source",               neutral),
                    ("TERMINAL",    EM_DASH,                     "no per-unit source",           neutral),
                    ("ROSTER",      fmtInt(s?.totalVehicles),    "vehicles in fleet · live",     .blue),
                    ("GRADE",       EM_DASH,                     "not graded yet",            neutral),
                ]
            case .quarter:
                return [
                    ("YEAR-AVG",    EM_DASH,                     "no live source",               neutral),
                    ("CEILING",     EM_DASH,                     "no per-unit source",           neutral),
                    ("FLEET",       fmtInt(s?.totalVehicles),    "vehicles in fleet · live",     .blue),
                    ("GRADE",       EM_DASH,                     "not graded yet",            neutral),
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
            case .review:       return "Fleet utilization, maintenance status, and fuel economy are live fleet-wide. A composite grade for a single vehicle is not computed yet, so none is shown — judge this unit on the live numbers."
            case .utilization:  return "Utilization is live (in-use ÷ total vehicles). Per-vehicle peak utilization needs a per-unit metrics source that is not provisioned yet."
            case .maintenance:  return "In-maintenance and out-of-service counts are live. A Zeun health score for a single vehicle is not computed yet — inspection records are kept, but nothing scores them."
            case .onTime:       return "In-transit count is live. On-time-pull grading has no live source yet — pull timing is not measured, so no rate is shown."
            case .inspection:   return "Open-maintenance count is live. Inspection-pass grading is not measured yet, so no pass rate is shown."
            case .deadhead:     return "Deadhead-corridor grading has no live source yet — empty miles are not measured, so this lane stays blank."
            case .onboarding:   return "Total fleet count is live. Per-step onboarding attainment has no live source yet."
            case .quarter:      return "Total fleet count is live. Per-quarter trajectory rollups have no live source yet."
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
        } catch { /* leave nil → KPIs render honest "—" */ }
        // Per-unit identity: surface the FIRST real fleet vehicle (typed
        // FleetVehicleRow from fleet.getVehicles) instead of a hardcoded
        // carrier persona. No live source → identity falls back to "—".
        do {
            focalVehicle = try await EusoTripAPI.shared.fleetCanonical.getVehicles(limit: 1).first
        } catch { /* leave nil → identity renders honest "—" */ }
    }
}

/// Live fuel economy from `fleet.getFleetStats.avgMpg`. No invented fallback:
/// when the server reports 0 / nil (no fuel-txn data) we render an honest "—".
private func fmtMpg(_ raw: Double?) -> String {
    guard let v = raw, v > 0 else { return EM_DASH }
    return String(format: "%.1f", v)
}

/// Render an Int field honestly: nil → "—", otherwise the value.
private func fmtInt(_ v: Int?) -> String {
    guard let v = v else { return EM_DASH }
    return String(v)
}

/// Live utilization percent (in-use ÷ total) from `fleet.getFleetStats`.
/// nil → honest "—" (no invented "91%").
private func utilStr(_ s: FleetStatsResp?) -> String {
    guard let u = s?.utilization else { return EM_DASH }
    return "\(u)%"
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
