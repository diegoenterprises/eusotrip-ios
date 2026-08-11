//
//  CV330B_CatalystVehicleBVariantOctet.swift
//  EusoTrip — Catalyst · Vehicle B-variant deep-drill octet (330B-337B).
//
//  Pixel-match to:
//    330B Catalyst Vehicle Scorecard Axis Detail
//    331B Catalyst Vehicle Profile Tier Detail
//    332B Catalyst Vehicle Document Detail
//    333B Catalyst Vehicle Analytic Detail
//    334B Catalyst Vehicle Settlement Detail
//    335B Catalyst Vehicle Onboarding Step Detail
//    336B Catalyst Vehicle Compliance Row Detail
//    337B Catalyst Vehicle Quarter Detail
//
//  B-variants of the CV330-CV336 octet — one level deeper than the septet:
//  each surfaces a specific axis/row drill for the company's first fleet
//  asset. All 8 share `CatalystVehicleBBody`. Bottom nav frozen.
//
//  LIVE BINDINGS (zero fabrication):
//    • fleet.getFleetStats        → CVBFleetStats  (utilization / avgMpg)
//    • fleet.listAssets           → FleetAsset[]   (resolve a real vehicleId)
//    • vehicles.getScorecardAxis  → CVBScorecardAxis
//        (real vehicleName / companyName / assetCode / titledAt / scoreId /
//         status / grade / composite / laneAvgDelta — server vehicles.ts:532)
//
//  Identity (vehicle make/model/year, owner company, asset code, titled
//  date) is read STRICTLY from the live scorecard-axis proc — never a
//  hardcoded persona. Sub-fields with NO live source — per-allocation
//  settlement line-items, per-quarter gross rollups, per-doc / per-step /
//  per-compliance-row §-citation states, profile-tier grading — render an
//  honest "—" / EusoEmptyState, never a fabricated literal or a
//  §-citation MISSING/EXPIRED row. There is no scorecard-target,
//  tier, settlement-allocation, or per-doc-compliance table in the
//  schema, so those drills carry the honest neutral state.
//

import SwiftUI

// fleet.getFleetStats — subset iOS reads (fleet.ts:233 returns the wider set).
private struct CVBFleetStats: Decodable, Hashable {
    let totalVehicles: Int?
    let utilization: Int?
    let avgMpg: Double?
    let inMaintenance: Int?
}

// vehicles.getScorecardAxis — verbatim server return shape (vehicles.ts:592).
// Optional throughout so a null server response (no db / no company / no
// matching vehicle) degrades into an honest "—" rather than crashing decode.
private struct CVBScorecardAxis: Decodable, Hashable {
    let axisId: String?          // "COMPOSITE-<id>"
    let vehicleId: String?
    let scoreId: String?         // "SCORE-<id>-COMPOSITE"
    let vehicleName: String?     // "Peterbilt 579 · 2022" (real make/model/year)
    let companyName: String?     // owner company (nullable)
    let assetCode: String?       // "TRK-001"
    let titledAt: String?        // "2024-08-04" (vehicle.createdAt date, nullable)
    let status: String?          // "PUBLISHED · LIVE" / "ARCHIVED"
    let grade: String?           // "A" … "F"
    let composite: Double?       // 0.00–1.00
    let laneAvgDelta: Double?    // this vehicle's composite − fleet mean
}

enum CatalystVehicleBKind: String {
    case scoreAxis, profileTier, document, analytic, settlement, onboarding, compliance, quarter
}

// Static per-kind chrome copy. The eyebrow / title / citation anchor (§9.4,
// §13.4, §107.601, §396.17, §168) are published-spec SECTION LABELS, not
// data — they identify which compliance/scoring construct the drill is
// about. The live STATE of any of those constructs is sourced (or honestly
// "—") below; this struct never asserts a fabricated MISSING/EXPIRED state.
private struct CVBConfig {
    let eyebrow: String
    let citation: String        // spec section label only — no asserted state
    let title: String
    let pillCopy: String
}

