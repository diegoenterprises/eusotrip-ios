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
//  parameterized by `CatalystVehicleKind`.
//
//  ZERO-FABRICATION BINDING (2026-06-06):
//    • fleet.getFleetStats        → CVFleetStats  (utilization, avgMpg,
//      active/inTransit/available counts) — MCP-verified shape at
//      frontend/server/routers/fleet.ts:190.
//    • vehicles.getScorecardAxis  → CVScorecardAxis (vehicleName,
//      companyName, assetCode, titledAt, status, grade, composite,
//      laneAvgDelta) — MCP-verified at frontend/server/routers/vehicles.ts:532.
//      The server DERIVES composite/grade honestly from delivered-load
//      throughput (util+volume axes; mpg untelemetered) and returns `null`
//      when the vehicle / company can't be resolved, so it is decoded
//      optional and every field degrades to an honest "—".
//
//  NO server source exists for VIN, per-vehicle MPG/RPM, per-vehicle
//  90-day revenue / settlement line-items, year/class/CVSA, per-doc
//  compliance rows, SAFER/OOS, or per-quarter rollups — every such slot
//  renders an honest "—" rather than a fabricated literal or persona.
//  Bottom nav frozen (Catalyst: Home / Fleet / Wallet / Me).
//

import SwiftUI

// fleet.getFleetStats — bare object. Only the fields this screen reads are
// declared; all optional so a partial server response degrades gracefully.
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

// vehicles.getScorecardAxis — real vehicle identity + §9.4 composite
// headline. Server returns this object or `null`; decoded optional.
private struct CVScorecardAxis: Decodable, Hashable {
    let axisId: String?
    let vehicleId: String?
    let scoreId: String?
    let vehicleName: String?     // "Peterbilt 579 · 2022" (real make/model/year)
    let companyName: String?     // real companies.name (nullable)
    let assetCode: String?       // "TRK-001"
    let titledAt: String?        // vehicle createdAt date (nullable)
    let status: String?          // "PUBLISHED · LIVE" / "ARCHIVED"
    let grade: String?           // derived A–F
    let composite: Double?       // derived 0–1
    let laneAvgDelta: Double?    // vehicle composite − fleet mean
}

enum CatalystVehicleKind: String {
    case scorecard, profile, documents, analytics, settlements, onboarding, compliance
}

private struct CatalystVehicleConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let pillCopy: String
}

private extension CatalystVehicleKind {
    var config: CatalystVehicleConfig {
        switch self {
        case .scorecard:
            return .init(eyebrow: "CATALYST · VEHICLE · SCORECARD",
                         citation: "OWNER-OP SEAM · CLEAN ASSET",
                         title: "Vehicle scorecard",
                         pillCopy: "Catalyst tracks vehicle · same company both sides · clean depreciation books")
        case .profile:
            return .init(eyebrow: "CATALYST · VEHICLE · PROFILE",
                         citation: "OWNER-OP SEAM · CLEAN ASSET",
                         title: "Vehicle profile",
                         pillCopy: "Catalyst owns asset · same company both sides · clean depreciation books")
        case .documents:
            return .init(eyebrow: "CATALYST · VEHICLE · DOCUMENTS",
                         citation: "OWNER-OP SEAM · §396 EVIDENCE",
                         title: "Vehicle documents",
                         pillCopy: "Catalyst pins title + registration + cab card + inspection · clean §396 cabinet")
        case .analytics:
            return .init(eyebrow: "CATALYST · VEHICLE · ANALYTICS",
                         citation: "OWNER-OP SEAM · 90D ROLLING",
                         title: "Vehicle analytics",
                         pillCopy: "Catalyst dashboards asset · same company · clean rate-per-mile, MPG and dwell decomposition")
        case .settlements:
            return .init(eyebrow: "CATALYST · VEHICLE · LEDGER",
                         citation: "OWNER-OP SEAM · §396 CLEAN ASSET",
                         title: "Vehicle settlements",
                         pillCopy: "Catalyst earns on asset · same company both sides · clean depreciation books")
        case .onboarding:
            return .init(eyebrow: "CATALYST · VEHICLE · ONBOARD",
                         citation: "OWNER-OP SEAM · 5-STEP LADDER",
                         title: "Vehicle onboarding",
                         pillCopy: "Catalyst seats asset · same company · 5 onboarding pillars")
        case .compliance:
            return .init(eyebrow: "CATALYST · VEHICLE · COMPLIANCE",
                         citation: "OWNER-OP SEAM · §396 §393 §397",
                         title: "Vehicle compliance",
                         pillCopy: "Catalyst monitors asset · same company both sides · §396 §393 §397 record")
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
                trailing: [NavSlot(label: "Fleet",  systemImage: "truck.box.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private let kCVDash = "—"

private struct CatalystVehicleBody: View {
    let kind: CatalystVehicleKind

    // The focal asset for this scorecard. The septet screens are reached
    // from the Fleet roster, which passes the selected vehicleId; default
    // is the caller's first assigned asset (resolved server-side).
    let vehicleId: String

    @Environment(\.palette) private var palette
    @State private var stats: CVFleetStats?
    @State private var axis: CVScorecardAxis?

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

    // Subhead binds to the real asset identity (name · asset code · window).
    private var subhead: String {
        let name = axis?.vehicleName?.nilIfBlank ?? kCVDash
        let code = axis?.assetCode?.nilIfBlank ?? kCVDash
        return "\(name) · \(code) · last 90 days"
    }

    private func header(_ c: CatalystVehicleConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // Status pill caption binds to the real composite/grade/status from the
    // scorecard axis. When the axis is unresolved every token is "—".
    private var statusPill: String {
        switch kind {
        case .scorecard, .analytics:
            let grade = axis?.grade?.nilIfBlank ?? kCVDash
            let comp = axis?.composite.map { String(format: "%.2f", $0) } ?? kCVDash
            return "GRADE \(grade) · COMPOSITE \(comp)"
        default:
            return axis?.status?.nilIfBlank ?? kCVDash
        }
    }

    private func pill(_ c: CatalystVehicleConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(statusPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // Identity row binds to the real vehicle name / asset code / company.
    // VIN has no server source on this lane → omitted (no fabricated VIN).
    private var identityRow: some View {
        let name = axis?.vehicleName?.nilIfBlank ?? kCVDash
        let code = axis?.assetCode?.nilIfBlank ?? kCVDash
        let company = axis?.companyName?.nilIfBlank ?? kCVDash
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(assetMonogram).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) · \(code)").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(company) · owner-op").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    // Monogram from the real make initials; "—" when no name is resolved.
    private var assetMonogram: String {
        guard let name = axis?.vehicleName?.nilIfBlank else { return kCVDash }
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? kCVDash : initials.uppercased()
    }

    private var kpiGrid: some View {
        let s = stats
        let a = axis
        // Only KPIs with a live server source carry a value; every slot
        // with no real source renders "—" (no fabricated literal). Color
        // stays neutral textPrimary when the value is the honest dash so we
        // never paint a "—" green/success.
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scorecard:
                return [
                    kpi("GRADE",       a?.grade?.nilIfBlank,
                        a?.composite.map { "composite \(String(format: "%.2f", $0))" } ?? "—", .green),
                    kpi("UTILIZATION", s?.utilization.map { "\($0)%" },
                        "fleet · in-use share", .green),
                    kpi("MPG",         fmtCVMpg(s?.avgMpg),
                        "fleet · live fuel", .blue),
                    kpi("LANE Δ",      a?.laneAvgDelta.map { fmtSignedDelta($0) },
                        "vs fleet mean composite", .blue),
                ]
            case .profile:
                return [
                    kpi("VEHICLE",     a?.vehicleName?.nilIfBlank, "make · model · year", .blue),
                    kpi("ASSET",       a?.assetCode?.nilIfBlank,   "unit code", .blue),
                    kpi("TITLED",      a?.titledAt?.nilIfBlank,    "on record", .green),
                    kpi("STATUS",      activeStatus(s),            "live ops", .green),
                ]
            case .documents:
                // No per-doc compliance source on this lane → honest "—".
                return [
                    kpi("DOCS",        nil, "pinned · current", .blue),
                    kpi("TITLE",       nil, "—", .green),
                    kpi("INSURE",      nil, "—", .green),
                    kpi("ANNUAL",      nil, "—", .green),
                ]
            case .analytics:
                return [
                    // No per-vehicle RPM source → "—".
                    kpi("RPM",         nil,                   "rate per mile", .green),
                    kpi("MPG",         fmtCVMpg(s?.avgMpg),   "fleet · live fuel", .blue),
                    kpi("COMPOSITE",   a?.composite.map { String(format: "%.2f", $0) },
                        "§9.4 derived · 90d", .blue),
                    kpi("UTILIZATION", s?.utilization.map { "\($0)%" },
                        "fleet · in-use share", .green),
                ]
            case .settlements:
                // No per-vehicle 90d revenue / settlement line-items on this
                // lane → every settlement KPI is an honest "—".
                return [
                    kpi("REV-90D",     nil, "—", .green),
                    kpi("AVG/LOAD",    nil, "—", .blue),
                    kpi("PAYOUTS",     nil, "—", .green),
                    kpi("PENDING",     nil, "—", .green),
                ]
            case .onboarding:
                // No onboarding-step ladder source on this lane → "—".
                return [
                    kpi("STEPS",       nil, "terminal · ladder", .green),
                    kpi("PIN",         nil, "—", .green),
                    kpi("TITLE",       a?.titledAt?.nilIfBlank, "on record", .green),
                    kpi("STATUS",      a?.status?.nilIfBlank,   "asset state", .green),
                ]
            case .compliance:
                // No SAFER / OOS / §396 §393 §397 row source on this lane → "—".
                return [
                    kpi("SAFER",       nil, "—", .green),
                    kpi("OOS-YTD",     nil, "—", .green),
                    kpi("§396",        nil, "—", .green),
                    kpi("§393 §397",   nil, "—", .green),
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

    // KPI builder: a present value keeps its tint; an absent value renders
    // the honest dash in neutral textPrimary so the empty slot never reads
    // as a passing/green metric.
    private func kpi(_ label: String, _ value: String?, _ sub: String, _ tint: Color) -> (String, String, String, Color) {
        if let v = value?.nilIfBlank {
            return (label, v, sub, tint)
        }
        return (label, kCVDash, sub, palette.textPrimary)
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .scorecard:    return "Refresh weekly. Use this asset's composite as the carrier-pitch reference for the next pull."
            case .profile:      return "Confirm the asset record stays current — title, unit code and status drive the scorecard identity."
            case .documents:    return "Per-document compliance has no live feed on this lane yet — file the §396 cabinet to populate it."
            case .analytics:    return "Composite is derived from delivered-load throughput. Hold the cadence to defend the grade."
            case .settlements:  return "Per-vehicle settlement line-items have no live feed on this lane yet — see the Wallet ledger."
            case .onboarding:   return "Onboarding-step status has no live feed on this lane yet — seat the asset from the Fleet roster."
            case .compliance:   return "SAFER / OOS / §396 rows have no live feed on this lane yet — pull FMCSA to populate them."
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
        do {
            axis = try await EusoTripAPI.shared.query(
                "vehicles.getScorecardAxis",
                input: ScorecardAxisInput(vehicleId: vehicleId, axisId: nil)
            )
        } catch { /* axis stays nil → honest "—" everywhere */ }
    }

    private struct ScorecardAxisInput: Encodable {
        let vehicleId: String
        let axisId: String?
    }
}

// MPG formatter: real fleet avg when > 0, honest "—" otherwise (no 6.8 default).
private func fmtCVMpg(_ raw: Double?) -> String? {
    guard let v = raw, v > 0 else { return nil }
    return String(format: "%.1f", v)
}
private func fmtSignedDelta(_ v: Double) -> String {
    let sign = v >= 0 ? "+" : ""
    return "\(sign)\(String(format: "%.2f", v))"
}
private func activeStatus(_ s: CVFleetStats?) -> String? {
    guard let s, (s.inTransit ?? 0) + (s.available ?? 0) > 0 || (s.active ?? 0) > 0 else { return nil }
    return (s.inTransit ?? 0) > 0 ? "IN-TRANSIT" : "AVAILABLE"
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

// MARK: - Screens (CV330-CV336)

struct CatalystVehicleScorecardScreen: View {
    let theme: Theme.Palette
    var vehicleId: String = "1"
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .scorecard, vehicleId: vehicleId) } }
}
struct CatalystVehicleProfileScreen: View {
    let theme: Theme.Palette
    var vehicleId: String = "1"
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .profile, vehicleId: vehicleId) } }
}
struct CatalystVehicleDocumentsScreen: View {
    let theme: Theme.Palette
    var vehicleId: String = "1"
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .documents, vehicleId: vehicleId) } }
}
struct CatalystVehicleAnalyticsScreen: View {
    let theme: Theme.Palette
    var vehicleId: String = "1"
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .analytics, vehicleId: vehicleId) } }
}
struct CatalystVehicleSettlementsScreen: View {
    let theme: Theme.Palette
    var vehicleId: String = "1"
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .settlements, vehicleId: vehicleId) } }
}
struct CatalystVehicleOnboardingScreen: View {
    let theme: Theme.Palette
    var vehicleId: String = "1"
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .onboarding, vehicleId: vehicleId) } }
}
struct CatalystVehicleComplianceScreen: View {
    let theme: Theme.Palette
    var vehicleId: String = "1"
    var body: some View { CatalystVehicleShell(theme: theme) { CatalystVehicleBody(kind: .compliance, vehicleId: vehicleId) } }
}

// MARK: - Previews

#Preview("CV330 Score · Dark")    { CatalystVehicleScorecardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV331 Profile · Light") { CatalystVehicleProfileScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV332 Docs · Dark")     { CatalystVehicleDocumentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV333 Analytics · Light") { CatalystVehicleAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV334 Ledger · Dark")   { CatalystVehicleSettlementsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV335 Onboard · Light") { CatalystVehicleOnboardingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV336 Compliance · Dark") { CatalystVehicleComplianceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