private extension CatalystVehicleBKind {
    var config: CVBConfig {
        switch self {
        case .scoreAxis:
            return .init(eyebrow: "CATALYST · VEHICLE · SCORECARD AXIS",
                         citation: "§9.4 · COMPOSITE",
                         title: "Axis detail",
                         pillCopy: "Catalyst rates this asset on the §9.4 vehicle-composite axis · same company both sides.")
        case .profileTier:
            return .init(eyebrow: "CATALYST · VEHICLE · TIER",
                         citation: "§13.4 · TIER",
                         title: "Tier detail",
                         pillCopy: "Catalyst tier criteria (§13.4) apply to this asset · same company both sides.")
        case .document:
            return .init(eyebrow: "CATALYST · VEHICLE · DOCUMENT",
                         citation: "§107.601 · HAZMAT REG",
                         title: "Document detail",
                         pillCopy: "Catalyst archives this asset's §107.601 hazmat-registration document · same company both sides.")
        case .analytic:
            return .init(eyebrow: "CATALYST · VEHICLE · ANALYTIC",
                         citation: "§9.4 · MPG INDEX",
                         title: "Analytic detail",
                         pillCopy: "Catalyst tracks this asset's §9.4 mpg-index KPI · same company both sides.")
        case .settlement:
            return .init(eyebrow: "CATALYST · VEHICLE · SETTLEMENT",
                         citation: "§168(k) · DEPRECIATION",
                         title: "Settlement detail",
                         pillCopy: "Catalyst earns on this asset under §168(k) clean depreciation books · same company both sides.")
        case .onboarding:
            return .init(eyebrow: "CATALYST · ASSET · STEP DETAIL",
                         citation: "§396.17 · PERIODIC INSP",
                         title: "Step detail",
                         pillCopy: "Catalyst onboards this asset against the §396.17 periodic-inspection step · same company both sides.")
        case .compliance:
            return .init(eyebrow: "CATALYST · VEHICLE · COMPLIANCE ROW",
                         citation: "§397 · HAZMAT TRANSPORT",
                         title: "Compliance row",
                         pillCopy: "Catalyst monitors this asset's §397 hazmat-transport compliance row · same company both sides.")
        case .quarter:
            return .init(eyebrow: "CATALYST · VEHICLE · QUARTER DETAIL",
                         citation: "§168 · QUARTER ROLLUP",
                         title: "Quarter detail",
                         pillCopy: "Catalyst archives the §168 depreciation quarter rollup for this asset · same company both sides.")
        }
    }
}

private struct CatalystVehicleBShell<Content: View>: View {
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

private struct CatalystVehicleBBody: View {
    let kind: CatalystVehicleBKind

    @Environment(\.palette) private var palette
    @State private var stats: CVBFleetStats?
    @State private var axis: CVBScorecardAxis?
    @State private var loading = true

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                rowCard(c)
                identityRow
                kpiGrid(c)
                nextStepCard(c)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // Subhead: real asset code · spec section · real published status.
    // No source for assetCode/status → honest "—".
    private func subhead(_ c: CVBConfig) -> String {
        let code = nonEmpty(axis?.assetCode) ?? "—"
        let state = nonEmpty(axis?.status) ?? "—"
        return "\(code) · \(c.citation) · \(state)"
    }

    private func header(_ c: CVBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subhead(c)).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CVBConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · \(c.citation)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Row identity card. scoreId + grade + status come from the live axis
    // proc. The score axis is the only one of the eight rows backed by a
    // live derivation; the other seven (tier/doc/analytic/settlement/step/
    // compliance/quarter) have NO per-row table, so their row identity and
    // state render an honest "—" rather than a fabricated SCORE/DOC/ALLOC id.
    private func rowCard(_ c: CVBConfig) -> some View {
        let grade = nonEmpty(axis?.grade)
        let rowId: String? = (kind == .scoreAxis) ? nonEmpty(axis?.scoreId) : nil
        let state: String? = (kind == .scoreAxis) ? nonEmpty(axis?.status) : nil
        return LifecycleCard {
            HStack(spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(grade ?? "–").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowId ?? "—").font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(state ?? "No live row record").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    // Real vehicle identity from vehicles.getScorecardAxis — never hardcoded.
    private var identityRow: some View {
        let name = nonEmpty(axis?.vehicleName)
        let code = nonEmpty(axis?.assetCode)
        let line1: String = {
            switch (name, code) {
            case let (n?, c?): return "\(n) · \(c)"
            case let (n?, nil): return n
            case let (nil, c?): return c
            default: return "—"
            }
        }()
        let company = nonEmpty(axis?.companyName)
        let titled = nonEmpty(axis?.titledAt).map { "titled \($0)" }
        let line2 = [company, "owner-op", titled].compactMap { $0 }.joined(separator: " · ")
        let badge = name?.split(separator: " ").first.map { String($0.prefix(2)).uppercased() } ?? "—"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(badge).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(line1).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(line2.isEmpty ? "—" : line2).font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    // KPI grid. Bound to live fields where a source exists; honest "—" for
    // every sub-field with NO live source (settlement allocation amount/chain,
    // quarter gross rollup, per-doc/step/compliance-row state, tier grade).
    private func kpiGrid(_ c: CVBConfig) -> some View {
        let s = stats
        let a = axis
        let dash = "—"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scoreAxis:
                return [
                    ("GRADE",  nonEmpty(a?.grade) ?? dash,           "composite axis",      .green),
                    ("UTIL",   pct(s?.utilization),                  "fleet · §9.4",        .green),
                    ("MPG",    fmtCVBMpg(s?.avgMpg),                 "live fuel · §9.4",    .blue),
                    ("COMPST", fmtScore(a?.composite),               nonEmpty(a?.status) ?? dash, .green),
                ]
            case .profileTier:
                // No tier table in schema → tier / grade / effect have no live
                // source; only the §13.4 anchor and the company are real.
                return [
                    ("TIER",     dash,                                "no live tier record", palette.textTertiary),
                    ("CRITERIA", "§13.4",                             "tier criteria anchor", .blue),
                    ("ASSET",    nonEmpty(a?.assetCode) ?? dash,      nonEmpty(a?.companyName) ?? "owner", .blue),
                    ("EFFECT",   dash,                                "no live pillar effect", palette.textTertiary),
                ]
            case .document:
                // No per-doc compliance table → doc state / runway have no live
                // source. Never assert a §107.601 MISSING row.
                return [
                    ("DOC",    "HM-126F",                             "§107.601 hazmat reg", .blue),
                    ("STATE",  dash,                                  "no live doc record",  palette.textTertiary),
                    ("RUNWAY", dash,                                  "no live expiry",      palette.textTertiary),
                    ("OWNER",  nonEmpty(a?.companyName) ?? dash,      "asset owner",         .blue),
                ]
            case .analytic:
                return [
                    ("MPG",    fmtCVBMpg(s?.avgMpg),                 "fleet fuel · §9.4",   .blue),
                    ("IDX",    fmtDelta(a?.laneAvgDelta),            "composite vs fleet mean", .green),
                    ("COMPST", fmtScore(a?.composite),               nonEmpty(a?.status) ?? dash, .green),
                    ("PILLAR", "§9.4",                               "MPG index pillar",    .blue),
                ]
            case .settlement:
                // No settlement-allocation table for this drill → amount / chain
                // / due state have no live source. Never assert $1,320 / LD-…7E.
                return [
                    ("AMOUNT", dash,                                  "no live allocation",  palette.textTertiary),
                    ("CHAIN",  dash,                                  "no live POD chain",   palette.textTertiary),
                    ("STATE",  dash,                                  "no live settlement",  palette.textTertiary),
                    ("BOOK",   "§168(k)",                             "depreciation anchor", .blue),
                ]
            case .onboarding:
                // No per-step onboarding table → step state / runway have no live
                // source. Never assert a §396.17 EXPIRED row.
                return [
                    ("STEP",   "CVSA",                                "§396.17 periodic insp", .blue),
                    ("STATE",  dash,                                  "no live step record",  palette.textTertiary),
                    ("RUNWAY", dash,                                  "no live expiry",       palette.textTertiary),
                    ("OWNER",  nonEmpty(a?.companyName) ?? dash,      "asset owner",          .blue),
                ]
            case .compliance:
                // No per-compliance-row table → row state has no live source.
                return [
                    ("ROW",    "HM-126F",                             "§397 hazmat-transport", .blue),
                    ("STATE",  dash,                                  "no live compliance row", palette.textTertiary),
                    ("POOL",   "§397",                                "transport pillar",     .blue),
                    ("OWNER",  nonEmpty(a?.companyName) ?? dash,      "asset owner",          .blue),
                ]
            case .quarter:
                // No per-quarter rollup table → gross rollup / load count have no
                // live source. Never assert $14,820 / 9 loads.
                return [
                    ("Q",      dash,                                  "no live quarter close", palette.textTertiary),
                    ("ROLLUP", dash,                                  "no live gross rollup",  palette.textTertiary),
                    ("BOOK",   "§168",                                "depreciation anchor",   .blue),
                    ("STATE",  dash,                                  "no live QC record",     palette.textTertiary),
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

    private func nextStepCard(_ c: CVBConfig) -> some View {
        let copy: String = {
            switch kind {
            case .scoreAxis:
                let g = nonEmpty(axis?.grade)
                let sc = fmtScore(axis?.composite)
                if let g, sc != "—" {
                    return "Composite axis grade \(g) at \(sc), derived from live §9.4 util + volume. Refresh weekly with the next QC cycle."
                }
                return "Composite axis is derived from live §9.4 util + volume throughput. No graded record yet — refresh after the next delivered-load cycle."
            case .profileTier:
                return "No live §13.4 tier record for this asset yet. The tier table isn't in the schema; this drill stays neutral until it lands."
            case .document:
                return "§107.601 hazmat-registration document drill. No per-doc compliance record is sourced yet — the doc state stays neutral until the document store lands."
            case .analytic:
                let d = fmtDelta(axis?.laneAvgDelta)
                if d != "—" {
                    return "Composite index \(d) vs fleet mean, derived live. MPG carries from the fleet fuel feed (§9.4)."
                }
                return "MPG carries from the live fleet fuel feed (§9.4). No composite-vs-mean delta yet — refresh after more delivered loads."
            case .settlement:
                return "No per-allocation settlement line-item is sourced for this drill yet (no allocation table in the schema). Amount and POD chain stay neutral."
            case .onboarding:
                return "§396.17 periodic-inspection step drill. No per-step onboarding record is sourced yet — the step state stays neutral."
            case .compliance:
                return "§397 hazmat-transport compliance-row drill. No per-row compliance record is sourced yet — the row state stays neutral."
            case .quarter:
                return "No per-quarter §168 depreciation rollup is sourced for this drill yet (no quarter-rollup table in the schema). Gross and QC stay neutral."
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
        loading = true
        defer { loading = false }
        // Fleet-wide live metrics (utilization / avgMpg).
        stats = try? await EusoTripAPI.shared.queryNoInput("fleet.getFleetStats")
        // Resolve a REAL vehicleId from the signed-in company's fleet, then
        // pull the live scorecard axis for it. No hardcoded vehicleId.
        do {
            let assets: FleetAPI.AssetsResponse =
                try await EusoTripAPI.shared.queryNoInput("fleet.listAssets")
            if let first = assets.items.first {
                struct AxisIn: Encodable { let vehicleId: String }
                axis = try await EusoTripAPI.shared.query(
                    "vehicles.getScorecardAxis", input: AxisIn(vehicleId: first.id))
            }
        } catch { /* honest "—" everywhere axis is absent */ }
    }
}

// MARK: - Honest formatters (no invented fallbacks)

private func nonEmpty(_ s: String?) -> String? {
    guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return s
}

private func pct(_ v: Int?) -> String {
    guard let v else { return "—" }
    return "\(v)%"
}

private func fmtCVBMpg(_ raw: Double?) -> String {
    guard let v = raw, v > 0 else { return "—" }
    return String(format: "%.1f", v)
}

private func fmtScore(_ raw: Double?) -> String {
    guard let v = raw else { return "—" }
    return String(format: "%.2f", v)
}

private func fmtDelta(_ raw: Double?) -> String {
    guard let v = raw else { return "—" }
    return (v >= 0 ? "+" : "") + String(format: "%.2f", v)
}

// MARK: - Screens (CV330B-CV337B)

struct CatalystVehicleScoreAxisScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .scoreAxis) } }
}
struct CatalystVehicleProfileTierScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .profileTier) } }
}
struct CatalystVehicleDocumentDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .document) } }
}
struct CatalystVehicleAnalyticDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .analytic) } }
}
struct CatalystVehicleSettlementDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .settlement) } }
}
struct CatalystVehicleStepDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .onboarding) } }
}
struct CatalystVehicleComplianceRowScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .compliance) } }
}
struct CatalystVehicleQuarterDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .quarter) } }
}

// MARK: - Previews

#Preview("CV330B Axis · Dark")    { CatalystVehicleScoreAxisScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV331B Tier · Light")   { CatalystVehicleProfileTierScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV332B Doc · Dark")     { CatalystVehicleDocumentDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV333B Analytic · Light") { CatalystVehicleAnalyticDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV334B Settle · Dark")  { CatalystVehicleSettlementDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV335B Step · Light")   { CatalystVehicleStepDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV336B Comp · Dark")    { CatalystVehicleComplianceRowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV337B Q1 · Light")     { CatalystVehicleQuarterDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
